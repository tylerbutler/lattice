import gleam/dict
import gleam/list
import gleam/option.{type Option, None, Some}

/// A Last-Writer-Wins Map (LWW-Map) CRDT.
/// Each key maps to a value and a timestamp. On conflict, the entry with the
/// higher timestamp wins. Removal is tombstone-based: a remove stores None as
/// the value, so deleted keys stay gone across merges as long as the tombstone
/// has a higher timestamp.
pub type LWWMap {
  LWWMap(entries: dict.Dict(String, #(Option(String), Int)))
}

/// Create a new empty LWW-Map
pub fn new() -> LWWMap {
  LWWMap(entries: dict.new())
}

/// Set a key to a value at the given timestamp.
/// If the key already has an entry with an equal or higher timestamp,
/// the existing entry is kept (LWW semantics: strictly greater wins).
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
/// Returns Ok(value) if the key exists and is not tombstoned.
/// Returns Error(Nil) if the key is missing or has been removed.
pub fn get(map: LWWMap, key: String) -> Result(String, Nil) {
  case dict.get(map.entries, key) {
    Ok(#(Some(value), _)) -> Ok(value)
    _ -> Error(Nil)
  }
}

/// Remove a key at the given timestamp by inserting a tombstone.
/// If the key already has an entry with an equal or higher timestamp,
/// the remove is rejected (existing entry wins).
pub fn remove(map: LWWMap, key: String, timestamp: Int) -> LWWMap {
  let should_remove = case dict.get(map.entries, key) {
    Error(_) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_remove {
    True ->
      LWWMap(entries: dict.insert(map.entries, key, #(None, timestamp)))
    False -> map
  }
}

/// Return all active (non-tombstoned) keys in the map.
/// Order is not guaranteed.
pub fn keys(map: LWWMap) -> List(String) {
  dict.fold(map.entries, [], fn(acc, key, entry) {
    case entry {
      #(Some(_), _) -> [key, ..acc]
      #(None, _) -> acc
    }
  })
}

/// Return all active (non-tombstoned) values in the map.
/// Order is not guaranteed.
pub fn values(map: LWWMap) -> List(String) {
  dict.fold(map.entries, [], fn(acc, _key, entry) {
    case entry {
      #(Some(value), _) -> [value, ..acc]
      #(None, _) -> acc
    }
  })
}

/// Merge two LWW-Maps by resolving each key using the highest timestamp.
/// Tombstones participate in merge: if a tombstone has a higher timestamp
/// than the active entry for a key, the key remains removed.
/// On equal timestamps, the first argument's entry wins (consistent tiebreak).
pub fn merge(a: LWWMap, b: LWWMap) -> LWWMap {
  let all_keys =
    list.unique(list.append(dict.keys(a.entries), dict.keys(b.entries)))
  let merged =
    list.fold(all_keys, dict.new(), fn(acc, key) {
      let winner = case dict.get(a.entries, key), dict.get(b.entries, key) {
        Ok(ea), Ok(eb) -> {
          let #(_, ts_a) = ea
          let #(_, ts_b) = eb
          case ts_a >= ts_b {
            True -> ea
            False -> eb
          }
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
