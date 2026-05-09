//// A positive-negative counter (PN-Counter) CRDT.
////
//// Supports both increment and decrement operations by pairing two G-Counters:
//// one tracking increments and one tracking decrements. The value is the
//// difference between the two totals. Merge delegates to G-Counter merge on
//// each half independently.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_counters/pn_counter
////
//// let counter = pn_counter.new(replica_id.new("node-a"))
////   |> pn_counter.increment(10)
////   |> pn_counter.decrement(3)
//// pn_counter.value(counter)  // -> 7
//// ```

import gleam/dynamic/decode
import gleam/int
import gleam/json
import lattice_core/replica_id.{type ReplicaId}
import lattice_counters/g_counter

/// A counter that supports both increment and decrement operations.
///
/// Internally pairs two G-Counters (`positive` and `negative`). The visible
/// value is `g_counter.value(positive) - g_counter.value(negative)`.
pub opaque type PNCounter {
  PNCounter(positive: g_counter.GCounter, negative: g_counter.GCounter)
}

pub type UpdateError {
  NegativeDelta(Int)
}

/// Create a new PN-Counter for the given replica.
///
/// Returns a fresh counter with a zero value. Both inner G-Counters are
/// initialized with `replica_id` as their node identifier.
pub fn new(replica_id: ReplicaId) -> PNCounter {
  PNCounter(
    positive: g_counter.new(replica_id),
    negative: g_counter.new(replica_id),
  )
}

/// Increment the counter by `delta`.
///
/// Adds `delta` to the positive G-Counter. `delta` should be a non-negative
/// integer; the positive G-Counter is grow-only so passing a negative value
/// violates the invariant.
///
/// See `increment_with_delta` for the delta-state variant that also returns
/// a small payload suitable for incremental sync (e.g. over websockets).
pub fn increment(counter: PNCounter, delta: Int) -> PNCounter {
  let assert Ok(updated) = try_increment(counter, delta)
  updated
}

/// Safely increment the counter by `delta`.
///
/// Returns `Error(NegativeDelta(delta))` if `delta` is negative.
///
/// See `try_increment_with_delta` for the delta-state variant.
pub fn try_increment(
  counter: PNCounter,
  delta: Int,
) -> Result(PNCounter, UpdateError) {
  case try_increment_with_delta(counter, delta) {
    Ok(#(updated, _)) -> Ok(updated)
    Error(e) -> Error(e)
  }
}

/// Increment the counter by `delta` and return both the new state and a delta.
///
/// The returned delta is a `PNCounter` whose positive G-Counter contains
/// only this replica's new positive count and whose negative G-Counter is
/// empty. Merging the delta into a remote replica via `merge` produces the
/// same observable result as merging the full new state.
pub fn increment_with_delta(
  counter: PNCounter,
  delta: Int,
) -> #(PNCounter, PNCounter) {
  let assert Ok(result) = try_increment_with_delta(counter, delta)
  result
}

