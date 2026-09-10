//// Recursive last-writer-wins maps of atomic child snapshots.
////
//// Greater timestamps win; ties select tombstones, then modern provenance,
//// then writer identity in UTF-8 byte order. Equal modern write IDs cannot name
//// different payloads.
//// Competing child snapshots are not merged. Use ORMap for collaborative edits.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import lattice_core/replica_id.{type ReplicaId}
import lattice_maps/crdt.{
  type Crdt, type CrdtSpec, type EditContext, type MergeError, type UpdateError,
}

/// A recursive map with one child schema and immutable assignment metadata.
///
/// ## Examples
///
/// ```gleam
/// let revisions: lww_map.LWWMap(Int) =
///   lww_map.new(replica_id.new("A"), crdt.OrMapSpec(crdt.SequenceSpec))
/// lww_map.keys(revisions) // -> []
/// ```
pub type LWWMap(a) =
  crdt.LWWMap(a)

/// Create an empty map for the local writer.
///
/// ## Examples
///
/// ```gleam
/// lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// ```
pub fn new(replica: ReplicaId, spec: CrdtSpec(a)) -> LWWMap(a) {
  crdt.lww_new(replica, spec)
}

/// Return the local writer identity.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let map = lww_map.new(local, crdt.TextSpec)
/// lww_map.replica_id(map) // -> local
/// ```
pub fn replica_id(map: LWWMap(a)) -> ReplicaId {
  crdt.lww_replica(map)
}

/// Return the complete child schema.
///
/// ## Examples
///
/// ```gleam
/// let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
/// let map = lww_map.new(replica_id.new("A"), schema)
/// lww_map.spec(map) // -> schema
/// ```
pub fn spec(map: LWWMap(a)) -> CrdtSpec(a) {
  crdt.lww_spec(map)
}

/// Set the local writer without changing stored assignment payloads or authors.
///
/// Queries return bound copies. Use `update` to prepare edits under the new
/// assignment's identity, rather than editing under a historical writer.
///
/// ## Examples
///
/// ```gleam
/// let source = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let snapshot = source |> lww_map.to_json |> json.to_string
/// let assert Ok(loaded) = lww_map.from_json(snapshot)
/// let local = lww_map.bind(loaded, replica_id.new("B"))
/// lww_map.replica_id(local) // -> replica_id.new("B")
/// ```
pub fn bind(map: LWWMap(a), replica: ReplicaId) -> LWWMap(a) {
  crdt.lww_bind(map, replica)
}

/// Get a locally bound copy of an active child, without modifying its assignment.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let map = lww_map.new(local, crdt.LwwRegisterSpec(""))
/// let child = crdt.CrdtLwwRegister(lww_register.new("Ready", 1, local))
/// let assert Ok(map) = lww_map.set(map, "status", child, 1)
/// let assert Ok(crdt.CrdtLwwRegister(status)) = lww_map.get(map, "status")
/// lww_register.value(status) // -> "Ready"
/// ```
pub fn get(map: LWWMap(a), key: String) -> Result(Crdt(a), Nil) {
  crdt.lww_get(map, key)
}

/// Assign a complete immutable child snapshot at a strictly greater timestamp.
///
/// For Sequence/Text edits or fresh replacements, prefer `update` and its new
/// assignment context to prevent allocation-ID reuse.
///
/// The timestamp must exceed both the key's existing timestamp and the map's
/// pruned timestamp. Schema and timestamp failures return `Error`.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let map = lww_map.new(local, crdt.LwwRegisterSpec(0))
/// let child = crdt.CrdtLwwRegister(lww_register.new(42, 1, local))
/// let assert Ok(map) = lww_map.set(map, "answer", child, 1)
/// lww_map.set(map, "answer", child, 1)
/// // -> Error(crdt.TimestampNotAdvanced("answer", 1, 1))
/// ```
pub fn set(
  map: LWWMap(a),
  key: String,
  value: Crdt(a),
  timestamp: Int,
) -> Result(LWWMap(a), MergeError) {
  crdt.lww_set(map, key, value, timestamp)
}

