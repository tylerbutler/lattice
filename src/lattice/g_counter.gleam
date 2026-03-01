import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

/// A G-Counter is a grow-only counter CRDT
pub type GCounter {
  GCounter(dict: dict.Dict(String, Int), self_id: String)
}

/// Create a new G-Counter for the given replica
pub fn new(replica_id: String) -> GCounter {
  GCounter(dict.new(), replica_id)
}

/// Increment the counter by the given delta (must be non-negative)
pub fn increment(counter: GCounter, delta: Int) -> GCounter {
  let GCounter(dict, self_id) = counter
  let current = result.unwrap(dict.get(dict, self_id), 0)
  GCounter(dict.insert(dict, self_id, current + delta), self_id)
}

/// Get the value of the counter (sum of all replica counts)
pub fn value(counter: GCounter) -> Int {
  let GCounter(dict, _) = counter
  dict.fold(dict, 0, fn(acc, _key, value) { acc + value })
}

/// Merge two G-Counters using pairwise maximum
pub fn merge(a: GCounter, b: GCounter) -> GCounter {
  let GCounter(dict_a, self_id_a) = a
  let GCounter(dict_b, _) = b

  let a_keys = dict.keys(dict_a)
  let b_keys = dict.keys(dict_b)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  let merged_dict = merge_helper(dict_a, dict_b, all_keys, dict.new())

  // Keep the self_id from the first counter
  GCounter(merged_dict, self_id_a)
}

/// Encode a G-Counter as a self-describing JSON value.
/// Format: {"type": "g_counter", "v": 1, "state": {"self_id": "...", "counts": {...}}}
pub fn to_json(counter: GCounter) -> json.Json {
  let GCounter(d, self_id) = counter
  json.object([
    #("type", json.string("g_counter")),
    #("v", json.int(1)),
    #("state", json.object([
      #("self_id", json.string(self_id)),
      #("counts", json.dict(d, fn(k) { k }, json.int)),
    ])),
  ])
}

/// Decode a G-Counter from a JSON string produced by to_json.
pub fn from_json(json_string: String) -> Result(GCounter, json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", decode.string)
      use counts <- decode.field("counts", decode.dict(decode.string, decode.int))
      decode.success(GCounter(dict: counts, self_id: self_id))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}

fn merge_helper(
  a: dict.Dict(String, Int),
  b: dict.Dict(String, Int),
  keys: List(String),
  acc: dict.Dict(String, Int),
) -> dict.Dict(String, Int) {
  case keys {
    [] -> acc
    [key, ..rest] -> {
      let a_val = result.unwrap(dict.get(a, key), 0)
      let b_val = result.unwrap(dict.get(b, key), 0)
      let merged_val = case a_val > b_val {
        True -> a_val
        False -> b_val
      }
      let new_acc = dict.insert(acc, key, merged_val)
      merge_helper(a, b, rest, new_acc)
    }
  }
}
