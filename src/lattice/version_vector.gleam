//// A version vector for tracking causal ordering between replicas.
////
//// Each replica has a logical clock (monotonically increasing integer). Version
//// vectors enable detecting whether two states are causally ordered (one happened
//// before the other) or concurrent (neither dominates). Merge takes the pairwise
//// maximum of all clocks.
////
//// ## Example
////
//// ```gleam
//// import lattice/version_vector
////
//// let a = version_vector.new()
////   |> version_vector.increment("node-a")
////   |> version_vector.increment("node-a")
//// let b = version_vector.new()
////   |> version_vector.increment("node-b")
//// version_vector.compare(a, b)  // -> Concurrent
//// ```

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result

/// The causal ordering relationship between two version vectors.
///
/// - `Before`: the first vector happened before the second (all clocks <=,
///   at least one strictly <)
/// - `After`: the first vector happened after the second (all clocks >=,
///   at least one strictly >)
/// - `Concurrent`: neither dominates — the states diverged; at least one
///   clock is strictly greater in each direction
/// - `Equal`: both vectors have identical clocks for all replicas
pub type Order {
  Before
  After
  Concurrent
  Equal
}

/// A version vector tracking logical clocks for each replica.
///
/// Internally holds a dictionary from replica ID to clock value. The type is
/// opaque: use `new`, `increment`, `get`, `compare`, and `merge` to interact
/// with it. Serialization helpers `to_dict` and `from_dict` are provided for
/// JSON encoding and decoding.
pub opaque type VersionVector {
  VersionVector(dict: dict.Dict(String, Int))
}

/// Create a new empty version vector.
///
/// All replica clocks start at zero (missing entries are treated as zero).
pub fn new() -> VersionVector {
  VersionVector(dict.new())
}

/// Increment the clock for a specific replica.
///
/// Returns a new version vector with `replica_id`'s clock increased by one.
/// This is the standard way to record a new event at `replica_id`.
pub fn increment(vv: VersionVector, replica_id: String) -> VersionVector {
  let VersionVector(dict) = vv
  let current = result.unwrap(dict.get(dict, replica_id), 0)
  VersionVector(dict.insert(dict, replica_id, current + 1))
}

/// Get the clock value for a specific replica.
///
/// Returns `0` if `replica_id` has not been seen (missing entries default
/// to zero, consistent with the version vector semantics).
pub fn get(vv: VersionVector, replica_id: String) -> Int {
  let VersionVector(dict) = vv
  result.unwrap(dict.get(dict, replica_id), 0)
}

/// Compare two version vectors and return their causal ordering.
///
/// Returns `Equal` if all clocks match, `Before` if `a` is strictly dominated
/// by `b`, `After` if `a` strictly dominates `b`, or `Concurrent` if neither
/// dominates the other.
pub fn compare(a: VersionVector, b: VersionVector) -> Order {
  let VersionVector(dict_a) = a
  let VersionVector(dict_b) = b
  let a_keys = dict.keys(dict_a)
  let b_keys = dict.keys(dict_b)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  compare_helper(dict_a, dict_b, all_keys, False, False)
}

/// Merge two version vectors using pairwise maximum.
///
/// For each replica, the merged clock is the maximum of the two inputs.
/// This operation is commutative, associative, and idempotent.
pub fn merge(a: VersionVector, b: VersionVector) -> VersionVector {
  let VersionVector(dict_a) = a
  let VersionVector(dict_b) = b
  let a_keys = dict.keys(dict_a)
  let b_keys = dict.keys(dict_b)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  VersionVector(merge_helper(dict_a, dict_b, all_keys, dict.new()))
}

/// Encode a VersionVector as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`.
/// Format: `{"type": "version_vector", "v": 1, "state": {"clocks": {...}}}`
///
/// Use `from_json` to decode the result back into a `VersionVector`.
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

/// Decode a VersionVector from a JSON string produced by `to_json`.
///
/// Returns `Ok(VersionVector)` on success, or `Error(json.DecodeError)` if
/// the input is not a valid version-vector JSON envelope.
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

/// Extract the internal clock dictionary from a VersionVector.
///
/// Intended for use by serialization code in sibling modules (e.g.,
/// `mv_register`). Prefer the higher-level API (`get`, `compare`, `merge`)
/// for all other use cases.
pub fn to_dict(vv: VersionVector) -> dict.Dict(String, Int) {
  let VersionVector(d) = vv
  d
}

/// Construct a VersionVector from a raw clock dictionary.
///
/// Intended for use by deserialization code in sibling modules (e.g.,
/// `mv_register`). Prefer `new` and `increment` for all other use cases.
pub fn from_dict(d: dict.Dict(String, Int)) -> VersionVector {
  VersionVector(d)
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