/// Edit once under the new assignment's namespace, then atomically assign.
///
/// To replace a child from empty, construct its default with `context.replica_id`.
/// Inherited historical IDs remain intact. Failures leave the map unchanged.
/// Do not use a fixed replica ID to construct a replacement Sequence or Text:
/// each accepted assignment needs its own allocation namespace.
///
/// ## Examples
///
/// Replace Text from empty on each write, using the new assignment's context:
///
/// ```gleam
/// import gleam/result
/// import lattice_text/text
///
/// let map: lww_map.LWWMap(String) =
///   lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// let replace = fn(_, context: crdt.EditContext) {
///   text.append(text.new(context.replica_id), "Replacement")
///   |> result.map(crdt.CrdtText)
/// }
/// let assert Ok(first) = lww_map.update(map, "body", 1, replace)
/// let assert Ok(second) = lww_map.update(first, "body", 2, replace)
/// let assert Ok(crdt.CrdtText(body)) = lww_map.get(second, "body")
/// text.value(body) // -> "Replacement"
/// ```
///
/// The same pattern gives a generic Sequence fresh item identities:
///
/// ```gleam
/// import gleam/result
/// import lattice_sequence/sequence
///
/// let map: lww_map.LWWMap(Int) =
///   lww_map.new(replica_id.new("A"), crdt.SequenceSpec)
/// let assert Ok(map) = lww_map.update(map, "items", 1, fn(_, context) {
///   sequence.insert_many(sequence.new(context.replica_id), 0, [10, 20])
///   |> result.map(crdt.CrdtSequence)
/// })
/// let assert Ok(crdt.CrdtSequence(items)) = lww_map.get(map, "items")
/// sequence.values(items) // -> [10, 20]
/// ```
///
/// To edit an existing child instead, use the callback's first argument. For an
/// LWWRegister, pass `context.replica_id` to `lww_register.set`.
pub fn update(
  map: LWWMap(a),
  key: String,
  timestamp: Int,
  callback: fn(Crdt(a), EditContext) -> Result(Crdt(a), e),
) -> Result(LWWMap(a), UpdateError(e)) {
  crdt.lww_update(map, key, timestamp, callback)
}

/// Write a tombstone at a timestamp above both the existing write and prune floor.
///
/// ## Examples
///
/// ```gleam
/// let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// let assert Ok(removed) = lww_map.remove(map, "body", 1)
/// lww_map.get(removed, "body") // -> Error(Nil)
/// ```
pub fn remove(
  map: LWWMap(a),
  key: String,
  timestamp: Int,
) -> Result(LWWMap(a), MergeError) {
  crdt.lww_remove(map, key, timestamp)
}

/// Return active keys in unspecified order.
///
/// ## Examples
///
/// ```gleam
/// let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// lww_map.keys(map) // -> []
/// ```
pub fn keys(map: LWWMap(a)) -> List(String) {
  crdt.lww_keys(map)
}

/// Return locally bound active children in unspecified order.
///
/// ## Examples
///
/// ```gleam
/// let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// lww_map.values(map) // -> []
/// ```
pub fn values(map: LWWMap(a)) -> List(Crdt(a)) {
  crdt.lww_values(map)
}

/// Return the number of retained tombstones.
///
/// ## Examples
///
/// ```gleam
/// let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// let assert Ok(map) = lww_map.remove(map, "body", 1)
/// lww_map.tombstone_count(map) // -> 1
/// ```
pub fn tombstone_count(map: LWWMap(a)) -> Int {
  crdt.lww_tombstone_count(map)
}

/// Return the stable timestamp floor.
///
/// ## Examples
///
/// ```gleam
/// let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// lww_map.prune(map, 10) |> lww_map.pruned_timestamp // -> 10
/// ```
pub fn pruned_timestamp(map: LWWMap(a)) -> Int {
  crdt.lww_pruned_timestamp(map)
}

/// Prune stable tombstones, without compacting child states.
///
/// Only advance the floor after every participating replica has observed the
/// covered writes and removals. Older remote-only entries can then be rejected.
///
/// ## Examples
///
/// ```gleam
/// let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// let assert Ok(map) = lww_map.remove(map, "body", 5)
/// // After all replicas have observed the removal at timestamp 5:
/// let pruned = lww_map.prune(map, 5)
/// lww_map.tombstone_count(pruned) // -> 0
/// lww_map.pruned_timestamp(pruned) // -> 5
/// ```
pub fn prune(map: LWWMap(a), stable: Int) -> LWWMap(a) {
  crdt.lww_prune(map, stable)
}

/// Merge atomic assignments using the left map's local identity.
///
/// Child snapshots from competing assignments are never merged together.
/// At equal timestamps, tombstones win; otherwise modern writes use writer
/// identity and imported legacy writes use their original String tie keys.
/// Both comparisons use lexicographic UTF-8 byte order on both targets.
///
/// ## Examples
///
/// ```gleam
/// let a = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(0))
/// let b = lww_map.new(replica_id.new("B"), crdt.LwwRegisterSpec(0))
/// let assert Ok(merged) = lww_map.merge(a, b)
/// lww_map.replica_id(merged) // -> replica_id.new("A")
/// ```
pub fn merge(a: LWWMap(a), b: LWWMap(a)) -> Result(LWWMap(a), MergeError) {
  merge_as(a, b, replica_id(a))
}

