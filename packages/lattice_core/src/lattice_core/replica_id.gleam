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

import gleam/dynamic/decode
import gleam/json
import gleam/order
import gleam/string

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

/// Compare two ReplicaId values lexicographically.
///
/// Delegates to `string.compare` on the underlying strings. Used for
/// deterministic tie-breaking (e.g., in LWW-Register merge when timestamps
/// are equal).
pub fn compare(a: ReplicaId, b: ReplicaId) -> order.Order {
  string.compare(to_string(a), to_string(b))
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
