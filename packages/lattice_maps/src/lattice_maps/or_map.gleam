//// An observed-remove map (OR-Map) CRDT.
////
//// Keys are tracked using an OR-Set with add-wins semantics: concurrent update
//// and remove of the same key resolves in favor of the update. Each value is
//// itself a CRDT (specified by `CrdtSpec` at construction), enabling nested
//// convergent data structures.
////
//// ## Example
////
//// ```gleam
//// import lattice_maps/crdt
//// import lattice_core/replica_id
//// import lattice_counters/g_counter
//// import lattice_maps/or_map
////
//// let map = or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
////   |> or_map.update("score", fn(c) {
////     let assert crdt.CrdtGCounter(gc) = c
////     crdt.CrdtGCounter(g_counter.increment(gc, 10))
////   })
//// ```

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/set
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_maps/crdt.{type Crdt, type CrdtSpec}
import lattice_sets/or_set.{type ORSet}

/// An OR-Map (observed-remove map) CRDT.
///
/// Keys are tracked using an `ORSet(String)` which provides add-wins
/// semantics: if an update and a remove of the same key happen concurrently
/// on different replicas, the update wins after merging.
///
/// Values are stored as the `Crdt` tagged union so they can be merged
/// per-key using type-specific logic. The `crdt_spec` field records which
/// CRDT type is used for values, enabling auto-creation of default values
/// for new keys.
pub opaque type ORMap {
  ORMap(
    replica_id: ReplicaId,
    crdt_spec: CrdtSpec,
    key_set: ORSet(String),
    values: dict.Dict(String, Crdt),
    remove_bounds: dict.Dict(String, VersionVector),
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

/// Create a new empty OR-Map for the given replica with the specified CRDT type.
///
/// The `crdt_spec` determines what type of CRDT is auto-created when `update`
/// is called on a key that does not yet exist in the map.
pub fn new(replica_id: ReplicaId, crdt_spec: CrdtSpec) -> ORMap {
  ORMap(
    replica_id: replica_id,
    crdt_spec: crdt_spec,
    key_set: or_set.new(replica_id),
    values: dict.new(),
    remove_bounds: dict.new(),
  )
}

/// Apply a function to the CRDT value at `key`, auto-creating it if absent.
///
/// If the key does not exist, a default value is created from `crdt_spec`
/// and passed to `f`. The key is added to the OR-Set, marking it active.
/// The return value of `f` replaces (or sets) the value for that key.
///
/// See `update_with_delta` for the delta-state variant that also returns a
/// small payload suitable for incremental sync (e.g. over websockets).
pub fn update(map: ORMap, key: String, f: fn(Crdt) -> Crdt) -> ORMap {
  let current = current_value(map, key)
  let new_value = f(current)
  let safe_value = case matches_spec(new_value, map.crdt_spec) {
    True -> new_value
    False -> current
  }
  let #(updated, _) = put_value(map, key, safe_value)
  updated
}

/// Get the CRDT value at `key`.
///
/// Returns `Ok(crdt)` if the key is active in the OR-Set.
/// Returns `Error(Nil)` if the key has never been added, or has been removed
/// and not re-added.
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
///
/// Removes the key from the OR-Set (marking it inactive). The underlying
/// CRDT value is retained until prune determines the removal is causally
/// stable. A causal bound is recorded so prune can later decide when it is
/// safe to discard the value.
///
/// State-only convenience wrapper around `remove_with_delta` — the produced
/// delta is discarded. See `remove_with_delta` for the delta-state variant
/// that also returns a small payload suitable for incremental sync (e.g.
/// over websockets).
pub fn remove(map: ORMap, key: String) -> ORMap {
  let #(updated, _) = remove_with_delta(map, key)
  updated
}

/// Return the list of all active keys (those present in the OR-Set).
///
/// Order is not guaranteed.
pub fn keys(map: ORMap) -> List(String) {
  set.to_list(or_set.value(map.key_set))
}

/// Return the CRDT values for all active keys.
///
/// Order is not guaranteed and does not correspond to the order of `keys`.
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
///
/// The OR-Set key trackers are merged with add-wins semantics: if a key was
/// concurrently updated on one replica and removed on another, the key
/// survives in the merged result. CRDT values are merged per-key using
/// `crdt.merge` for type-specific convergence.
///
/// Returns `Error(TypeMismatch(...))` if the two maps have different
/// `crdt_spec` values (e.g., one holds counters and the other holds sets).
pub fn merge(a: ORMap, b: ORMap) -> Result(ORMap, crdt.MergeError) {
  case a.crdt_spec == b.crdt_spec {
    False ->
      Error(crdt.TypeMismatch(
        expected: spec_to_string(a.crdt_spec),
        found: spec_to_string(b.crdt_spec),
      ))
    True -> {
      let merged_key_set = or_set.merge(a.key_set, b.key_set)
      let active_keys = or_set.value(merged_key_set)
      let all_value_keys =
        set.to_list(set.union(
          set.from_list(dict.keys(a.values)),
          set.from_list(dict.keys(b.values)),
        ))
      let merged_values =
        list.fold(all_value_keys, dict.new(), fn(acc, key) {
          let merged_crdt = case valid_value(a, key), valid_value(b, key) {
            Ok(ca), Ok(cb) ->
              case crdt.merge(ca, cb) {
                Ok(merged) -> merged
                Error(_) -> crdt.default_crdt(a.crdt_spec, a.replica_id)
              }
            Ok(ca), Error(_) -> ca
            Error(_), Ok(cb) -> cb
            Error(_), Error(_) ->
              panic as "unreachable: key must exist in at least one map"
          }
          dict.insert(acc, key, merged_crdt)
        })

      // Merge remove_bounds: keep bounds for removed keys, clear for active keys
      let all_bound_keys =
        set.to_list(set.union(
          set.from_list(dict.keys(a.remove_bounds)),
          set.from_list(dict.keys(b.remove_bounds)),
        ))
      let merged_bounds =
        list.fold(all_bound_keys, dict.new(), fn(acc, key) {
          case set.contains(active_keys, key) {
            True -> acc
            False ->
              case
                dict.get(a.remove_bounds, key),
                dict.get(b.remove_bounds, key)
              {
                Ok(ba), Ok(bb) ->
                  dict.insert(acc, key, version_vector.merge(ba, bb))
                Ok(ba), Error(_) -> dict.insert(acc, key, ba)
                Error(_), Ok(bb) -> dict.insert(acc, key, bb)
                Error(_), Error(_) -> acc
              }
          }
        })

      Ok(ORMap(
        replica_id: a.replica_id,
        crdt_spec: a.crdt_spec,
        key_set: merged_key_set,
        values: merged_values,
        remove_bounds: merged_bounds,
      ))
    }
  }
}

/// Prune tombstones for keys and compact removed values whose removal is
/// causally stable.
///
/// Delegates to `or_set.prune` to remove tombstones from the internal key
/// tracker. Then, for each removed key that has a recorded causal bound, if
/// the pruned version vector dominates that bound, the key's CRDT value is
/// discarded (the removal is stable and no concurrent re-add can reference
/// the old value).
///
/// Only call this with a version vector representing events that have been
/// seen by all replicas (causally stable), otherwise zombie updates might be
/// incorrectly ignored.
pub fn prune(map: ORMap, stable_vv: VersionVector) -> ORMap {
  let pruned_key_set = or_set.prune(map.key_set, stable_vv)
  let pruned_vv = or_set.pruned_vv(pruned_key_set)
  let active_keys = or_set.value(pruned_key_set)

  let #(compacted_values, compacted_bounds) =
    dict.fold(map.values, #(dict.new(), map.remove_bounds), fn(acc, key, val) {
      let #(vals, bounds) = acc
      case set.contains(active_keys, key) {
        True -> #(dict.insert(vals, key, val), bounds)
        False ->
          case dict.get(map.remove_bounds, key) {
            Ok(bound) ->
              case version_vector.dominates(pruned_vv, bound) {
                True -> #(vals, dict.delete(bounds, key))
                False -> #(dict.insert(vals, key, val), bounds)
              }
            Error(_) -> #(dict.insert(vals, key, val), bounds)
          }
      }
    })

  ORMap(
    ..map,
    key_set: pruned_key_set,
    values: compacted_values,
    remove_bounds: compacted_bounds,
  )
}

/// Return the number of entries in the internal values dict.
///
/// This is an internal helper exposed for testing value compaction.
/// Active and retained-for-merge entries are both counted.
@internal
pub fn internal_value_count(map: ORMap) -> Int {
  dict.size(map.values)
}

/// Encode an `ORMap` as a self-describing JSON value.
///
/// The nested OR-Set (`key_set`) and CRDT values are double-encoded as JSON
/// strings so they can be decoded using the existing `from_json` APIs.
///
/// Format: `{"type": "or_map", "v": 2, "state": {"replica_id": "...", "crdt_spec": "...", "key_set": "...", "values": [...], "remove_bounds": {...}}}`
///
/// The encoded value can be restored with `from_json`.
pub fn to_json(map: ORMap) -> json.Json {
  let ORMap(rid, crdt_spec, key_set, values, remove_bounds) = map
  let values_json =
    json.array(dict.to_list(values), fn(pair) {
      let #(key, crdt_val) = pair
      json.object([
        #("key", json.string(key)),
        #("crdt", json.string(json.to_string(crdt.to_json(crdt_val)))),
      ])
    })
  let bounds_json =
    json.dict(remove_bounds, fn(k) { k }, fn(vv) { version_vector.to_json(vv) })
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(replica_id.to_string(rid))),
        #("crdt_spec", json.string(spec_to_string(crdt_spec))),
        #("key_set", json.string(json.to_string(or_set.to_json(key_set)))),
        #("values", values_json),
        #("remove_bounds", bounds_json),
      ]),
    ),
  ])
}

