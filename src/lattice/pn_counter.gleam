import gleam/dynamic/decode
import gleam/json
import lattice/g_counter

/// A PN-Counter is a counter that supports both increments and decrements
/// It is built on top of two G-Counters: one for positive values, one for negative
pub type PNCounter {
  PNCounter(positive: g_counter.GCounter, negative: g_counter.GCounter)
}

/// Create a new PN-Counter for the given replica
pub fn new(replica_id: String) -> PNCounter {
  PNCounter(
    positive: g_counter.new(replica_id),
    negative: g_counter.new(replica_id),
  )
}

/// Increment the counter by the given delta (must be non-negative)
/// This adds to the positive G-Counter
pub fn increment(counter: PNCounter, delta: Int) -> PNCounter {
  let PNCounter(positive, negative) = counter
  PNCounter(positive: g_counter.increment(positive, delta), negative: negative)
}

/// Decrement the counter by the given delta (must be non-negative)
/// This adds to the negative G-Counter (the value is decremented)
pub fn decrement(counter: PNCounter, delta: Int) -> PNCounter {
  let PNCounter(positive, negative) = counter
  PNCounter(positive: positive, negative: g_counter.increment(negative, delta))
}

/// Get the value of the counter (positive sum - negative sum)
pub fn value(counter: PNCounter) -> Int {
  let PNCounter(positive, negative) = counter
  g_counter.value(positive) - g_counter.value(negative)
}

/// Encode a PN-Counter as a self-describing JSON value.
/// Format: {"type": "pn_counter", "v": 1, "state": {"positive": {...}, "negative": {...}}}
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

/// Decode a PN-Counter from a JSON string produced by to_json.
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

/// Merge two PN-Counters by merging their positive and negative G-Counters separately
pub fn merge(a: PNCounter, b: PNCounter) -> PNCounter {
  let PNCounter(positive_a, negative_a) = a
  let PNCounter(positive_b, negative_b) = b

  PNCounter(
    positive: g_counter.merge(positive_a, positive_b),
    negative: g_counter.merge(negative_a, negative_b),
  )
}
