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

import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/order

// Aliased so the `replica_id` accessor below can take the obvious name.
import lattice_core/replica_id.{type ReplicaId} as replica

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
pub fn new(
  value value: a,
  timestamp timestamp: Int,
  replica_id replica_id: ReplicaId,
) -> LWWRegister(a) {
  LWWRegister(value: value, timestamp: timestamp, replica_id: replica_id)
}

/// Update the register if `timestamp` is strictly greater than the current one.
///
/// If `timestamp > register.timestamp`, replaces the stored value and
/// timestamp with the new ones. Otherwise returns the register unchanged.
/// This ensures only strictly newer writes are accepted.
/// The `replica_id` is preserved from the original register. Use `set_as`
/// to author a new write after adopting another replica's winning value.
///
/// Note that the comparison is *strict*, so a wall clock is not a safe source
/// on its own: it stalls for a millisecond at a time, and a second write
/// inside the same tick is silently dropped even when it came from this same
/// replica. Callers that write faster than their clock ticks should stamp
/// `int.max(wall_clock, timestamp(register) + 1)`, which keeps every local
/// write ordered while leaving `merge` commutative.
///
/// See `set_with_delta` for the delta-state variant that also returns a
/// small payload suitable for incremental sync (e.g. over websockets).
pub fn set(
  register register: LWWRegister(a),
  value value: a,
  timestamp timestamp: Int,
) -> LWWRegister(a) {
  let #(updated, _) = set_with_delta(register:, value:, timestamp:)
  updated
}

/// Set a value and return both the new state and a delta.
///
/// The returned delta is an `LWWRegister` carrying the write that was
/// actually accepted locally. When `timestamp` strictly exceeds the current
/// timestamp the delta carries the new (value, timestamp, replica_id);
/// otherwise the local set is a no-op and the delta carries the unchanged
/// register so that no rejected write can win on a remote replica.
///
/// Merging the delta into a remote via `merge` produces the same result as
/// merging the new local state, preserving convergence.
pub fn set_with_delta(
  register register: LWWRegister(a),
  value value: a,
  timestamp timestamp: Int,
) -> #(LWWRegister(a), LWWRegister(a)) {
  set_as_with_delta(
    register:,
    value:,
    timestamp:,
    replica_id: register.replica_id,
  )
}

/// Write a strictly newer value as the given replica.
///
/// Unlike `set`, an accepted write records the supplied author. A rejected
/// write leaves the value, timestamp, and historical author unchanged.
/// Equal timestamps are rejected even if the new author sorts higher.
///
/// ## Examples
///
/// ```gleam
/// let old = lww_register.new("old", 1, replica_id.new("A"))
/// let updated = lww_register.set_as(old, "new", 2, replica_id.new("B"))
/// lww_register.replica_id(updated)  // -> replica_id.new("B")
/// ```
pub fn set_as(
  register register: LWWRegister(a),
  value value: a,
  timestamp timestamp: Int,
  replica_id replica_id: ReplicaId,
) -> LWWRegister(a) {
  let #(updated, _) =
    set_as_with_delta(register:, value:, timestamp:, replica_id:)
  updated
}

/// Write as the given replica and return the accepted state and delta.
///
/// Both results carry the accepted write. For a rejected timestamp, both
/// retain the unchanged register, including its historical author.
///
/// ## Examples
///
/// ```gleam
/// let old = lww_register.new("old", 1, replica_id.new("A"))
/// let #(updated, delta) =
///   lww_register.set_as_with_delta(old, "new", 2, replica_id.new("B"))
/// lww_register.merge(old, delta) == updated  // -> True
/// ```
pub fn set_as_with_delta(
  register register: LWWRegister(a),
  value value: a,
  timestamp timestamp: Int,
  replica_id replica_id: ReplicaId,
) -> #(LWWRegister(a), LWWRegister(a)) {
  use <- bool.guard(timestamp <= register.timestamp, #(register, register))
  let updated =
    LWWRegister(value: value, timestamp: timestamp, replica_id: replica_id)
  #(updated, updated)
}

/// Return the current value of the register.
///
/// Provided for a uniform functional API since the type is opaque.
pub fn value(register: LWWRegister(a)) -> a {
  register.value
}