/// Decode an `ORMap` from a JSON string produced by `to_json`.
///
/// Supports both v1 (no remove_bounds) and v2 (with remove_bounds) formats.
/// v1 maps are decoded with empty remove_bounds, meaning no value compaction
/// is possible until new removes are performed.
///
/// Returns `Error` if the string is not valid JSON, does not match the
/// expected format, or contains an unknown `crdt_spec` string.
pub fn from_json(json_string: String) -> Result(ORMap, json.DecodeError) {
  let value_pair_decoder = {
    use key <- decode.field("key", decode.string)
    use crdt_str <- decode.field("crdt", decode.string)
    decode.success(#(key, crdt_str))
  }
  let bounds_decoder = decode.dict(decode.string, version_vector.decoder())
  let state_decoder = {
    use state <- decode.field("state", {
      use replica_id_str <- decode.field("replica_id", decode.string)
      use crdt_spec_str <- decode.field("crdt_spec", decode.string)
      use key_set_str <- decode.field("key_set", decode.string)
      use values_list <- decode.field("values", decode.list(value_pair_decoder))
      use remove_bounds <- decode.optional_field(
        "remove_bounds",
        dict.new(),
        bounds_decoder,
      )
      decode.success(#(
        replica_id_str,
        crdt_spec_str,
        key_set_str,
        values_list,
        remove_bounds,
      ))
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
      case type_tag == "or_map" {
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=or_map",
                found: type_tag,
                path: [],
              ),
            ]),
          )
        True ->
          case version {
            1 | 2 ->
              case json.parse(from: json_string, using: state_decoder) {
                Error(e) -> Error(e)
                Ok(#(
                  replica_id_str,
                  crdt_spec_str,
                  key_set_str,
                  values_list,
                  remove_bounds,
                )) ->
                  decode_or_map_state(
                    replica_id_str,
                    crdt_spec_str,
                    key_set_str,
                    values_list,
                    remove_bounds,
                  )
              }
            _ ->
              Error(
                json.UnableToDecode([
                  decode.DecodeError(
                    expected: "v=1 or v=2",
                    found: int.to_string(version),
                    path: ["v"],
                  ),
                ]),
              )
          }
      }
  }
}

