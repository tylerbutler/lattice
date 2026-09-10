//// A globally unique identifier for a replica (node) in a distributed system.
////
//// Replica IDs are opaque wrappers around strings. Use `new` to create one
//// from a string and `to_string` to extract the underlying value. The opaque
//// type prevents accidental use of arbitrary strings where a replica ID is
//// expected.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
////
//// let rid = replica_id.new("node-a")
//// replica_id.to_string(rid)  // -> "node-a"
//// ```

import gleam/bit_array
import gleam/dynamic/decode
import gleam/json
import gleam/order

/// An opaque identifier for a replica in a distributed system.
///
/// Wraps a `String` value. Two `ReplicaId` values are equal if and only if
/// their underlying strings are equal. ReplicaId values can be used as
/// dictionary keys and set elements.
pub opaque type ReplicaId {
  ReplicaId(String)
}

/// Create a new ReplicaId from a string.
pub fn new(id: String) -> ReplicaId {
  ReplicaId(id)
}

/// Extract the underlying string from a ReplicaId.
pub fn to_string(replica_id: ReplicaId) -> String {
  let ReplicaId(s) = replica_id
  s
}

/// Compare two ReplicaId values by lexicographic UTF-8 byte order.
///
/// Uses the same order on Erlang and JavaScript for deterministic tie-breaking
/// (e.g., in LWW-Register merge when timestamps are equal). Strings retain their
/// original form; no Unicode normalization is applied.
///
/// ## Examples
///
/// ```gleam
/// compare(new("\u{e000}"), new("\u{10000}"))
/// // -> order.Lt
/// ```
pub fn compare(a: ReplicaId, b: ReplicaId) -> order.Order {
  let ReplicaId(a) = a
  let ReplicaId(b) = b
  bit_array.compare(<<a:utf8>>, <<b:utf8>>)
}

/// Encode a ReplicaId as a JSON string.
pub fn to_json(replica_id: ReplicaId) -> json.Json {
  json.string(to_string(replica_id))
}

/// A decoder for ReplicaId values in JSON.
///
/// Decodes a JSON string and wraps it in a ReplicaId. Useful as a building
/// block in `from_json` decoders across the library.
pub fn decoder() -> decode.Decoder(ReplicaId) {
  decode.map(decode.string, new)
}
