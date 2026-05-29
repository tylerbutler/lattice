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
//// import lattice_core/replica_id
//// import lattice_core/version_vector
////
//// let node_a = replica_id.new("node-a")
//// let node_b = replica_id.new("node-b")
//// let a = version_vector.new()
////   |> version_vector.increment(node_a)
////   |> version_vector.increment(node_a)
//// let b = version_vector.new()
////   |> version_vector.increment(node_b)
//// version_vector.compare(a, b)  // -> Concurrent
//// ```

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import lattice_core/replica_id.{type ReplicaId}

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
  VersionVector(dict: dict.Dict(ReplicaId, Int))
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
pub fn increment(vv: VersionVector, replica_id: ReplicaId) -> VersionVector {
  let VersionVector(dict) = vv
  let current = result.unwrap(dict.get(dict, replica_id), 0)
  VersionVector(dict.insert(dict, replica_id, current + 1))
}

/// Get the clock value for a specific replica.
///
/// Returns `0` if `replica_id` has not been seen (missing entries default
/// to zero, consistent with the version vector semantics).
pub fn get(vv: VersionVector, replica_id: ReplicaId) -> Int {
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
  let #(greater, less) =
    dict.fold(da, #(False, False), fn(acc, k, v_a) {
      let #(g, l) = acc
      let v_b = result.unwrap(dict.get(db, k), 0)
      #(g || v_a > v_b, l || v_a < v_b)
    })

  // Pass 2: Check keys in B that are NOT in A
  // If k is in B but not A, then v_b > 0 (implicitly v_a=0), so A < B => less=True
  let #(greater, less) =
    dict.fold(db, #(greater, less), fn(acc, k, _v_b) {
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

/// Check whether version vector `a` dominates `b`.
///
/// Returns `True` when every clock in `a` is greater than or equal to the
/// corresponding clock in `b`. Equivalently, `compare(a, b)` is `Equal` or
/// `After`.
pub fn dominates(a: VersionVector, b: VersionVector) -> Bool {
  case compare(a, b) {
    Equal | After -> True
    Before | Concurrent -> False
  }
}

/// Check whether a version vector is empty (has no clock entries).
pub fn is_empty(vv: VersionVector) -> Bool {
  let VersionVector(d) = vv
  dict.is_empty(d)
}

/// Set the clock for a replica to the maximum of the current value and `value`.
///
/// If the replica has no entry, `value` is used. This avoids round-tripping
/// through `to_dict`/`from_dict` when building a version vector incrementally.
pub fn set_max(
  vv vv: VersionVector,
  replica_id replica_id: ReplicaId,
  value value: Int,
) -> VersionVector {
  let VersionVector(d) = vv
  let current = result.unwrap(dict.get(d, replica_id), 0)
  case value > current {
    True -> VersionVector(dict.insert(d, replica_id, value))
    False -> vv
  }
}

/// Merge two version vectors using pairwise maximum.
///
/// For each replica, the merged clock is the maximum of the two inputs.
/// This operation is commutative, associative, and idempotent.
pub fn merge(a: VersionVector, b: VersionVector) -> VersionVector {
  let VersionVector(da) = a
  let VersionVector(db) = b

  let merged =
    dict.fold(db, da, fn(acc, k, v_b) {
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
        #("clocks", json.dict(d, fn(k) { replica_id.to_string(k) }, json.int)),
      ]),
    ),
  ])
}

/// Decode a VersionVector from a JSON string produced by `to_json`.
///
/// Returns `Ok(VersionVector)` on success, or `Error(json.DecodeError)` if
/// the input is not a valid version-vector JSON envelope.
pub fn from_json(
  json_string: String,
) -> Result(VersionVector, json.DecodeError) {
  let state_decoder = {
    use state <- decode.field("state", {
      use clocks <- decode.field(
        "clocks",
        decode.dict(replica_id.decoder(), decode.int),
      )
      decode.success(VersionVector(dict: clocks))
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
      case type_tag == "version_vector" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=version_vector and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

/// A JSON decoder for VersionVector values.
///
/// Decodes the self-describing envelope format produced by `to_json`.
/// Useful as a building block in `from_json` decoders when a VersionVector
/// is embedded inline within another JSON structure.
pub fn decoder() -> decode.Decoder(VersionVector) {
  use _type <- decode.field("type", decode.string)
  use _v <- decode.field("v", decode.int)
  use clocks <- decode.field("state", {
    use clocks <- decode.field(
      "clocks",
      decode.dict(replica_id.decoder(), decode.int),
    )
    decode.success(clocks)
  })
  decode.success(VersionVector(dict: clocks))
}

/// Extract the internal clock dictionary from a VersionVector.
///
/// Returns a `Dict(ReplicaId, Int)` mapping replica IDs to their clock values.
/// Useful for serialization or when you need direct access to the raw clock
/// data. Prefer the higher-level API (`get`, `compare`, `merge`) for most
/// use cases.
pub fn to_dict(vv: VersionVector) -> dict.Dict(ReplicaId, Int) {
  let VersionVector(d) = vv
  d
}

/// Construct a VersionVector from a raw clock dictionary.
///
/// Creates a version vector from a `Dict(ReplicaId, Int)` mapping replica IDs
/// to clock values. Useful for deserialization or constructing a version
/// vector from external data. Prefer `new` and `increment` for most use
/// cases.
pub fn from_dict(d: dict.Dict(ReplicaId, Int)) -> VersionVector {
  VersionVector(d)
}