fn decode_or_map_state(
  replica_id_str: String,
  crdt_spec_str: String,
  key_set_str: String,
  values_list: List(#(String, String)),
  remove_bounds: dict.Dict(String, VersionVector),
) -> Result(ORMap, json.DecodeError) {
  case string_to_spec(crdt_spec_str) {
    Error(_) ->
      Error(
        json.UnableToDecode([
          decode.DecodeError(
            expected: "known CrdtSpec",
            found: crdt_spec_str,
            path: ["state", "crdt_spec"],
          ),
        ]),
      )
    Ok(crdt_spec) ->
      case or_set.from_json(key_set_str) {
        Error(e) -> Error(e)
        Ok(key_set) -> {
          let values_result =
            list.try_map(values_list, fn(pair) {
              let #(key, crdt_str) = pair
              case crdt.from_json(crdt_str) {
                Ok(c) ->
                  case matches_spec(c, crdt_spec) {
                    True -> Ok(#(key, c))
                    False ->
                      Error(
                        json.UnableToDecode([
                          decode.DecodeError(
                            expected: spec_to_string(crdt_spec),
                            found: crdt_name(c),
                            path: ["state", "values"],
                          ),
                        ]),
                      )
                  }
                Error(e) -> Error(e)
              }
            })
          case values_result {
            Error(e) -> Error(e)
            Ok(pairs) ->
              Ok(ORMap(
                replica_id: replica_id.new(replica_id_str),
                crdt_spec: crdt_spec,
                key_set: key_set,
                values: dict.from_list(pairs),
                remove_bounds: remove_bounds,
              ))
          }
        }
      }
  }
}

fn matches_spec(value: Crdt, spec: CrdtSpec) -> Bool {
  case value, spec {
    crdt.CrdtGCounter(_), crdt.GCounterSpec -> True
    crdt.CrdtPnCounter(_), crdt.PnCounterSpec -> True
    crdt.CrdtLwwRegister(_), crdt.LwwRegisterSpec -> True
    crdt.CrdtMvRegister(_), crdt.MvRegisterSpec -> True
    crdt.CrdtGSet(_), crdt.GSetSpec -> True
    crdt.CrdtTwoPSet(_), crdt.TwoPSetSpec -> True
    crdt.CrdtOrSet(_), crdt.OrSetSpec -> True
    _, _ -> False
  }
}

fn valid_value(map: ORMap, key: String) -> Result(Crdt, Nil) {
  case dict.get(map.values, key) {
    Ok(value) ->
      case matches_spec(value, map.crdt_spec) {
        True -> Ok(value)
        False -> Ok(crdt.default_crdt(map.crdt_spec, map.replica_id))
      }
    Error(_) -> Error(Nil)
  }
}

fn crdt_name(value: Crdt) -> String {
  case value {
    crdt.CrdtGCounter(_) -> "g_counter"
    crdt.CrdtPnCounter(_) -> "pn_counter"
    crdt.CrdtLwwRegister(_) -> "lww_register"
    crdt.CrdtMvRegister(_) -> "mv_register"
    crdt.CrdtGSet(_) -> "g_set"
    crdt.CrdtTwoPSet(_) -> "two_p_set"
    crdt.CrdtOrSet(_) -> "or_set"
    crdt.CrdtVersionVector(_) -> "version_vector"
  }
}

// ----------------------------------------------------------------------------
// Delta-state API
//
// `update_with_delta` and `remove_with_delta` return both the new map state
// and an `ORMapDelta` capturing only the change. Deltas are merged into a
// remote replica via `apply_delta`, producing the same convergence as
// merging the full state but with much smaller payloads.
//
// See DEV.md "Delta-State CRDTs" for the contract and the "Operationalizing
// over websockets" section for transport guidance.
// ----------------------------------------------------------------------------

/// A delta describing changes to an `ORMap`.
///
/// Carries only the touched keys and their value-CRDT deltas, plus the
/// key-set delta from the underlying `ORSet`. The `crdt_spec` and
/// `replica_id` are included so `apply_delta` can validate and route the
/// merge correctly.
///
/// An `ORMapDelta` is structurally a sparse `ORMap`: it can be applied to
/// any remote `ORMap` of the same `crdt_spec` via `apply_delta`. Multiple
/// deltas can also be combined into a single delta via `merge_deltas`
/// before transmission.
pub opaque type ORMapDelta {
  ORMapDelta(
    replica_id: ReplicaId,
    crdt_spec: CrdtSpec,
    key_set_delta: ORSet(String),
    value_deltas: dict.Dict(String, Crdt),
    remove_bounds_delta: dict.Dict(String, VersionVector),
  )
}

/// Return the empty/identity delta for a map.
///
/// `apply_delta(m, empty_delta(m))` returns `m` unchanged. Useful as the
/// starting accumulator when folding multiple delta-producing operations.
pub fn empty_delta(map: ORMap) -> ORMapDelta {
  ORMapDelta(
    replica_id: map.replica_id,
    crdt_spec: map.crdt_spec,
    key_set_delta: or_set.new(map.replica_id),
    value_deltas: dict.new(),
    remove_bounds_delta: dict.new(),
  )
}

/// Apply a delta-producing function to the value at `key` and return both
/// the new map and a delta capturing only the change.
///
/// The callback `f` receives the current value (or a default if absent) and
/// must return a tuple `#(new_value, value_delta)`. Use the `_with_delta`
/// variants of the underlying CRDT modules (e.g. `g_counter.increment_with_delta`)
/// to produce the value delta:
///
/// ```gleam
/// or_map.update_with_delta(map, "score", fn(c) {
///   let assert crdt.CrdtGCounter(gc) = c
///   let #(new_gc, delta_gc) = g_counter.increment_with_delta(gc, 5)
///   #(crdt.CrdtGCounter(new_gc), crdt.CrdtGCounter(delta_gc))
/// })
/// ```
///
/// If the returned new value or delta does not match the map's `crdt_spec`,
/// both are coerced to the spec's default and an empty delta is emitted —
/// matching the safety behavior of `update`.
pub fn update_with_delta(
  map: ORMap,
  key: String,
  f: fn(Crdt) -> #(Crdt, Crdt),
) -> #(ORMap, ORMapDelta) {
  let current = current_value(map, key)
  let #(new_value, value_delta) = f(current)
  let #(safe_value, safe_delta) = case
    matches_spec(new_value, map.crdt_spec),
    matches_spec(value_delta, map.crdt_spec)
  {
    True, True -> #(new_value, value_delta)
    _, _ -> #(current, crdt.default_delta(map.crdt_spec, map.replica_id))
  }
  let #(updated, key_set_delta) = put_value(map, key, safe_value)
  let delta =
    ORMapDelta(
      replica_id: map.replica_id,
      crdt_spec: map.crdt_spec,
      key_set_delta: key_set_delta,
      value_deltas: dict.from_list([#(key, safe_delta)]),
      remove_bounds_delta: dict.new(),
    )
  #(updated, delta)
}

fn current_value(map: ORMap, key: String) -> Crdt {
  case or_set.contains(map.key_set, key), dict.get(map.values, key) {
    True, Ok(crdt_val) -> crdt_val
    _, _ -> crdt.default_crdt(map.crdt_spec, map.replica_id)
  }
}

fn put_value(map: ORMap, key: String, value: Crdt) -> #(ORMap, ORSet(String)) {
  let #(updated_key_set, key_set_delta) =
    or_set.add_with_delta(map.key_set, key)
  #(
    ORMap(
      replica_id: map.replica_id,
      crdt_spec: map.crdt_spec,
      key_set: updated_key_set,
      values: dict.insert(map.values, key, value),
      remove_bounds: dict.delete(map.remove_bounds, key),
    ),
    key_set_delta,
  )
}

/// Remove a key and return both the new map and a delta capturing the
/// remove.
///
/// The delta carries the OR-Set tombstones from `or_set.remove_with_delta`
/// and the recorded causal bound, which together let any remote replica
/// retract the key while preserving add-wins semantics for concurrent adds.
pub fn remove_with_delta(map: ORMap, key: String) -> #(ORMap, ORMapDelta) {
  let #(updated_key_set, key_set_delta) =
    or_set.remove_with_delta(map.key_set, key)
  let bound = or_set_bound_after_remove(map.key_set, key)
  let updated_bounds = case version_vector.is_empty(bound) {
    True -> map.remove_bounds
    False -> dict.insert(map.remove_bounds, key, bound)
  }
  let bounds_delta = case version_vector.is_empty(bound) {
    True -> dict.new()
    False -> dict.from_list([#(key, bound)])
  }
  let updated =
    ORMap(..map, key_set: updated_key_set, remove_bounds: updated_bounds)
  let delta =
    ORMapDelta(
      replica_id: map.replica_id,
      crdt_spec: map.crdt_spec,
      key_set_delta: key_set_delta,
      value_deltas: dict.new(),
      remove_bounds_delta: bounds_delta,
    )
  #(updated, delta)
}

fn or_set_bound_after_remove(
  key_set: ORSet(String),
  key: String,
) -> VersionVector {
  let #(_, bound) = or_set.remove_with_bound(key_set, key)
  bound
}

/// Apply a delta to a map, producing a new map.
///
/// Returns `Error(TypeMismatch(...))` if the delta and map have different
/// `crdt_spec` values. Otherwise reconstructs the delta as a sparse
/// `ORMap` and merges it via `merge`, so the returned map converges with
/// what would result from merging the delta source's full state.
///
/// Idempotent and commutative: applying the same delta twice, or applying
/// deltas in any order, yields the same final state.
pub fn apply_delta(
  map: ORMap,
  delta: ORMapDelta,
) -> Result(ORMap, crdt.MergeError) {
  case map.crdt_spec == delta.crdt_spec {
    False ->
      Error(crdt.TypeMismatch(
        expected: spec_to_string(map.crdt_spec),
        found: spec_to_string(delta.crdt_spec),
      ))
    True -> {
      let delta_as_map =
        ORMap(
          replica_id: delta.replica_id,
          crdt_spec: delta.crdt_spec,
          key_set: delta.key_set_delta,
          values: delta.value_deltas,
          remove_bounds: delta.remove_bounds_delta,
        )
      merge(map, delta_as_map)
    }
  }
}

/// Combine two deltas into a single delta.
///
/// Useful for transport layers that batch unacked deltas before
/// transmission: instead of sending N small deltas, merge them once and
/// send the join. Equivalent under `apply_delta` to applying both deltas
/// individually in either order.
///
/// Returns `Error(TypeMismatch(...))` if the two deltas have different
/// `crdt_spec` values.
pub fn merge_deltas(
  a: ORMapDelta,
  b: ORMapDelta,
) -> Result(ORMapDelta, crdt.MergeError) {
  case a.crdt_spec == b.crdt_spec {
    False ->
      Error(crdt.TypeMismatch(
        expected: spec_to_string(a.crdt_spec),
        found: spec_to_string(b.crdt_spec),
      ))
    True -> {
      let merged_key_set = or_set.merge(a.key_set_delta, b.key_set_delta)
      let all_value_keys =
        set.to_list(set.union(
          set.from_list(dict.keys(a.value_deltas)),
          set.from_list(dict.keys(b.value_deltas)),
        ))
      let merged_values =
        list.fold(all_value_keys, dict.new(), fn(acc, key) {
          let merged = case
            dict.get(a.value_deltas, key),
            dict.get(b.value_deltas, key)
          {
            Ok(va), Ok(vb) ->
              case crdt.merge(va, vb) {
                Ok(m) -> m
                Error(_) -> crdt.default_delta(a.crdt_spec, a.replica_id)
              }
            Ok(va), Error(_) -> va
            Error(_), Ok(vb) -> vb
            Error(_), Error(_) ->
              panic as "unreachable: key must exist in at least one delta"
          }
          dict.insert(acc, key, merged)
        })
      let all_bound_keys =
        set.to_list(set.union(
          set.from_list(dict.keys(a.remove_bounds_delta)),
          set.from_list(dict.keys(b.remove_bounds_delta)),
        ))
      let merged_bounds =
        list.fold(all_bound_keys, dict.new(), fn(acc, key) {
          case
            dict.get(a.remove_bounds_delta, key),
            dict.get(b.remove_bounds_delta, key)
          {
            Ok(ba), Ok(bb) ->
              dict.insert(acc, key, version_vector.merge(ba, bb))
            Ok(ba), Error(_) -> dict.insert(acc, key, ba)
            Error(_), Ok(bb) -> dict.insert(acc, key, bb)
            Error(_), Error(_) ->
              panic as "unreachable: key must exist in at least one delta"
          }
        })
      Ok(ORMapDelta(
        replica_id: a.replica_id,
        crdt_spec: a.crdt_spec,
        key_set_delta: merged_key_set,
        value_deltas: merged_values,
        remove_bounds_delta: merged_bounds,
      ))
    }
  }
}

/// Encode an `ORMapDelta` as a self-describing JSON value.
///
/// Format mirrors `to_json` for ORMap but uses `"type": "or_map_delta"`.
/// Use `delta_from_json` to decode.
pub fn delta_to_json(delta: ORMapDelta) -> json.Json {
  let ORMapDelta(rid, crdt_spec, key_set_delta, value_deltas, bounds_delta) =
    delta
  let values_json =
    json.array(dict.to_list(value_deltas), fn(pair) {
      let #(key, crdt_val) = pair
      json.object([
        #("key", json.string(key)),
        #("crdt", json.string(json.to_string(crdt.to_json(crdt_val)))),
      ])
    })
  let bounds_json =
    json.dict(bounds_delta, fn(k) { k }, fn(vv) { version_vector.to_json(vv) })
  json.object([
    #("type", json.string("or_map_delta")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(replica_id.to_string(rid))),
        #("crdt_spec", json.string(spec_to_string(crdt_spec))),
        #(
          "key_set_delta",
          json.string(json.to_string(or_set.to_json(key_set_delta))),
        ),
        #("value_deltas", values_json),
        #("remove_bounds_delta", bounds_json),
      ]),
    ),
  ])
}

