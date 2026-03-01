import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/set
import lattice/crdt.{type Crdt, type CrdtSpec}
import lattice/or_set.{type ORSet}

/// An OR-Map (Observed-Remove Map) CRDT.
/// Keys are tracked using an OR-Set (add-wins semantics for concurrent
/// update vs remove conflicts). Values are Crdt union types which are
/// merged per-key on map merge.
pub type ORMap {
  ORMap(
    replica_id: String,
    crdt_spec: CrdtSpec,
    key_set: ORSet(String),
    values: dict.Dict(String, Crdt),
  )
}

fn spec_to_string(spec: CrdtSpec) -> String {
  case spec {
    crdt.GCounterSpec -> "g_counter"
    crdt.PnCounterSpec -> "pn_counter"
    crdt.LwwRegisterSpec -> "lww_register"
    crdt.MvRegisterSpec -> "mv_register"
    crdt.GSetSpec -> "g_set"
    crdt.TwoPSetSpec -> "two_p_set"
    crdt.OrSetSpec -> "or_set"
  }
}

fn string_to_spec(s: String) -> Result(CrdtSpec, Nil) {
  case s {
    "g_counter" -> Ok(crdt.GCounterSpec)
    "pn_counter" -> Ok(crdt.PnCounterSpec)
    "lww_register" -> Ok(crdt.LwwRegisterSpec)
    "mv_register" -> Ok(crdt.MvRegisterSpec)
    "g_set" -> Ok(crdt.GSetSpec)
    "two_p_set" -> Ok(crdt.TwoPSetSpec)
    "or_set" -> Ok(crdt.OrSetSpec)
    _ -> Error(Nil)
  }
}

/// Encode an OR-Map as a self-describing JSON value.
/// Nested OR-Set (key_set) and CRDT values are encoded as JSON strings
/// (double-encoded) so they can be decoded using the existing from_json APIs.
/// Format: {"type": "or_map", "v": 1, "state": {"replica_id": "...", "crdt_spec": "...", "key_set": "...", "values": [...]}}
pub fn to_json(map: ORMap) -> json.Json {
  let ORMap(replica_id, crdt_spec, key_set, values) = map
  let values_json =
    json.array(dict.to_list(values), fn(pair) {
      let #(key, crdt_val) = pair
      json.object([
        #("key", json.string(key)),
        #("crdt", json.string(json.to_string(crdt.to_json(crdt_val)))),
      ])
    })
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(replica_id)),
        #("crdt_spec", json.string(spec_to_string(crdt_spec))),
        #("key_set", json.string(json.to_string(or_set.to_json(key_set)))),
        #("values", values_json),
      ]),
    ),
  ])
}

/// Decode an OR-Map from a JSON string produced by to_json.
pub fn from_json(json_string: String) -> Result(ORMap, json.DecodeError) {
  let value_pair_decoder = {
    use key <- decode.field("key", decode.string)
    use crdt_str <- decode.field("crdt", decode.string)
    decode.success(#(key, crdt_str))
  }
  let decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use crdt_spec_str <- decode.field("crdt_spec", decode.string)
      use key_set_str <- decode.field("key_set", decode.string)
      use values_list <- decode.field("values", decode.list(value_pair_decoder))
      decode.success(#(replica_id, crdt_spec_str, key_set_str, values_list))
    })
    decode.success(state)
  }
  case json.parse(from: json_string, using: decoder) {
    Error(e) -> Error(e)
    Ok(#(replica_id, crdt_spec_str, key_set_str, values_list)) -> {
      case string_to_spec(crdt_spec_str) {
        Error(_) ->
          Error(json.UnableToDecode([
            decode.DecodeError(
              expected: "known CrdtSpec",
              found: crdt_spec_str,
              path: ["state", "crdt_spec"],
            ),
          ]))
        Ok(crdt_spec) -> {
          case or_set.from_json(key_set_str) {
            Error(e) -> Error(e)
            Ok(key_set) -> {
              let values_result =
                list.try_map(values_list, fn(pair) {
                  let #(key, crdt_str) = pair
                  case crdt.from_json(crdt_str) {
                    Ok(c) -> Ok(#(key, c))
                    Error(e) -> Error(e)
                  }
                })
              case values_result {
                Error(e) -> Error(e)
                Ok(pairs) ->
                  Ok(ORMap(
                    replica_id: replica_id,
                    crdt_spec: crdt_spec,
                    key_set: key_set,
                    values: dict.from_list(pairs),
                  ))
              }
            }
          }
        }
      }
    }
  }
}

