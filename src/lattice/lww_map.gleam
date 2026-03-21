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

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/string

/// A Last-Writer-Wins Map (LWW-Map) CRDT.
///
/// Internally stores each key with an `Option(String)` value and an `Int`
/// timestamp. A `None` value represents a tombstone (removed key). On merge,
/// the entry with the higher timestamp wins for each key. Equal timestamps are
/// resolved deterministically: tombstones win over active values, and active
/// values use lexicographic string order as a tiebreak.
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
/// On equal timestamps, tombstones win over active values and active values
/// use lexicographic string order as a deterministic tiebreak.
///
/// Merge is commutative, associative, and idempotent (a valid CRDT join).
pub fn merge(a: LWWMap, b: LWWMap) -> LWWMap {
  let LWWMap(da) = a
  let LWWMap(db) = b
  
  let merged = dict.fold(db, da, fn(acc, key, b_entry) {
    case dict.get(acc, key) {
      Ok(a_entry) -> dict.insert(acc, key, pick_winner(a_entry, b_entry))
      Error(Nil) -> dict.insert(acc, key, b_entry)
    }
  })
  
  LWWMap(merged)
}

fn pick_winner(
  a: #(Option(String), Int),
  b: #(Option(String), Int),
) -> #(Option(String), Int) {
  let #(_, ts_a) = a
  let #(_, ts_b) = b

  case int.compare(ts_a, ts_b) {
    Gt -> a
    Lt -> b
    Eq ->
      case compare_entries(a, b) {
        Gt | Eq -> a
        Lt -> b
      }
  }
}

fn compare_entries(
  a: #(Option(String), Int),
  b: #(Option(String), Int),
) -> Order {
  let #(value_a, _) = a
  let #(value_b, _) = b

  case value_a, value_b {
    None, None -> Eq
    None, Some(_) -> Gt
    Some(_), None -> Lt
    Some(val_a), Some(val_b) -> string.compare(val_a, val_b)
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
  let decoder = {
    use state <- decode.field("state", {
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      decode.success(LWWMap(entries: dict.from_list(entries_list)))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