/// Decode an `ORMapDelta` from a JSON string produced by `delta_to_json`.
pub fn delta_from_json(
  json_string: String,
) -> Result(ORMapDelta, json.DecodeError) {
  let value_pair_decoder = {
    use key <- decode.field("key", decode.string)
    use crdt_str <- decode.field("crdt", decode.string)
    decode.success(#(key, crdt_str))
  }
  let bounds_decoder = decode.dict(decode.string, version_vector.decoder())
  let state_decoder = {
    use state <- decode.field("state", {
      use replica_id_str <- decode.field("replica_id", decode.string)
      use crdt_spec_str <- decode.field("crdt_spec", decode.string)
      use key_set_str <- decode.field("key_set_delta", decode.string)
      use values_list <- decode.field(
        "value_deltas",
        decode.list(value_pair_decoder),
      )
      use bounds <- decode.optional_field(
        "remove_bounds_delta",
        dict.new(),
        bounds_decoder,
      )
      decode.success(#(
        replica_id_str,
        crdt_spec_str,
        key_set_str,
        values_list,
        bounds,
      ))
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
      case type_tag == "or_map_delta" {
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=or_map_delta",
                found: type_tag,
                path: [],
              ),
            ]),
          )
        True ->
          case version {
            1 ->
              case json.parse(from: json_string, using: state_decoder) {
                Error(e) -> Error(e)
                Ok(#(rid_str, spec_str, key_set_str, values_list, bounds)) ->
                  decode_or_map_delta_state(
                    rid_str,
                    spec_str,
                    key_set_str,
                    values_list,
                    bounds,
                  )
              }
            _ ->
              Error(
                json.UnableToDecode([
                  decode.DecodeError(
                    expected: "v=1",
                    found: int.to_string(version),
                    path: ["v"],
                  ),
                ]),
              )
          }
      }
  }
}

