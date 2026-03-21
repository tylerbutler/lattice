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
import gleam/int
import gleam/json
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
  let VersionVector(da) = a
  let VersionVector(db) = b
  
  // Pass 1: Check keys in A against B
  let #(greater, less) = dict.fold(da, #(False, False), fn(acc, k, v_a) {
    let #(g, l) = acc
    let v_b = result.unwrap(dict.get(db, k), 0)
    #(g || v_a > v_b, l || v_a < v_b)
  })

  // Pass 2: Check keys in B that are NOT in A
  // If k is in B but not A, then v_b > 0 (implicitly v_a=0), so A < B => less=True
  let #(greater, less) = dict.fold(db, #(greater, less), fn(acc, k, _v_b) {
    let #(g, _) = acc
    case dict.has_key(da, k) {
      True -> acc
      False -> #(g, True)
    }
  })

  case greater, less {
    False, False -> Equal
    True, False -> After
    False, True -> Before
    True, True -> Concurrent
  }
}

/// Merge two version vectors using pairwise maximum.
///
/// For each replica, the merged clock is the maximum of the two inputs.
/// This operation is commutative, associative, and idempotent.
pub fn merge(a: VersionVector, b: VersionVector) -> VersionVector {
  let VersionVector(da) = a
  let VersionVector(db) = b
  
  let merged = dict.fold(db, da, fn(acc, k, v_b) {
    case dict.get(acc, k) {
      Ok(v_a) -> dict.insert(acc, k, int.max(v_a, v_b))
      Error(Nil) -> dict.insert(acc, k, v_b)
    }
  })
  
  VersionVector(merged)
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
