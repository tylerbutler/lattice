//// A last-writer-wins register (LWW-Register) CRDT.
////
//// Stores a single value with an associated timestamp. When two replicas
//// conflict, the value with the strictly higher timestamp wins. On equal
//// timestamps, the replica with the lexicographically greater `replica_id`
//// wins, ensuring fully commutative merge.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_registers/lww_register
////
//// let a = lww_register.new("hello", 1, replica_id.new("node-a"))
//// let b = lww_register.new("world", 2, replica_id.new("node-b"))
//// let merged = lww_register.merge(a, b)
//// lww_register.value(merged)  // -> "world"
//// ```

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/order
import lattice_core/replica_id.{type ReplicaId}

/// A register holding a single value alongside its write timestamp and
/// replica identifier.
///
/// `value` is the stored payload, `timestamp` is an integer logical clock
/// used to resolve conflicts, and `replica_id` provides a deterministic
/// tie-breaker when timestamps are equal.
pub opaque type LWWRegister(a) {
  LWWRegister(value: a, timestamp: Int, replica_id: ReplicaId)
}

/// Create a new LWW-Register with an initial value, timestamp, and replica ID.
///
/// `timestamp` should be a positive integer representing the logical time of
/// the write. Use a monotonically increasing source (e.g., wall-clock
/// milliseconds or a Lamport clock) so that later writes have higher values.
/// `replica_id` identifies the writing node and is used as a deterministic
/// tie-breaker when two registers have equal timestamps during merge.
pub fn new(val: a, timestamp: Int, replica_id: ReplicaId) -> LWWRegister(a) {
  LWWRegister(value: val, timestamp: timestamp, replica_id: replica_id)
}

/// Update the register if `timestamp` is strictly greater than the current one.
///
/// If `timestamp > register.timestamp`, replaces the stored value and
/// timestamp with the new ones. Otherwise returns the register unchanged.
/// This ensures only strictly newer writes are accepted.
/// The `replica_id` is preserved from the original register.
pub fn set(register: LWWRegister(a), val: a, timestamp: Int) -> LWWRegister(a) {
  case timestamp > register.timestamp {
    True ->
      LWWRegister(
        value: val,
        timestamp: timestamp,
        replica_id: register.replica_id,
      )
    False -> register
  }
}

/// Return the current value of the register.
///
/// Provided for a uniform functional API since the type is opaque.
pub fn value(register: LWWRegister(a)) -> a {
  register.value
}

/// Merge two LWW-Registers by returning the one with the higher timestamp.
///
/// When `a.timestamp > b.timestamp`, returns `a`. When `b.timestamp >
/// a.timestamp`, returns `b`. On equal timestamps, the register whose
/// `replica_id` is lexicographically greater wins, providing a fully
/// commutative, associative, and idempotent merge.
pub fn merge(a: LWWRegister(a), b: LWWRegister(a)) -> LWWRegister(a) {
  case a.timestamp > b.timestamp {
    True -> a
    False ->
      case a.timestamp < b.timestamp {
        True -> b
        False -> {
          // Equal timestamps: use replica_id as deterministic tie-breaker
          case replica_id.compare(a.replica_id, b.replica_id) {
            order.Gt -> a
            order.Lt -> b
            order.Eq -> a
          }
        }
      }
  }
}

/// Encode a LWWRegister(String) as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version = 2), and `state`.
/// Format: `{"type": "lww_register", "v": 2, "state": {"value": "...", "timestamp": ..., "replica_id": "..."}}`
///
/// Use `from_json` to decode the result back into a `LWWRegister(String)`.
pub fn to_json(register: LWWRegister(String)) -> json.Json {
  json.object([
    #("type", json.string("lww_register")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("value", json.string(register.value)),
        #("timestamp", json.int(register.timestamp)),
        #("replica_id", json.string(replica_id.to_string(register.replica_id))),
      ]),
    ),
  ])
}

/// Decode a LWWRegister(String) from a JSON string produced by `to_json`.
///
/// Supports both v1 (no replica_id, defaults to "") and v2 (with replica_id)
/// envelopes. Returns `Ok(LWWRegister(String))` on success, or
/// `Error(json.DecodeError)` if the input is not a valid LWW-Register JSON
/// envelope.
pub fn from_json(
  json_string: String,
) -> Result(LWWRegister(String), json.DecodeError) {
  let v2_state_decoder = {
    use state <- decode.field("state", {
      use value <- decode.field("value", decode.string)
      use timestamp <- decode.field("timestamp", decode.int)
      use replica_id_str <- decode.optional_field(
        "replica_id",
        "",
        decode.string,
      )
      decode.success(LWWRegister(
        value: value,
        timestamp: timestamp,
        replica_id: replica_id.new(replica_id_str),
      ))
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
      case type_tag == "lww_register" && { version == 1 || version == 2 } {
        True -> json.parse(from: json_string, using: v2_state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=lww_register and v=1 or v=2",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}
