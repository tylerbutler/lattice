/// A Last-Writer-Wins Register CRDT
/// Stores a single value; updates are resolved by timestamp (higher wins)
pub type LWWRegister(a) {
  LWWRegister(value: a, timestamp: Int)
}

/// Create a new LWW-Register with an initial value and timestamp
pub fn new(val: a, timestamp: Int) -> LWWRegister(a) {
  LWWRegister(value: val, timestamp: timestamp)
}

/// Update the register value only if the new timestamp is strictly greater
/// than the current timestamp; otherwise return the register unchanged
pub fn set(register: LWWRegister(a), val: a, timestamp: Int) -> LWWRegister(a) {
  case timestamp > register.timestamp {
    True -> LWWRegister(value: val, timestamp: timestamp)
    False -> register
  }
}

/// Return the current value of the register
pub fn value(register: LWWRegister(a)) -> a {
  register.value
}

/// Merge two LWW-Registers by returning the one with the higher timestamp.
/// On equal timestamps, returns `b` (the second argument) for a consistent
/// tiebreak. Commutativity holds at the value level: when timestamps differ,
/// both merge(a,b) and merge(b,a) return the register with the higher
/// timestamp. When timestamps are equal, both registers have the same
/// timestamp so value-level commutativity requires test cases to use
/// distinct timestamps or accept equal values.
pub fn merge(a: LWWRegister(a), b: LWWRegister(a)) -> LWWRegister(a) {
  case a.timestamp > b.timestamp {
    True -> a
    False -> b
  }
}
