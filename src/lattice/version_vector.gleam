import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

/// Represents the relative ordering of two version vectors
pub type Order {
  Before
  After
  Concurrent
  Equal
}

/// A version vector tracks logical clocks for each replica
pub type VersionVector {
  VersionVector(dict: dict.Dict(String, Int))
}

/// Create a new empty version vector
pub fn new() -> VersionVector {
  VersionVector(dict.new())
}

/// Increment the clock for a specific replica
pub fn increment(vv: VersionVector, replica_id: String) -> VersionVector {
  let VersionVector(dict) = vv
  let current = result.unwrap(dict.get(dict, replica_id), 0)
  VersionVector(dict.insert(dict, replica_id, current + 1))
}

/// Get the clock value for a specific replica
pub fn get(vv: VersionVector, replica_id: String) -> Int {
  let VersionVector(dict) = vv
  result.unwrap(dict.get(dict, replica_id), 0)
}

/// Compare two version vectors
/// Returns the ordering between them
pub fn compare(a: VersionVector, b: VersionVector) -> Order {
  let VersionVector(dict_a) = a
  let VersionVector(dict_b) = b
  let a_keys = dict.keys(dict_a)
  let b_keys = dict.keys(dict_b)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  compare_helper(dict_a, dict_b, all_keys, False, False)
}

fn compare_helper(
  a: dict.Dict(String, Int),
  b: dict.Dict(String, Int),
  keys: List(String),
  found_less: Bool,
  found_greater: Bool,
) -> Order {
  case keys {
    [] -> {
      case found_less, found_greater {
        False, False -> Equal
        True, False -> Before
        False, True -> After
        _, _ -> Concurrent
      }
    }
    [key, ..rest] -> {
      let a_val = result.unwrap(dict.get(a, key), 0)
      let b_val = result.unwrap(dict.get(b, key), 0)
      case a_val < b_val {
        True -> compare_helper(a, b, rest, True, found_greater)
        False -> {
          case a_val > b_val {
            True -> compare_helper(a, b, rest, found_less, True)
            False -> compare_helper(a, b, rest, found_less, found_greater)
          }
        }
      }
    }
  }
}

/// Encode a VersionVector as a self-describing JSON value.
/// Format: {"type": "version_vector", "v": 1, "state": {"clocks": {...}}}
pub fn to_json(vv: VersionVector) -> json.Json {
  let VersionVector(d) = vv
  json.object([
    #("type", json.string("version_vector")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("clocks", json.dict(d, fn(k) { k }, json.int)),
      ]),
    ),
  ])
}

/// Decode a VersionVector from a JSON string produced by to_json.
pub fn from_json(json_string: String) -> Result(VersionVector, json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use clocks <- decode.field(
        "clocks",
        decode.dict(decode.string, decode.int),
      )
      decode.success(VersionVector(dict: clocks))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}

/// Merge two version vectors using pairwise maximum
pub fn merge(a: VersionVector, b: VersionVector) -> VersionVector {
  let VersionVector(dict_a) = a
  let VersionVector(dict_b) = b
  let a_keys = dict.keys(dict_a)
  let b_keys = dict.keys(dict_b)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  VersionVector(merge_helper(dict_a, dict_b, all_keys, dict.new()))
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
