//// A last-writer-wins register (LWW-Register) CRDT.
////
//// Stores a single value with an associated timestamp. When two replicas
//// conflict, the value with the strictly higher timestamp wins. On equal
//// timestamps, the replica with the lexicographically greater `replica_id`
//// wins for modern writes. Modern writes outrank imported legacy writes;
//// legacy ties use the original deterministic key in UTF-8 byte order,
//// followed by replica ID when keys are equal.
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

import gleam/bit_array
import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/order
import gleam/result

// Aliased so the `replica_id` accessor below can take the obvious name.
import lattice_core/replica_id.{type ReplicaId} as replica

/// A register holding a single value alongside its write timestamp and
/// replica identifier.
///
/// `value` is the stored payload, `timestamp` is an integer logical clock
/// used to resolve conflicts, and `replica_id` provides a deterministic
/// tie-breaker between modern writes when timestamps are equal. Legacy imports
/// also retain their deterministic payload key.
pub opaque type LWWRegister(a) {
  LWWRegister(
    value: a,
    timestamp: Int,
    replica_id: ReplicaId,
    provenance: Provenance,
  )
}

type Provenance {
  Modern
  Legacy(tie_key: String)
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
  LWWRegister(value:, timestamp:, replica_id:, provenance: Modern)
}

/// Write a value as `replica_id` if `timestamp` is strictly greater.
///
/// If `timestamp > register.timestamp`, replaces the stored value and
/// write metadata. Otherwise returns the register unchanged. Supplying the
/// writer explicitly prevents a local write after `merge` from inheriting the
/// winning remote writer's identity.
///
/// Note that the comparison is *strict*, so a wall clock is not a safe source
/// on its own: it stalls for a millisecond at a time, and a second write
/// inside the same tick is silently dropped even when it came from this same
/// replica. Callers that write faster than their clock ticks should stamp
/// `int.max(wall_clock, timestamp(register) + 1)`, which keeps every local
/// write ordered while leaving `merge` commutative.
///
/// A writer must not reuse the same `(timestamp, replica_id)` for different
/// values. After a restart, use a fresh replica ID or restore a durable logical
/// clock that advances beyond every prior write from that ID.
///
/// See `set_with_delta` for the delta-state variant that also returns a
/// small payload suitable for incremental sync (e.g. over websockets).
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("B")
/// let adopted = lww_register.new("old", 1, replica_id.new("A"))
/// let updated = lww_register.set(adopted, "new", 2, local)
/// lww_register.replica_id(updated)  // -> local
/// ```
pub fn set(
  register register: LWWRegister(a),
  value value: a,
  timestamp timestamp: Int,
  replica_id replica_id: ReplicaId,
) -> LWWRegister(a) {
  let #(updated, _) = set_with_delta(register:, value:, timestamp:, replica_id:)
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
  replica_id replica_id: ReplicaId,
) -> #(LWWRegister(a), LWWRegister(a)) {
  use <- bool.guard(timestamp <= register.timestamp, #(register, register))
  let updated = new(value:, timestamp:, replica_id:)
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
/// `set` records its supplied author only for an accepted write. After `merge`
/// this is the replica whose write won, which makes it useful for provenance
/// and for tie-breaking consistently with `merge` in downstream code.
/// A v1 import retains its optional ID (or `""`), not a proven writer identity.
/// Legacy ties compare the stored key first, then this ID when keys are equal.
pub fn replica_id(register: LWWRegister(a)) -> ReplicaId {
  register.replica_id
}

/// Merge two LWW-Registers by returning the one with the higher timestamp.
///
/// When `a.timestamp > b.timestamp`, returns `a`. When `b.timestamp >
/// a.timestamp`, returns `b`. On equal timestamps, the register whose
/// `replica_id` is lexicographically greater wins for modern writes.
/// Modern writes outrank legacy imports at equal timestamps. Legacy ties
/// compare their stored keys in UTF-8 byte order. Keys must distinguish
/// different legacy payloads; equal keys use replica ID ordering to select
/// consistent metadata. Modern write identities must not be reused.
pub fn merge(a: LWWRegister(a), b: LWWRegister(a)) -> LWWRegister(a) {
  use <- bool.guard(a.timestamp > b.timestamp, a)
  use <- bool.guard(a.timestamp < b.timestamp, b)
  let comparison = case a.provenance, b.provenance {
    Modern, Modern -> replica.compare(a.replica_id, b.replica_id)
    Modern, Legacy(_) -> order.Gt
    Legacy(_), Modern -> order.Lt
    Legacy(left), Legacy(right) ->
      case bit_array.compare(<<left:utf8>>, <<right:utf8>>) {
        order.Eq -> replica.compare(a.replica_id, b.replica_id)
        order.Lt -> order.Lt
        order.Gt -> order.Gt
      }
  }
  case comparison {
    order.Gt -> a
    order.Lt -> b
    order.Eq -> a
  }
}

/// Encode a LWWRegister(String) as a self-describing JSON value.
///
/// Produces a v3 envelope preserving the writer and modern/legacy provenance.
/// Earlier readers reject v3: upgrade readers before sending this output.
///
/// Use `from_json` to decode the result back into a `LWWRegister(String)`.
pub fn to_json(register: LWWRegister(String)) -> json.Json {
  to_json_with(register, json.string)
}

/// Encode a register with a custom payload encoder, preserving write metadata.
///
/// Uses the same v3 envelope as `to_json`, including the original legacy key.
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
    #("v", json.int(3)),
    #(
      "state",
      json.object([
        #("value", encode(register.value)),
        #("timestamp", json.int(register.timestamp)),
        #("replica_id", json.string(replica.to_string(register.replica_id))),
        #("provenance", provenance_to_json(register.provenance)),
      ]),
    ),
  ])
}