/// Merge into an explicit receiving identity.
///
/// The chosen assignment retains its historical writer. The receiving identity
/// applies to future writes and to bound query results.
///
/// ## Examples
///
/// ```gleam
/// let a = lww_map.new(replica_id.new("A"), crdt.TextSpec)
/// let b = lww_map.new(replica_id.new("B"), crdt.TextSpec)
/// let local = replica_id.new("C")
/// let assert Ok(merged) = lww_map.merge_as(a, b, local)
/// lww_map.replica_id(merged) // -> local
/// ```
pub fn merge_as(
  a: LWWMap(a),
  b: LWWMap(a),
  replica: ReplicaId,
) -> Result(LWWMap(a), MergeError) {
  crdt.lww_merge_as(a, b, replica)
}

/// Encode a modern String-payload snapshot (version 3).
///
/// ## Examples
///
/// ```gleam
/// let map = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let encoded = map |> lww_map.to_json |> json.to_string
/// lww_map.from_json(encoded) // -> Ok(map)
/// ```
pub fn to_json(map: LWWMap(String)) -> Json {
  to_json_with(map, json.string)
}

/// Encode a generic modern snapshot.
///
/// The encoder also handles configured register defaults in recursive schemas.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let map = lww_map.new(local, crdt.LwwRegisterSpec(0))
/// let child = crdt.CrdtLwwRegister(lww_register.new(42, 1, local))
/// let assert Ok(map) = lww_map.set(map, "answer", child, 1)
/// let encoded = lww_map.to_json_with(map, json.int) |> json.to_string
/// lww_map.from_json_with(encoded, decode.int) // -> Ok(map)
/// ```
pub fn to_json_with(map: LWWMap(a), encode: fn(a) -> Json) -> Json {
  crdt.lww_to_json_with(map, encode)
}

/// Decode a modern String snapshot.
///
/// Bind the decoded map before making writes as a different replica.
///
/// ## Examples
///
/// ```gleam
/// let source = lww_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let encoded = source |> lww_map.to_json |> json.to_string
/// let assert Ok(loaded) = lww_map.from_json(encoded)
/// let local = lww_map.bind(loaded, replica_id.new("B"))
/// lww_map.replica_id(local) // -> replica_id.new("B")
/// ```
pub fn from_json(input: String) -> Result(LWWMap(String), json.DecodeError) {
  from_json_with(input, decode.string)
}

/// Decode a generic snapshot, preserving historical writers and legacy provenance.
///
/// Legacy scalar snapshots require `import_legacy`; they are not modern
/// replication messages.
///
/// ## Examples
///
/// ```gleam
/// let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
/// let map = lww_map.new(replica_id.new("A"), schema)
/// let encoded = lww_map.to_json_with(map, json.int) |> json.to_string
/// let assert Ok(loaded) = lww_map.from_json_with(encoded, decode.int)
/// lww_map.spec(loaded) // -> schema
/// ```
pub fn from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(LWWMap(a), json.DecodeError) {
  crdt.lww_from_json_with(input, decoder)
}

/// Import old scalar String entries as LWWRegister children.
///
/// Requires an explicit register schema/default. Original String tie keys are
/// persisted as legacy provenance and compared in lexicographic UTF-8 byte
/// order, without Unicode normalization. Import an agreed baseline before cutover.
/// Distribute the resulting modern snapshot before accepting modern writes;
/// importing old messages repeatedly is not a mixed-version replication scheme.
///
/// ## Examples
///
/// ```gleam
/// import gleam/result
/// import lattice_core/replica_id
/// import lattice_maps/crdt
/// import lattice_maps/lww_map
///
/// pub fn migrate(legacy_snapshot: String) {
///   use map <- result.try(lww_map.import_legacy(
///     legacy_snapshot, crdt.LwwRegisterSpec(""),
///     replica_id.new("cutover-writer"),
///   ))
///   Ok(lww_map.to_json(map))
/// }
/// ```
pub fn import_legacy(
  input: String,
  spec: CrdtSpec(String),
  replica: ReplicaId,
) -> Result(LWWMap(String), json.DecodeError) {
  crdt.lww_import_legacy(input, spec, replica)
}
