import gleam/dict
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