/// Create a new empty OR-Map for the given replica with the specified CRDT type.
pub fn new(replica_id: String, crdt_spec: CrdtSpec) -> ORMap {
  ORMap(
    replica_id: replica_id,
    crdt_spec: crdt_spec,
    key_set: or_set.new(replica_id),
    values: dict.new(),
  )
}

/// Apply a function to the CRDT value at key, auto-creating it from crdt_spec
/// if the key doesn't exist. Adds the key to the OR-Set (marks it active).
pub fn update(map: ORMap, key: String, f: fn(Crdt) -> Crdt) -> ORMap {
  let current = case dict.get(map.values, key) {
    Ok(crdt_val) -> crdt_val
    Error(_) -> crdt.default_crdt(map.crdt_spec, map.replica_id)
  }
  let updated = f(current)
  ORMap(
    replica_id: map.replica_id,
    crdt_spec: map.crdt_spec,
    key_set: or_set.add(map.key_set, key),
    values: dict.insert(map.values, key, updated),
  )
}

/// Get the CRDT value at key.
/// Returns Ok(crdt) if the key is active in the OR-Set, Error(Nil) otherwise.
pub fn get(map: ORMap, key: String) -> Result(Crdt, Nil) {
  case or_set.contains(map.key_set, key) {
    True ->
      case dict.get(map.values, key) {
        Ok(val) -> Ok(val)
        Error(_) -> Error(Nil)
      }
    False -> Error(Nil)
  }
}

/// Remove a key from the OR-Map.
/// Only removes from the OR-Set (key becomes inactive); the value is retained
/// in the values dict so it can be merged if the key is re-added concurrently.
pub fn remove(map: ORMap, key: String) -> ORMap {
  ORMap(..map, key_set: or_set.remove(map.key_set, key))
}

/// Return the list of all active keys (those present in the OR-Set).
pub fn keys(map: ORMap) -> List(String) {
  set.to_list(or_set.value(map.key_set))
}

/// Return the CRDT values for all active keys.
pub fn values(map: ORMap) -> List(Crdt) {
  let active_keys = or_set.value(map.key_set)
  dict.fold(map.values, [], fn(acc, key, val) {
    case set.contains(active_keys, key) {
      True -> [val, ..acc]
      False -> acc
    }
  })
}

/// Merge two OR-Maps.
/// Key OR-Sets are merged with add-wins semantics (concurrent update beats remove).
/// CRDT values are merged per-key using the type-specific crdt.merge.
pub fn merge(a: ORMap, b: ORMap) -> ORMap {
  let merged_key_set = or_set.merge(a.key_set, b.key_set)
  let all_value_keys =
    list.unique(list.append(dict.keys(a.values), dict.keys(b.values)))
  let merged_values =
    list.fold(all_value_keys, dict.new(), fn(acc, key) {
      let merged_crdt = case dict.get(a.values, key), dict.get(b.values, key) {
        Ok(ca), Ok(cb) -> crdt.merge(ca, cb)
        Ok(ca), Error(_) -> ca
        Error(_), Ok(cb) -> cb
        Error(_), Error(_) -> panic as "unreachable: key must exist in at least one map"
      }
      dict.insert(acc, key, merged_crdt)
    })
  ORMap(
    replica_id: a.replica_id,
    crdt_spec: a.crdt_spec,
    key_set: merged_key_set,
    values: merged_values,
  )
}