/// Decode a LWWRegister(String) from a JSON string produced by `to_json`.
///
/// Imports v1 with the original String value as its legacy tie key.
/// Accepts v2 as modern (including an empty-but-present writer) and preserves
/// v3 provenance. A v1 placeholder does not prove the historical writer.
/// Pass the local replica ID to `set` for every subsequent write.
pub fn from_json(
  json_string: String,
) -> Result(LWWRegister(String), json.DecodeError) {
  use version <- result.try(envelope_version(json_string))
  case version {
    1 -> import_legacy_with(json_string, decode.string, fn(value) { value })
    _ -> from_json_with(json_string, decode.string)
  }
}

/// Decode a register with a custom payload decoder.
///
/// Accepts v2 as modern and preserves v3 provenance. Both require a string
/// `replica_id`, including when that string is empty. Rejects v1: use
/// `import_legacy_with` with a deterministic key for legacy generic payloads.
/// Invalid payloads, provenance, or envelopes return `Error`.
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
  use version <- result.try(envelope_version(json_string))
  case version {
    2 | 3 ->
      json.parse(json_string, {
        use state <- decode.field("state", {
          use value <- decode.field("value", decoder)
          use timestamp <- decode.field("timestamp", decode.int)
          use writer <- decode.field("replica_id", decode.string)
          use provenance <- decode.then(case version {
            2 -> decode.success(Modern)
            _ ->
              decode.field("provenance", provenance_decoder(), decode.success)
          })
          decode.success(LWWRegister(
            value,
            timestamp,
            replica.new(writer),
            provenance,
          ))
        })
        decode.success(state)
      })
    _ -> Error(invalid("v=2 or v=3; use import_legacy_with for v1", version))
  }
}

/// Import a v1 snapshot with an explicit deterministic legacy payload key.
///
/// Every replica must use the same key function. Different payloads at the
/// same timestamp must have different keys; equal keys must identify equal
/// payloads. Keys are compared as UTF-8 bytes, not runtime String ordering.
/// The key is persisted unchanged in v3, even with a different payload codec.
/// An optional v1 `replica_id` is retained and breaks ties only for equal keys.
///
/// For v1 data already re-encoded as v2, provenance is lost. Normal v2 decoding
/// remains modern. Recover a verified v1 baseline with an application migration
/// before calling this function; an empty v2 writer is not evidence of v1.
///
/// ## Examples
///
/// ```gleam
/// lww_register.import_legacy_with(
///   snapshot, decode.int, int.to_string,
/// )
/// ```
pub fn import_legacy_with(
  json_string: String,
  decoder: decode.Decoder(a),
  tie_key: fn(a) -> String,
) -> Result(LWWRegister(a), json.DecodeError) {
  use version <- result.try(envelope_version(json_string))
  use <- bool.guard(
    version != 1,
    Error(invalid("v=1 legacy snapshot", version)),
  )
  use #(value, timestamp, writer) <- result.try(
    json.parse(json_string, {
      use state <- decode.field("state", {
        use value <- decode.field("value", decoder)
        use timestamp <- decode.field("timestamp", decode.int)
        use writer <- decode.optional_field("replica_id", "", decode.string)
        decode.success(#(value, timestamp, writer))
      })
      decode.success(state)
    }),
  )
  Ok(LWWRegister(value, timestamp, replica.new(writer), Legacy(tie_key(value))))
}

fn provenance_to_json(provenance: Provenance) -> json.Json {
  case provenance {
    Modern -> json.object([#("kind", json.string("modern"))])
    Legacy(tie_key) ->
      json.object([
        #("kind", json.string("legacy")),
        #("tie_key", json.string(tie_key)),
      ])
  }
}

fn provenance_decoder() -> decode.Decoder(Provenance) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "modern" -> decode.success(Modern)
    "legacy" -> {
      use tie_key <- decode.field("tie_key", decode.string)
      decode.success(Legacy(tie_key))
    }
    _ -> decode.failure(Modern, "modern or legacy provenance")
  }
}

fn invalid(expected: String, version: Int) -> json.DecodeError {
  json.UnableToDecode([
    decode.DecodeError(expected, "v=" <> int.to_string(version), []),
  ])
}

fn envelope_version(json_string: String) -> Result(Int, json.DecodeError) {
  let envelope_decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(type_tag, version))
  }
  case json.parse(from: json_string, using: envelope_decoder) {
    Error(e) -> Error(e)
    Ok(#("lww_register", version)) -> Ok(version)
    Ok(#(type_tag, _)) ->
      Error(
        json.UnableToDecode([
          decode.DecodeError("type=lww_register", type_tag, ["type"]),
        ]),
      )
  }
}