fn decode_or_map_delta_state(
  replica_id_str: String,
  crdt_spec_str: String,
  key_set_str: String,
  values_list: List(#(String, String)),
  bounds: dict.Dict(String, VersionVector),
) -> Result(ORMapDelta, json.DecodeError) {
  case string_to_spec(crdt_spec_str) {
    Error(_) ->
      Error(
        json.UnableToDecode([
          decode.DecodeError(
            expected: "known CrdtSpec",
            found: crdt_spec_str,
            path: ["state", "crdt_spec"],
          ),
        ]),
      )
    Ok(crdt_spec) ->
      case or_set.from_json(key_set_str) {
        Error(e) -> Error(e)
        Ok(key_set_delta) -> {
          let values_result =
            list.try_map(values_list, fn(pair) {
              let #(key, crdt_str) = pair
              case crdt.from_json(crdt_str) {
                Ok(c) ->
                  case matches_spec(c, crdt_spec) {
                    True -> Ok(#(key, c))
                    False ->
                      Error(
                        json.UnableToDecode([
                          decode.DecodeError(
                            expected: spec_to_string(crdt_spec),
                            found: crdt_name(c),
                            path: ["state", "value_deltas"],
                          ),
                        ]),
                      )
                  }
                Error(e) -> Error(e)
              }
            })
          case values_result {
            Error(e) -> Error(e)
            Ok(pairs) ->
              Ok(ORMapDelta(
                replica_id: replica_id.new(replica_id_str),
                crdt_spec: crdt_spec,
                key_set_delta: key_set_delta,
                value_deltas: dict.from_list(pairs),
                remove_bounds_delta: bounds,
              ))
          }
        }
      }
  }
}
