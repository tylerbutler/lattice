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
//// import lattice/pn_counter
////
//// let counter = pn_counter.new("node-a")
////   |> pn_counter.increment(10)
////   |> pn_counter.decrement(3)
//// pn_counter.value(counter)  // -> 7
//// ```

import gleam/dynamic/decode
import gleam/json
import lattice/g_counter

/// A counter that supports both increment and decrement operations.
///
/// Internally pairs two G-Counters (`positive` and `negative`). The visible
/// value is `g_counter.value(positive) - g_counter.value(negative)`.
/// The type is non-opaque so that serialization can access the inner
/// G-Counter fields; do not rely on internal field names in application code.
pub type PNCounter {
  PNCounter(positive: g_counter.GCounter, negative: g_counter.GCounter)
}

/// Create a new PN-Counter for the given replica.
///
/// Returns a fresh counter with a zero value. Both inner G-Counters are
/// initialized with `replica_id` as their node identifier.
pub fn new(replica_id: String) -> PNCounter {
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
pub fn increment(counter: PNCounter, delta: Int) -> PNCounter {
  let PNCounter(positive, negative) = counter
  PNCounter(positive: g_counter.increment(positive, delta), negative: negative)
}

/// Decrement the counter by `delta`.
///
/// Adds `delta` to the negative G-Counter (which reduces the visible value).
/// `delta` should be a non-negative integer; the negative G-Counter is
/// grow-only so passing a negative value violates the invariant.
pub fn decrement(counter: PNCounter, delta: Int) -> PNCounter {
  let PNCounter(positive, negative) = counter
  PNCounter(positive: positive, negative: g_counter.increment(negative, delta))
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
  let g_counter.GCounter(pos_dict, pos_id) = positive
  let g_counter.GCounter(neg_dict, neg_id) = negative
  json.object([
    #("type", json.string("pn_counter")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #(
          "positive",
          json.object([
            #("self_id", json.string(pos_id)),
            #("counts", json.dict(pos_dict, fn(k) { k }, json.int)),
          ]),
        ),
        #(
          "negative",
          json.object([
            #("self_id", json.string(neg_id)),
            #("counts", json.dict(neg_dict, fn(k) { k }, json.int)),
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
    use self_id <- decode.field("self_id", decode.string)
    use counts <- decode.field("counts", decode.dict(decode.string, decode.int))
    decode.success(g_counter.GCounter(dict: counts, self_id: self_id))
  }
  let decoder = {
    use state <- decode.field("state", {
      use positive <- decode.field("positive", g_counter_state_decoder)
      use negative <- decode.field("negative", g_counter_state_decoder)
      decode.success(PNCounter(positive: positive, negative: negative))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
