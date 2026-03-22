//// A grow-only counter (G-Counter) CRDT.
////
//// Each replica maintains its own monotonically increasing count. The global
//// value is the sum across all replicas. Merge takes the pairwise maximum
//// of each replica's count, guaranteeing convergence.
////
//// G-Counter is non-opaque because `pn_counter` directly accesses its internal
//// fields for serialization. Adding opaque accessor functions would not improve
//// the API for this paired type.
////
//// ## Example
////
//// ```gleam
//// import lattice/g_counter
////
//// let a = g_counter.new("node-a") |> g_counter.increment(3)
//// let b = g_counter.new("node-b") |> g_counter.increment(5)
//// let merged = g_counter.merge(a, b)
//// g_counter.value(merged)  // -> 8
//// ```

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result

/// A grow-only counter that tracks per-replica counts.
///
/// Each replica identified by a `String` ID maintains its own count.
/// The global value is the sum of all per-replica counts.
/// The type is opaque to enforce encapsulation; internal helpers are provided
/// for paired types like `pn_counter`.
pub opaque type GCounter {
  GCounter(dict: dict.Dict(String, Int), self_id: String)
}

/// Create a new G-Counter for the given replica.
///
/// Returns a fresh counter where all per-replica counts are zero.
/// The `replica_id` identifies this node and is used when incrementing.
pub fn new(replica_id: String) -> GCounter {
  GCounter(dict.new(), replica_id)
}

/// Internal: Expose state for `pn_counter` serialization.
@internal
pub fn to_state(counter: GCounter) -> #(dict.Dict(String, Int), String) {
  let GCounter(d, id) = counter
  #(d, id)
}

/// Internal: Reconstruct from state for `pn_counter` deserialization.
@internal
pub fn from_state(state: #(dict.Dict(String, Int), String)) -> GCounter {
  let #(d, id) = state
  GCounter(d, id)
}

/// Increment the counter by `delta`.
///
/// Adds `delta` to this replica's count. `delta` must be non-negative;
/// passing a negative value throws because it would violate the grow-only
/// invariant and may cause incorrect merge results.
pub fn increment(counter: GCounter, delta: Int) -> GCounter {
  require_non_negative_delta(delta)
  let GCounter(dict, self_id) = counter
  let current = result.unwrap(dict.get(dict, self_id), 0)
  GCounter(dict.insert(dict, self_id, current + delta), self_id)
}

/// Get the current value of the counter.
///
/// Returns the sum of all per-replica counts, which represents the total
/// number of increments applied across all replicas observed by this counter.
pub fn value(counter: GCounter) -> Int {
  let GCounter(dict, _) = counter
  dict.fold(dict, 0, fn(acc, _key, value) { acc + value })
}

/// Merge two G-Counters using pairwise maximum.
///
/// For each replica, the merged count is the maximum of the two inputs.
/// The result's `self_id` is taken from `a`.
///
/// This operation is commutative, associative, and idempotent, satisfying
/// the CRDT join-semilattice laws. Any ordering of concurrent merges will
/// produce the same final state.
pub fn merge(a: GCounter, b: GCounter) -> GCounter {
  let GCounter(dict_a, self_id_a) = a
  let GCounter(dict_b, _) = b

  let merged_dict = dict.combine(dict_a, dict_b, int.max)

  // Keep the self_id from the first counter
  GCounter(merged_dict, self_id_a)
}

/// Encode a G-Counter as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`.
/// Format: `{"type": "g_counter", "v": 1, "state": {"self_id": "...", "counts": {...}}}`
///
/// Use `from_json` to decode the result back into a `GCounter`.
pub fn to_json(counter: GCounter) -> json.Json {
  let GCounter(d, self_id) = counter
  json.object([
    #("type", json.string("g_counter")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("self_id", json.string(self_id)),
        #("counts", json.dict(d, fn(k) { k }, json.int)),
      ]),
    ),
  ])
}

/// Decode a G-Counter from a JSON string produced by `to_json`.
///
/// Returns `Ok(GCounter)` on success, or `Error(json.DecodeError)` if the
/// input is not a valid G-Counter JSON envelope.
pub fn from_json(json_string: String) -> Result(GCounter, json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", decode.string)
      use counts <- decode.field(
        "counts",
        decode.dict(decode.string, decode.int),
      )
      decode.success(GCounter(dict: counts, self_id: self_id))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}

fn require_non_negative_delta(delta: Int) -> Nil {
  case delta < 0 {
    True -> panic as "g_counter.increment delta must be non-negative"
    False -> Nil
  }
}