/// Return the timestamp of the write the register currently holds.
///
/// Because `set` accepts only strictly greater timestamps, a caller stamping
/// writes from a wall clock needs to know the timestamp already held in order
/// to stay ahead of it — two writes inside the same clock tick are otherwise
/// unordered and the second is dropped. Reading this back from a decoded
/// snapshot lets such a caller seed its logical clock before its first write.
///
/// ## Examples
///
/// ```gleam
/// let register = lww_register.new("hello", 42, replica_id.new("node-a"))
/// lww_register.timestamp(register)  // -> 42
///
/// // Stamp the next write so it cannot collide with the one held.
/// let next = int.max(wall_clock_ms(), lww_register.timestamp(register) + 1)
/// ```
pub fn timestamp(register: LWWRegister(a)) -> Int {
  register.timestamp
}

/// Return the replica that owns the value the register currently holds.
///
/// `set` preserves the held author; `set_as` records its supplied author only
/// for an accepted write. After `merge` this is the replica whose write won,
/// which makes it useful for provenance and for tie-breaking consistently
/// with `merge` in downstream code.
pub fn replica_id(register: LWWRegister(a)) -> ReplicaId {
  register.replica_id
}

/// Merge two LWW-Registers by returning the one with the higher timestamp.
///
/// When `a.timestamp > b.timestamp`, returns `a`. When `b.timestamp >
/// a.timestamp`, returns `b`. On equal timestamps, the register whose
/// `replica_id` is lexicographically greater wins, providing a fully
/// commutative, associative, and idempotent merge.
pub fn merge(a: LWWRegister(a), b: LWWRegister(a)) -> LWWRegister(a) {
  use <- bool.guard(a.timestamp > b.timestamp, a)
  use <- bool.guard(a.timestamp < b.timestamp, b)
  // Equal timestamps: use replica_id as deterministic tie-breaker
  case replica.compare(a.replica_id, b.replica_id) {
    order.Gt -> a
    order.Lt -> b
    order.Eq -> a
  }
}

/// Encode a LWWRegister(String) as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version = 2), and `state`.
/// Format: `{"type": "lww_register", "v": 2, "state": {"value": "...", "timestamp": ..., "replica_id": "..."}}`
///
/// Use `from_json` to decode the result back into a `LWWRegister(String)`.
pub fn to_json(register: LWWRegister(String)) -> json.Json {
  to_json_with(register, json.string)
}

/// Encode a register with a custom payload encoder, preserving write metadata.
///
/// Uses the same v2 envelope as `to_json`.
///
/// ## Examples
///
/// ```gleam
/// let register = lww_register.new(42, 1, replica_id.new("A"))
/// lww_register.to_json_with(register, json.int)
/// ```
pub fn to_json_with(
  register: LWWRegister(a),
  encode: fn(a) -> json.Json,
) -> json.Json {
  json.object([
    #("type", json.string("lww_register")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("value", encode(register.value)),
        #("timestamp", json.int(register.timestamp)),
        #("replica_id", json.string(replica.to_string(register.replica_id))),
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
  from_json_with(json_string, decode.string)
}

/// Decode a register with a custom payload decoder.
///
/// Accepts v1 and v2 envelopes, with the same metadata rules as `from_json`.
/// Invalid payloads or envelopes return `Error`.
///
/// ## Examples
///
/// ```gleam
/// let register = lww_register.new(42, 1, replica_id.new("A"))
/// let encoded = lww_register.to_json_with(register, json.int) |> json.to_string
/// lww_register.from_json_with(encoded, decode.int)  // -> Ok(register)
/// ```
pub fn from_json_with(
  json_string: String,
  decoder: decode.Decoder(a),
) -> Result(LWWRegister(a), json.DecodeError) {
  let v2_state_decoder = {
    use state <- decode.field("state", {
      use value <- decode.field("value", decoder)
      use timestamp <- decode.field("timestamp", decode.int)
      use replica_id_str <- decode.optional_field(
        "replica_id",
        "",
        decode.string,
      )
      decode.success(LWWRegister(
        value: value,
        timestamp: timestamp,
        replica_id: replica.new(replica_id_str),
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