/// Safely increment the counter by `delta`, returning the new state and a delta.
///
/// Returns `Error(NegativeDelta(delta))` if `delta` is negative.
pub fn try_increment_with_delta(
  counter: PNCounter,
  delta: Int,
) -> Result(#(PNCounter, PNCounter), UpdateError) {
  let PNCounter(positive, negative) = counter
  case g_counter.try_increment_with_delta(positive, delta) {
    Ok(#(updated_positive, positive_delta)) -> {
      let updated = PNCounter(positive: updated_positive, negative: negative)
      let delta_state =
        PNCounter(
          positive: positive_delta,
          negative: g_counter.new(self_id_of(negative)),
        )
      Ok(#(updated, delta_state))
    }
    Error(g_counter.NegativeDelta(d)) -> Error(NegativeDelta(d))
  }
}

/// Decrement the counter by `delta`.
///
/// Adds `delta` to the negative G-Counter (which reduces the visible value).
/// `delta` should be a non-negative integer; the negative G-Counter is
/// grow-only so passing a negative value violates the invariant.
///
/// See `decrement_with_delta` for the delta-state variant.
pub fn decrement(counter: PNCounter, delta: Int) -> PNCounter {
  let assert Ok(updated) = try_decrement(counter, delta)
  updated
}

/// Safely decrement the counter by `delta`.
///
/// Returns `Error(NegativeDelta(delta))` if `delta` is negative.
///
/// See `try_decrement_with_delta` for the delta-state variant.
pub fn try_decrement(
  counter: PNCounter,
  delta: Int,
) -> Result(PNCounter, UpdateError) {
  case try_decrement_with_delta(counter, delta) {
    Ok(#(updated, _)) -> Ok(updated)
    Error(e) -> Error(e)
  }
}

/// Decrement the counter by `delta` and return both the new state and a delta.
///
/// The returned delta is a `PNCounter` whose negative G-Counter contains
/// only this replica's new negative count and whose positive G-Counter is
/// empty. Merging the delta into a remote replica via `merge` produces the
/// same observable result as merging the full new state.
pub fn decrement_with_delta(
  counter: PNCounter,
  delta: Int,
) -> #(PNCounter, PNCounter) {
  let assert Ok(result) = try_decrement_with_delta(counter, delta)
  result
}

/// Safely decrement the counter by `delta`, returning the new state and a delta.
///
/// Returns `Error(NegativeDelta(delta))` if `delta` is negative.
pub fn try_decrement_with_delta(
  counter: PNCounter,
  delta: Int,
) -> Result(#(PNCounter, PNCounter), UpdateError) {
  let PNCounter(positive, negative) = counter
  case g_counter.try_increment_with_delta(negative, delta) {
    Ok(#(updated_negative, negative_delta)) -> {
      let updated = PNCounter(positive: positive, negative: updated_negative)
      let delta_state =
        PNCounter(
          positive: g_counter.new(self_id_of(positive)),
          negative: negative_delta,
        )
      Ok(#(updated, delta_state))
    }
    Error(g_counter.NegativeDelta(d)) -> Error(NegativeDelta(d))
  }
}

fn self_id_of(c: g_counter.GCounter) -> ReplicaId {
  let #(_, self_id) = g_counter.to_parts(c)
  self_id
}

/// Get the current value of the counter.
///
/// Returns the sum of positive increments minus the sum of negative
/// decrements observed across all replicas.
pub fn value(counter: PNCounter) -> Int {
  let PNCounter(positive, negative) = counter
  g_counter.value(positive) - g_counter.value(negative)
}

/// Merge two PN-Counters.
///
/// Merges the positive G-Counters and negative G-Counters independently using
/// pairwise maximum. The result's `self_id` is taken from `a`'s positive
/// G-Counter.
///
/// This operation is commutative, associative, and idempotent.
pub fn merge(a: PNCounter, b: PNCounter) -> PNCounter {
  let PNCounter(positive_a, negative_a) = a
  let PNCounter(positive_b, negative_b) = b

  PNCounter(
    positive: g_counter.merge(positive_a, positive_b),
    negative: g_counter.merge(negative_a, negative_b),
  )
}

/// Encode a PN-Counter as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`.
/// Format: `{"type": "pn_counter", "v": 1, "state": {"positive": {...}, "negative": {...}}}`
///
/// Use `from_json` to decode the result back into a `PNCounter`.
pub fn to_json(counter: PNCounter) -> json.Json {
  let PNCounter(positive, negative) = counter
  let #(pos_dict, pos_id) = g_counter.to_parts(positive)
  let #(neg_dict, neg_id) = g_counter.to_parts(negative)
  json.object([
    #("type", json.string("pn_counter")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #(
          "positive",
          json.object([
            #("self_id", replica_id.to_json(pos_id)),
            #(
              "counts",
              json.dict(pos_dict, fn(k) { replica_id.to_string(k) }, json.int),
            ),
          ]),
        ),
        #(
          "negative",
          json.object([
            #("self_id", replica_id.to_json(neg_id)),
            #(
              "counts",
              json.dict(neg_dict, fn(k) { replica_id.to_string(k) }, json.int),
            ),
          ]),
        ),
      ]),
    ),
  ])
}

/// Decode a PN-Counter from a JSON string produced by `to_json`.
///
/// Returns `Ok(PNCounter)` on success, or `Error(json.DecodeError)` if the
/// input is not a valid PN-Counter JSON envelope.
pub fn from_json(json_string: String) -> Result(PNCounter, json.DecodeError) {
  let g_counter_state_decoder = {
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
    decode.success(g_counter.from_parts(counts, self_id))
  }
  let state_decoder = {
    use state <- decode.field("state", {
      use positive <- decode.field("positive", g_counter_state_decoder)
      use negative <- decode.field("negative", g_counter_state_decoder)
      decode.success(PNCounter(positive: positive, negative: negative))
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
      case type_tag == "pn_counter" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=pn_counter and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}
