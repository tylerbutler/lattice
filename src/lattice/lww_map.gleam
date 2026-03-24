//// A last-writer-wins map (LWW-Map) CRDT.
////
//// Each key maps to a value and a timestamp. On conflict, the entry with the
//// higher timestamp wins. Removal is timestamp-based (tombstone): a remove at
//// timestamp T beats any set at timestamp < T. Keys are strings; values are
//// strings.
////
//// ## Example
////
//// ```gleam
//// import lattice/lww_map
////
//// let a = lww_map.new() |> lww_map.set("name", "Alice", 1)
//// let b = lww_map.new() |> lww_map.set("name", "Bob", 2)
//// let merged = lww_map.merge(a, b)
//// lww_map.get(merged, "name")  // -> Ok("Bob")
//// ```
////
//// ## Tombstone Management
////
//// Removing a key creates a tombstone that persists until pruned. Use
//// `tombstone_count` to monitor growth and `prune` to reclaim space once all
//// replicas have synced past a stable timestamp.
//// See [#18](https://github.com/tylerbutler/lattice/issues/18) for details.

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/string

/// A Last-Writer-Wins Map (LWW-Map) CRDT.
///
/// Internally stores each key with an `Option(String)` value and an `Int`
/// timestamp. A `None` value represents a tombstone (removed key). On merge,
/// the entry with the higher timestamp wins for each key; on ties, the first
/// argument's entry is kept as a consistent tiebreak.
///
/// Note: Tombstones accumulate until pruned. Use `prune` with a stable
/// timestamp to remove them. See the `prune` function documentation for
/// the safety contract. A future version will embed a `pruned_timestamp` in
/// the type for automatic zombie detection on merge; see
/// [#18](https://github.com/tylerbutler/lattice/issues/18).
pub type LWWMap {
  LWWMap(entries: dict.Dict(String, #(Option(String), Int)))
}

/// Create a new empty LWW-Map.
pub fn new() -> LWWMap {
  LWWMap(entries: dict.new())
}

/// Set a key to a value at the given timestamp.
///
/// If the key already has an entry with an equal or higher timestamp, the
/// existing entry is kept (LWW semantics: strictly greater timestamp wins).
pub fn set(map: LWWMap, key: String, value: String, timestamp: Int) -> LWWMap {
  let should_update = case dict.get(map.entries, key) {
    Error(_) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_update {
    True ->
      LWWMap(entries: dict.insert(map.entries, key, #(Some(value), timestamp)))
    False -> map
  }
}

/// Get the value for a key.
///
/// Returns `Ok(value)` if the key exists and is not tombstoned.
/// Returns `Error(Nil)` if the key is missing or has been removed.
pub fn get(map: LWWMap, key: String) -> Result(String, Nil) {
  case dict.get(map.entries, key) {
    Ok(#(Some(value), _)) -> Ok(value)
    _ -> Error(Nil)
  }
}

/// Remove a key at the given timestamp by inserting a tombstone.
///
/// If the key already has an entry with an equal or higher timestamp, the
/// remove is rejected and the existing entry wins.
///
/// Note: This operation creates a tombstone. Use `tombstone_count` to monitor
/// growth and `prune` with a stable timestamp to remove tombstones once all
/// replicas have observed them.
/// (See https://github.com/tylerbutler/lattice/issues/18)
pub fn remove(map: LWWMap, key: String, timestamp: Int) -> LWWMap {
  let should_remove = case dict.get(map.entries, key) {
    Error(_) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_remove {
    True -> LWWMap(entries: dict.insert(map.entries, key, #(None, timestamp)))
    False -> map
  }
}

/// Return all active (non-tombstoned) keys in the map.
///
/// Order is not guaranteed.
pub fn keys(map: LWWMap) -> List(String) {
  dict.fold(map.entries, [], fn(acc, key, entry) {
    case entry {
      #(Some(_), _) -> [key, ..acc]
      #(None, _) -> acc
    }
  })
}

/// Return the number of tombstoned (removed) entries in the map.
///
/// Useful for monitoring tombstone growth and deciding when to call `prune`.
/// (See https://github.com/tylerbutler/lattice/issues/18)
///
/// ## Examples
///
/// ```gleam
/// let m = lww_map.new()
///   |> lww_map.set("a", "1", 1)
///   |> lww_map.set("b", "2", 1)
///   |> lww_map.remove("a", 10)
/// lww_map.tombstone_count(m)  // -> 1
/// ```
pub fn tombstone_count(map: LWWMap) -> Int {
  dict.fold(map.entries, 0, fn(acc, _key, entry) {
    case entry {
      #(None, _) -> acc + 1
      #(Some(_), _) -> acc
    }
  })
}

/// Prune tombstones at or below the given stable timestamp.
///
/// Removes all tombstone entries (keys with `None` value) whose timestamp is
/// less than or equal to `stable_timestamp`. Active entries are never removed.
///
/// **Safety contract:** The caller must ensure that all replicas have merged
/// all operations with timestamps up to `stable_timestamp` before pruning.
/// If this invariant is violated, a pruned tombstone may fail to suppress an
/// older `set` arriving later via merge, causing the key to reappear with its
/// old value — known as the "zombie problem" in CRDT literature. If you cannot
/// guarantee all replicas have synced, prefer a conservative (older)
/// `stable_timestamp` or wait for the zombie-safe v2 API
/// ([#18](https://github.com/tylerbutler/lattice/issues/18)).
///
/// **Future:** A v2 of this function will add a `pruned_timestamp` field to the
/// `LWWMap` type, enabling automatic zombie detection on merge. This is a
/// breaking change tracked in
/// [#18](https://github.com/tylerbutler/lattice/issues/18). The current
/// `prune` function is safe to use today with proper coordination.
///
/// ## Examples
///
/// ```gleam
/// let m = lww_map.new()
///   |> lww_map.set("a", "alive", 1)
///   |> lww_map.remove("b", 5)
///   |> lww_map.remove("c", 15)
/// let pruned = lww_map.prune(m, 10)
/// lww_map.tombstone_count(pruned)  // -> 1 (only "c" at ts=15 remains)
/// lww_map.get(pruned, "a")         // -> Ok("alive")
/// ```
pub fn prune(map: LWWMap, stable_timestamp: Int) -> LWWMap {
  LWWMap(
    entries: dict.filter(map.entries, fn(_key, entry) {
      case entry {
        #(None, ts) -> ts > stable_timestamp
        #(Some(_), _) -> True
      }
    }),
  )
}

/// Return all active (non-tombstoned) values in the map.
///
/// Order is not guaranteed and does not correspond to the order of `keys`.
pub fn values(map: LWWMap) -> List(String) {
  dict.fold(map.entries, [], fn(acc, _key, entry) {
    case entry {
      #(Some(value), _) -> [value, ..acc]
      #(None, _) -> acc
    }
  })
}

/// Merge two LWW-Maps by resolving each key using the highest timestamp.
///
/// Tombstones participate in merge: if a tombstone has a higher timestamp
/// than the active entry for a key, the key remains removed after merging.
/// On equal timestamps, a deterministic tie-break is used:
/// tombstones win over active values, otherwise the lexicographically greater
/// value wins.
///
/// Merge is commutative, associative, and idempotent (a valid CRDT join).
pub fn merge(a: LWWMap, b: LWWMap) -> LWWMap {
  let all_keys =
    list.unique(list.append(dict.keys(a.entries), dict.keys(b.entries)))
  let merged =
    list.fold(all_keys, dict.new(), fn(acc, key) {
      let winner = case dict.get(a.entries, key), dict.get(b.entries, key) {
        Ok(ea), Ok(eb) -> {
          choose_winner(ea, eb)
        }
        Ok(ea), Error(_) -> ea
        Error(_), Ok(eb) -> eb
        Error(_), Error(_) ->
          panic as "unreachable: key in all_keys but not in either dict"
      }
      dict.insert(acc, key, winner)
    })
  LWWMap(entries: merged)
}

fn choose_winner(
  a: #(Option(String), Int),
  b: #(Option(String), Int),
) -> #(Option(String), Int) {
  let #(_, ts_a) = a
  let #(_, ts_b) = b
  case ts_a > ts_b {
    True -> a
    False ->
      case ts_b > ts_a {
        True -> b
        False ->
          case a, b {
            #(None, _), #(Some(_), _) -> a
            #(Some(_), _), #(None, _) -> b
            #(None, _), #(None, _) -> a
            #(Some(a_val), _), #(Some(b_val), _) ->
              case string.compare(a_val, b_val) {
                Gt -> a
                Eq -> a
                Lt -> b
              }
          }
      }
  }
}

/// Encode a `LWWMap` as a self-describing JSON value.
///
/// Entries are encoded as a JSON array where each element has `key`, `value`
/// (nullable string for tombstones), and `timestamp` fields.
///
/// Format: `{"type": "lww_map", "v": 1, "state": {"entries": [...]}}`
///
/// The encoded value can be restored with `from_json`.
pub fn to_json(map: LWWMap) -> json.Json {
  let LWWMap(entries) = map
  let entries_json =
    json.array(dict.to_list(entries), fn(pair) {
      let #(key, #(opt_value, timestamp)) = pair
      json.object([
        #("key", json.string(key)),
        #("value", case opt_value {
          Some(v) -> json.string(v)
          None -> json.null()
        }),
        #("timestamp", json.int(timestamp)),
      ])
    })
  json.object([
    #("type", json.string("lww_map")),
    #("v", json.int(1)),
    #("state", json.object([#("entries", entries_json)])),
  ])
}

/// Decode a `LWWMap` from a JSON string produced by `to_json`.
///
/// Returns `Error` if the string is not valid JSON or does not match the
/// expected format.
pub fn from_json(json_string: String) -> Result(LWWMap, json.DecodeError) {
  let entry_decoder = {
    use key <- decode.field("key", decode.string)
    use opt_value <- decode.field("value", decode.optional(decode.string))
    use timestamp <- decode.field("timestamp", decode.int)
    decode.success(#(key, #(opt_value, timestamp)))
  }
  let state_decoder = {
    use state <- decode.field("state", {
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      decode.success(LWWMap(entries: dict.from_list(entries_list)))
    })
    decode.success(state)
  }
  let envelope_decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(type_tag, version))
  }
  case json.parse(from: json_string, using: envelope_decoder) {
    Error(e) -> Error(e)
    Ok(#(type_tag, version)) ->
      case type_tag == "lww_map" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=lww_map and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}
