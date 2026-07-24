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
//// import lattice_maps/lww_map
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
//// replicas have synced past a stable timestamp. The embedded
//// `pruned_timestamp` ensures that stale entries from unsynced replicas are
//// automatically rejected during merge (zombie prevention).

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/string

/// A Last-Writer-Wins Map (LWW-Map) CRDT.
///
/// Internally stores each key with an `Option(String)` value and an `Int`
/// timestamp. A `None` value represents a tombstone (removed key). On merge,
/// the entry with the higher timestamp wins for each key; on ties, tombstones
/// win over active values, otherwise the lexicographically greater value wins.
///
/// Tombstones accumulate until pruned. Use `prune` with a stable timestamp to
/// remove them. The embedded `pruned_timestamp` enables automatic zombie
/// detection on merge — entries from remote replicas at or below the pruned
/// threshold are discarded, preventing deleted keys from resurrecting.
pub opaque type LWWMap {
  LWWMap(
    entries: dict.Dict(String, #(Option(String), Int)),
    pruned_timestamp: Int,
  )
}

/// Create a new empty LWW-Map.
pub fn new() -> LWWMap {
  LWWMap(entries: dict.new(), pruned_timestamp: 0)
}

/// Return the pruned timestamp.
///
/// This is the highest stable timestamp passed to `prune`. Entries from remote
/// replicas with timestamps at or below this value are treated as zombies during
/// merge and discarded. A value of `0` means no pruning has occurred.
pub fn pruned_timestamp(map: LWWMap) -> Int {
  map.pruned_timestamp
}

/// Set a key to a value at the given timestamp.
///
/// If the key already has an entry with an equal or higher timestamp, the
/// existing entry is kept (LWW semantics: strictly greater timestamp wins).
pub fn set(
  map map: LWWMap,
  key key: String,
  value value: String,
  timestamp timestamp: Int,
) -> LWWMap {
  let should_update = case dict.get(map.entries, key) {
    Error(Nil) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_update {
    True ->
      LWWMap(
        ..map,
        entries: dict.insert(map.entries, key, #(Some(value), timestamp)),
      )
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
pub fn remove(
  map map: LWWMap,
  key key: String,
  timestamp timestamp: Int,
) -> LWWMap {
  let should_remove = case dict.get(map.entries, key) {
    Error(Nil) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_remove {
    True ->
      LWWMap(..map, entries: dict.insert(map.entries, key, #(None, timestamp)))
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
/// The `pruned_timestamp` is updated monotonically to `max(current, stable_timestamp)`.
///
/// After pruning, `merge` automatically detects zombie entries — entries from
/// remote replicas whose timestamps fall at or below the pruned threshold are
/// discarded, preventing deleted keys from resurrecting.
///
/// The `stable_timestamp` should ideally represent a point that all replicas
/// have synced past. Using a conservative (older) value is always safe; using
/// a value ahead of some replica means that replica's stale writes will be
/// silently dropped on merge (which is the correct behavior for pruned history).
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
  let new_pruned = int.max(map.pruned_timestamp, stable_timestamp)
  LWWMap(
    entries: dict.filter(map.entries, fn(_key, entry) {
      case entry {
        #(None, ts) -> ts > new_pruned
        #(Some(_), _) -> True
      }
    }),
    pruned_timestamp: new_pruned,
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
  let merged_pruned = int.max(a.pruned_timestamp, b.pruned_timestamp)
  let merged_from_a =
    dict.fold(a.entries, dict.new(), fn(acc, key, entry_a) {
      let entry = case dict.get(b.entries, key) {
        Ok(entry_b) -> Ok(choose_winner(entry_a, entry_b))
        Error(Nil) -> keep_if_not_zombie(entry_a, b.pruned_timestamp)
      }
      case entry {
        Ok(winner) -> dict.insert(acc, key, winner)
        Error(Nil) -> acc
      }
    })
  let merged =
    dict.fold(b.entries, merged_from_a, fn(acc, key, entry_b) {
      case dict.has_key(a.entries, key) {
        // Already resolved by choose_winner in the first fold.
        True -> acc
        False ->
          case keep_if_not_zombie(entry_b, a.pruned_timestamp) {
            Ok(winner) -> dict.insert(acc, key, winner)
            Error(Nil) -> acc
          }
      }
    })
  LWWMap(entries: merged, pruned_timestamp: merged_pruned)
}

/// An entry only present on one side is a zombie if its timestamp is at or
/// below the other side's pruned_timestamp — meaning the other side already
/// processed and garbage-collected the tombstone that would have suppressed it.
fn keep_if_not_zombie(
  entry: #(Option(String), Int),
  other_pruned: Int,
) -> Result(#(Option(String), Int), Nil) {
  let #(_, ts) = entry
  case ts <= other_pruned {
    True -> Error(Nil)
    False -> Ok(entry)
  }
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
/// (nullable string for tombstones), and `timestamp` fields. The
/// `pruned_timestamp` field records the highest stable timestamp passed to
/// `prune`, enabling zombie detection after deserialization.
///
/// Format: `{"type": "lww_map", "v": 2, "state": {"entries": [...], "pruned_timestamp": N}}`
///
/// The encoded value can be restored with `from_json`.
pub fn to_json(map: LWWMap) -> json.Json {
  let entries_json =
    json.array(dict.to_list(map.entries), fn(pair) {
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
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("entries", entries_json),
        #("pruned_timestamp", json.int(map.pruned_timestamp)),
      ]),
    ),
  ])
}

/// Decode a `LWWMap` from a JSON string produced by `to_json`.
///
/// Supports both v1 (no `pruned_timestamp`, defaults to 0) and v2 formats.
/// Returns `Error` if the string is not valid JSON or does not match the
/// expected format.
pub fn from_json(json_string: String) -> Result(LWWMap, json.DecodeError) {
  let entry_decoder = {
    use key <- decode.field("key", decode.string)
    use opt_value <- decode.field("value", decode.optional(decode.string))
    use timestamp <- decode.field("timestamp", decode.int)
    decode.success(#(key, #(opt_value, timestamp)))
  }
  let v1_state_decoder = {
    use state <- decode.field("state", {
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      decode.success(LWWMap(
        entries: dict.from_list(entries_list),
        pruned_timestamp: 0,
      ))
    })
    decode.success(state)
  }
  let v2_state_decoder = {
    use state <- decode.field("state", {
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      use pruned_ts <- decode.field("pruned_timestamp", decode.int)
      decode.success(LWWMap(
        entries: dict.from_list(entries_list),
        pruned_timestamp: pruned_ts,
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
      case type_tag == "lww_map", version {
        True, 1 -> json.parse(from: json_string, using: v1_state_decoder)
        True, 2 -> json.parse(from: json_string, using: v2_state_decoder)
        _, _ ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=lww_map and v=1 or v=2",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}
