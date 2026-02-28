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

/// Merge two PN-Counters by merging their positive and negative G-Counters separately
pub fn merge(a: PNCounter, b: PNCounter) -> PNCounter {
  let PNCounter(positive_a, negative_a) = a
  let PNCounter(positive_b, negative_b) = b

  PNCounter(
    positive: g_counter.merge(positive_a, positive_b),
    negative: g_counter.merge(negative_a, negative_b),
  )
}
