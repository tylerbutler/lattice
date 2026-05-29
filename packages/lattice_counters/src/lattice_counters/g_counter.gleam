//// A grow-only counter (G-Counter) CRDT.
////
//// Each replica maintains its own monotonically increasing count. The global
//// value is the sum across all replicas. Merge takes the pairwise maximum
//// of each replica's count, guaranteeing convergence.
////
//// G-Counter is opaque: use the provided functions to interact with it.
//// `pn_counter` in the same package can access internal fields directly.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_counters/g_counter
////
//// let a = g_counter.new(replica_id.new("node-a")) |> g_counter.increment(3)
//// let b = g_counter.new(replica_id.new("node-b")) |> g_counter.increment(5)
//// let merged = g_counter.merge(a, b)
//// g_counter.value(merged)  // -> 8
//// ```

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import lattice_core/replica_id.{type ReplicaId}

/// A grow-only counter that tracks per-replica counts.
///
/// Each replica identified by a `ReplicaId` maintains its own count.
/// The global value is the sum of all per-replica counts.
pub opaque type GCounter {
  GCounter(dict: dict.Dict(ReplicaId, Int), self_id: ReplicaId)
}

pub type IncrementError {
  NegativeDelta(Int)
}

/// Create a new G-Counter for the given replica.
///
/// Returns a fresh counter where all per-replica counts are zero.
/// The `replica_id` identifies this node and is used when incrementing.
pub fn new(replica_id: ReplicaId) -> GCounter {
  GCounter(dict.new(), replica_id)
}

/// Increment the counter by `delta`.
///
/// Adds `delta` to this replica's count. `delta` should be a non-negative
/// integer; passing a negative value will decrease the local count, which
/// violates the grow-only invariant and may cause incorrect merge results.
///
/// See `increment_with_delta` for the delta-state variant that also returns
/// a small payload suitable for incremental sync (e.g. over websockets).
pub fn increment(counter: GCounter, delta: Int) -> GCounter {
  // Ergonomic wrapper documented to panic on a negative delta; callers
  // needing error handling use `try_increment`.
  // nolint: assert_ok_pattern
  let assert Ok(updated) = try_increment(counter, delta)
  updated
}

/// Safely increment the counter by `delta`.
///
/// Returns `Error(NegativeDelta(delta))` if `delta` is negative.
///
/// See `try_increment_with_delta` for the delta-state variant.
pub fn try_increment(
  counter: GCounter,
  delta: Int,
) -> Result(GCounter, IncrementError) {
  case try_increment_with_delta(counter, delta) {
    Ok(#(updated, _)) -> Ok(updated)
    Error(e) -> Error(e)
  }
}

/// Increment the counter by `delta` and return both the new state and a delta.
///
/// The returned delta is itself a `GCounter` containing only this replica's
/// new count. Merging the delta into a remote replica via `merge` produces
/// the same result as merging the full new state — but the delta is a
/// minimal payload suitable for incremental sync (e.g., over websockets).
///
/// See `try_increment_with_delta` for an error-safe variant. `delta` should
/// be non-negative; a negative value will panic.
pub fn increment_with_delta(
  counter: GCounter,
  delta: Int,
) -> #(GCounter, GCounter) {
  // Ergonomic wrapper documented to panic on a negative delta; callers
  // needing error handling use `try_increment_with_delta`.
  // nolint: assert_ok_pattern
  let assert Ok(result) = try_increment_with_delta(counter, delta)
  result
}

/// Safely increment the counter by `delta`, returning the new state and a delta.
///
/// Returns `Error(NegativeDelta(delta))` if `delta` is negative. On success,
/// returns `Ok(#(new_state, delta))` where `delta` is a `GCounter` containing
/// only the changed self-replica entry.
pub fn try_increment_with_delta(
  counter: GCounter,
  delta: Int,
) -> Result(#(GCounter, GCounter), IncrementError) {
  case delta < 0 {
    True -> Error(NegativeDelta(delta))
    False -> {
      let GCounter(dict, self_id) = counter
      let current = result.unwrap(dict.get(dict, self_id), 0)
      let new_count = current + delta
      let updated = GCounter(dict.insert(dict, self_id, new_count), self_id)
      let delta_state =
        GCounter(dict.from_list([#(self_id, new_count)]), self_id)
      Ok(#(updated, delta_state))
    }
  }
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

  let a_keys = dict.keys(dict_a)
  let b_keys = dict.keys(dict_b)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  let merged_dict = merge_helper(dict_a, dict_b, all_keys, dict.new())

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
        #("self_id", replica_id.to_json(self_id)),
        #("counts", json.dict(d, fn(k) { replica_id.to_string(k) }, json.int)),
      ]),
    ),
  ])
}

/// Decode a G-Counter from a JSON string produced by `to_json`.
///
/// Returns `Ok(GCounter)` on success, or `Error(json.DecodeError)` if the
/// input is not a valid G-Counter JSON envelope.
pub fn from_json(json_string: String) -> Result(GCounter, json.DecodeError) {
  let state_decoder = {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", replica_id.decoder())
      let non_negative_int =
        decode.int
        |> decode.then(fn(val) {
          case val >= 0 {
            True -> decode.success(val)
            False -> decode.failure(val, "a non-negative integer")
          }
        })
      use counts <- decode.field(
        "counts",
        decode.dict(replica_id.decoder(), non_negative_int),
      )
      decode.success(GCounter(dict: counts, self_id: self_id))
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
      case type_tag == "g_counter" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=g_counter and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

fn merge_helper(
  a: dict.Dict(ReplicaId, Int),
  b: dict.Dict(ReplicaId, Int),
  keys: List(ReplicaId),
  acc: dict.Dict(ReplicaId, Int),
) -> dict.Dict(ReplicaId, Int) {
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

/// Extract the internal counts dictionary and self_id from a GCounter.
@internal
pub fn to_parts(counter: GCounter) -> #(dict.Dict(ReplicaId, Int), ReplicaId) {
  let GCounter(dict, self_id) = counter
  #(dict, self_id)
}

/// Construct a GCounter from a raw counts dictionary and self_id.
@internal
pub fn from_parts(
  dict: dict.Dict(ReplicaId, Int),
  self_id: ReplicaId,
) -> GCounter {
  GCounter(dict, self_id)
}
