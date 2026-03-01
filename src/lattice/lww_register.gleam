//// A last-writer-wins register (LWW-Register) CRDT.
////
//// Stores a single value with an associated timestamp. When two replicas
//// conflict, the value with the strictly higher timestamp wins. On equal
//// timestamps, the second argument to `merge` wins (consistent tiebreak).
////
//// ## Example
////
//// ```gleam
//// import lattice/lww_register
////
//// let a = lww_register.new("hello", 1)
//// let b = lww_register.new("world", 2)
//// let merged = lww_register.merge(a, b)
//// lww_register.value(merged)  // -> "world"
//// ```

import gleam/dynamic/decode
import gleam/json

/// A register holding a single value alongside its write timestamp.
///
/// `value` is the stored payload and `timestamp` is an integer logical clock
/// used to resolve conflicts. The type is non-opaque: `value` and `timestamp`
/// are part of the public API and can be read directly in application code.
pub type LWWRegister(a) {
  LWWRegister(value: a, timestamp: Int)
}

/// Create a new LWW-Register with an initial value and timestamp.
///
/// `timestamp` should be a positive integer representing the logical time of
/// the write. Use a monotonically increasing source (e.g., wall-clock
/// milliseconds or a Lamport clock) so that later writes have higher values.
pub fn new(val: a, timestamp: Int) -> LWWRegister(a) {
  LWWRegister(value: val, timestamp: timestamp)
}

/// Update the register if `timestamp` is strictly greater than the current one.
///
/// If `timestamp > register.timestamp`, replaces the stored value and
/// timestamp with the new ones. Otherwise returns the register unchanged.
/// This ensures only strictly newer writes are accepted.
pub fn set(register: LWWRegister(a), val: a, timestamp: Int) -> LWWRegister(a) {
  case timestamp > register.timestamp {
    True -> LWWRegister(value: val, timestamp: timestamp)
    False -> register
  }
}

/// Return the current value of the register.
///
/// Equivalent to `register.value`; provided for a uniform functional API.
pub fn value(register: LWWRegister(a)) -> a {
  register.value
}

/// Merge two LWW-Registers by returning the one with the higher timestamp.
///
/// When `a.timestamp > b.timestamp`, returns `a`. Otherwise returns `b`.
/// On equal timestamps, `b` is returned as a consistent tiebreak.
///
/// Commutativity holds when timestamps differ: both `merge(a, b)` and
/// `merge(b, a)` return the register with the higher timestamp.
/// When timestamps are equal both calls return their respective `b` argument,
/// so callers should use distinct timestamps or ensure both replicas hold
/// the same value when timestamps match.
pub fn merge(a: LWWRegister(a), b: LWWRegister(a)) -> LWWRegister(a) {
  case a.timestamp > b.timestamp {
    True -> a
    False -> b
  }
}

/// Encode a LWWRegister(String) as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`.
/// Format: `{"type": "lww_register", "v": 1, "state": {"value": "...", "timestamp": ...}}`
///
/// Use `from_json` to decode the result back into a `LWWRegister(String)`.
pub fn to_json(register: LWWRegister(String)) -> json.Json {
  json.object([
    #("type", json.string("lww_register")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("value", json.string(register.value)),
        #("timestamp", json.int(register.timestamp)),
      ]),
    ),
  ])
}

/// Decode a LWWRegister(String) from a JSON string produced by `to_json`.
///
/// Returns `Ok(LWWRegister(String))` on success, or `Error(json.DecodeError)`
/// if the input is not a valid LWW-Register JSON envelope.
pub fn from_json(
  json_string: String,
) -> Result(LWWRegister(String), json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use value <- decode.field("value", decode.string)
      use timestamp <- decode.field("timestamp", decode.int)
      decode.success(LWWRegister(value: value, timestamp: timestamp))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
