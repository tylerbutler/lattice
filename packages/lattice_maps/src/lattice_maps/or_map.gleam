//// Generation-aware observed-remove maps.
////
//// Concurrent updates join in one generation, with add-wins membership.
//// Updating after an observed removal creates a fresh generation. The newest
//// generation wins, even if it is removed; older values cannot return.
//// Sparse synchronization needs a baseline or eventual delivery of all required
//// deltas. An isolated later Sequence delta can temporarily have missing origins.

import gleam/dynamic/decode.{type Decoder}
import gleam/json.{type Json}
import gleam/result
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_maps/crdt.{
  type Crdt, type CrdtDelta, type CrdtSpec, type EditContext, type MergeError,
  type UpdateError,
}

/// A map with one recursive child schema.
///
/// ## Examples
///
/// ```gleam
/// let documents: or_map.ORMap(Int) =
///   or_map.new(replica_id.new("A"), crdt.OrMapSpec(crdt.SequenceSpec))
/// or_map.keys(documents) // -> []
/// ```
pub type ORMap(a) =
  crdt.ORMap(a)

/// A sparse generation-qualified change, not a map snapshot.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(0))
/// let delta: or_map.ORMapDelta(Int) = or_map.empty_delta(map)
/// or_map.apply_delta(map, delta) // -> Ok(map)
/// ```
pub type ORMapDelta(a) =
  crdt.ORMapDelta(a)

/// Create an empty map.
///
/// ## Examples
///
/// ```gleam
/// or_map.new(replica_id.new("A"), crdt.OrMapSpec(crdt.TextSpec))
/// ```
pub fn new(replica: ReplicaId, spec: CrdtSpec(a)) -> ORMap(a) {
  crdt.or_new(replica, spec)
}

/// Return the local editing identity.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let map = or_map.new(local, crdt.TextSpec)
/// or_map.replica_id(map) // -> local
/// ```
pub fn replica_id(map: ORMap(a)) -> ReplicaId {
  crdt.or_replica(map)
}

/// Return the complete child schema.
///
/// ## Examples
///
/// ```gleam
/// let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
/// let map = or_map.new(replica_id.new("A"), schema)
/// or_map.spec(map) // -> schema
/// ```
pub fn spec(map: ORMap(a)) -> CrdtSpec(a) {
  crdt.or_spec(map)
}

/// Bind a loaded or received map to the local writer without rewriting history.
///
/// Child callbacks receive identities scoped by key and generation. Keep each
/// independent writer's logical replica ID distinct.
///
/// ## Examples
///
/// ```gleam
/// let source = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let snapshot = source |> or_map.to_json |> json.to_string
/// let assert Ok(loaded) = or_map.from_json(snapshot)
/// let local = or_map.bind(loaded, replica_id.new("B"))
/// or_map.replica_id(local) // -> replica_id.new("B")
/// ```
pub fn bind(map: ORMap(a), replica: ReplicaId) -> ORMap(a) {
  crdt.or_bind(map, replica)
}

/// Get an active child bound to this map's local editing scope.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.GCounterSpec)
/// let assert Ok(map) = or_map.update(map, "score", fn(value) { value })
/// let assert Ok(crdt.CrdtGCounter(counter)) = or_map.get(map, "score")
/// g_counter.value(counter) // -> 0
/// ```
pub fn get(map: ORMap(a), key: String) -> Result(Crdt(a), Nil) {
  crdt.or_get(map, key)
}

/// Return active keys, in unspecified order.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// let assert Ok(map) = or_map.update(map, "body", fn(value) { value })
/// or_map.keys(map) // -> ["body"]
/// ```
pub fn keys(map: ORMap(a)) -> List(String) {
  crdt.or_keys(map)
}

/// Return active, locally bound children, in unspecified order.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// or_map.values(map) // -> []
/// ```
pub fn values(map: ORMap(a)) -> List(Crdt(a)) {
  crdt.or_values(map)
}

/// Join the callback's full child state within the current generation.
///
/// Removal/re-add, rather than a non-monotone callback, resets a child.
/// Use `update_delta` when a leaf operation can return a sparse delta, or when
/// a new LWWRegister write needs the callback's explicit author identity.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.GSetSpec)
/// let assert Ok(map) = or_map.update(map, "tags", fn(value) {
///   let assert crdt.CrdtGSet(tags) = value
///   crdt.CrdtGSet(g_set.add(tags, "reviewed"))
/// })
/// or_map.keys(map) // -> ["tags"]
/// ```
pub fn update(
  map: ORMap(a),
  key: String,
  callback: fn(Crdt(a)) -> Crdt(a),
) -> Result(ORMap(a), MergeError) {
  update_with_delta(map, key, callback) |> result.map(fn(pair) { pair.0 })
}

/// Run a full-value callback once and return the touched-key state delta.
///
/// The delta carries the complete returned child state. For large Sequence/Text
/// children, use `update_delta` instead.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.GSetSpec)
/// let assert Ok(#(updated, delta)) =
///   or_map.update_with_delta(map, "tags", fn(value) {
///     let assert crdt.CrdtGSet(tags) = value
///     crdt.CrdtGSet(g_set.add(tags, "ready"))
///   })
/// or_map.apply_delta(map, delta) // -> Ok(updated)
/// ```
pub fn update_with_delta(
  map: ORMap(a),
  key: String,
  callback: fn(Crdt(a)) -> Crdt(a),
) -> Result(#(ORMap(a), ORMapDelta(a)), MergeError) {
  crdt.or_update_with_delta(map, key, callback)
}

/// Run a sparse callback once, apply its delta, and return the resulting map/change.
///
/// Errors are atomic. `NoChange` still refreshes membership, so it is an
/// add-wins update. The callback context supplies the scoped author for new
/// LWWRegister writes. Nested maps return `crdt.OrMapChange(child_delta)`.
///
/// ## Examples
///
/// Author a register write with the supplied scope, not the old write's author:
///
/// ```gleam
/// import lattice_registers/lww_register
///
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let assert Ok(#(updated, delta)) =
///   or_map.update_delta(map, "title", fn(value, context) {
///     let assert crdt.CrdtLwwRegister(register) = value
///     let #(_, change) = lww_register.set_with_delta(
///       register, "New title", lww_register.timestamp(register) + 1,
///       context.replica_id,
///     )
///     Ok(crdt.StateDelta(crdt.CrdtLwwRegister(change)))
///   })
/// or_map.apply_delta(map, delta) // -> Ok(updated)
/// ```
///
/// Keep an inner ORMap change sparse through the outer map:
///
/// ```gleam
/// import gleam/result
/// import lattice_text/text
///
/// let map: or_map.ORMap(String) =
///   or_map.new(replica_id.new("A"), crdt.OrMapSpec(crdt.TextSpec))
/// let assert Ok(#(updated, delta)) =
///   or_map.update_delta(map, "document", fn(value, _) {
///     let assert crdt.CrdtOrMap(document) = value
///     use #(_, change) <- result.try(
///       or_map.update_delta(document, "body", fn(value, _) {
///         let assert crdt.CrdtText(body) = value
///         use #(_, change) <- result.try(text.append_with_delta(body, "Hello"))
///         Ok(crdt.StateDelta(crdt.CrdtText(change)))
///       }),
///     )
///     Ok(crdt.OrMapChange(change))
///   })
/// or_map.apply_delta(map, delta) // -> Ok(updated)
/// ```
pub fn update_delta(
  map: ORMap(a),
  key: String,
  callback: fn(Crdt(a), EditContext) -> Result(CrdtDelta(a), e),
) -> Result(#(ORMap(a), ORMapDelta(a)), UpdateError(e)) {
  crdt.or_update_delta(map, key, callback)
}

/// Remove observed membership; keep current-generation child history.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// let assert Ok(map) = or_map.update(map, "body", fn(value) { value })
/// or_map.remove(map, "body") |> or_map.get("body") // -> Error(Nil)
/// ```
pub fn remove(map: ORMap(a), key: String) -> ORMap(a) {
  remove_with_delta(map, key).0
}

/// Remove observed membership and return a generation-bearing removal delta.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// let assert Ok(map) = or_map.update(map, "body", fn(value) { value })
/// let #(removed, delta) = or_map.remove_with_delta(map, "body")
/// or_map.apply_delta(map, delta) // -> Ok(removed)
/// ```
pub fn remove_with_delta(
  map: ORMap(a),
  key: String,
) -> #(ORMap(a), ORMapDelta(a)) {
  crdt.or_remove_with_delta(map, key)
}

/// Merge into the left map's local identity.
///
/// ## Examples
///
/// ```gleam
/// let a = or_map.new(replica_id.new("A"), crdt.GCounterSpec)
/// let b = or_map.new(replica_id.new("B"), crdt.GCounterSpec)
/// let assert Ok(merged) = or_map.merge(a, b)
/// or_map.replica_id(merged) // -> replica_id.new("A")
/// ```
pub fn merge(a: ORMap(a), b: ORMap(a)) -> Result(ORMap(a), MergeError) {
  merge_as(a, b, replica_id(a))
}

/// Merge into an explicit receiving identity, including remote-only children.
///
/// ## Examples
///
/// ```gleam
/// let a = or_map.new(replica_id.new("A"), crdt.SequenceSpec)
/// let b = or_map.new(replica_id.new("B"), crdt.SequenceSpec)
/// let local = replica_id.new("C")
/// let assert Ok(merged) = or_map.merge_as(a, b, local)
/// or_map.replica_id(merged) // -> local
/// ```
pub fn merge_as(
  a: ORMap(a),
  b: ORMap(a),
  replica: ReplicaId,
) -> Result(ORMap(a), MergeError) {
  crdt.or_merge_as(a, b, replica)
}

/// Return an empty transport batch.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// or_map.apply_delta(map, or_map.empty_delta(map)) // -> Ok(map)
/// ```
pub fn empty_delta(map: ORMap(a)) -> ORMapDelta(a) {
  crdt.or_empty_delta(map)
}

/// Apply only touched keys, selecting generations before child changes.
///
/// Missing Sequence origins can produce an incomplete view until the required
/// baseline or earlier deltas arrive. Bind the receiving map before editing it.
///
/// ## Examples
///
/// ```gleam
/// let source = or_map.new(replica_id.new("A"), crdt.GCounterSpec)
/// let assert Ok(#(_, delta)) =
///   or_map.update_with_delta(source, "score", fn(value) { value })
/// let receiver = or_map.new(replica_id.new("B"), crdt.GCounterSpec)
/// let assert Ok(receiver) = or_map.apply_delta(receiver, delta)
/// or_map.keys(receiver) // -> ["score"]
/// ```
pub fn apply_delta(
  map: ORMap(a),
  delta: ORMapDelta(a),
) -> Result(ORMap(a), MergeError) {
  crdt.or_apply_delta(map, delta)
}

/// Combine sparse changes without turning nested deltas into snapshots.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// let assert Ok(#(first, a)) =
///   or_map.update_with_delta(map, "first", fn(value) { value })
/// let assert Ok(#(updated, b)) =
///   or_map.update_with_delta(first, "second", fn(value) { value })
/// let assert Ok(batch) = or_map.merge_deltas(a, b)
/// or_map.apply_delta(map, batch) // -> Ok(updated)
/// ```
pub fn merge_deltas(
  a: ORMapDelta(a),
  b: ORMapDelta(a),
) -> Result(ORMapDelta(a), MergeError) {
  crdt.or_merge_deltas(a, b)
}

/// Prune stable membership tombstones, but retain floors and current leaf history.
///
/// Outer stability never compacts inner Sequence/Text history or forwardings.
/// The vector must cover the namespaced membership tags in map deltas, not the
/// logical writer's unrelated leaf clocks. Each key/generation is a causal scope.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// // An empty frontier makes no events stable.
/// or_map.prune(map, version_vector.new()) // -> map
/// ```
pub fn prune(map: ORMap(a), stable: VersionVector) -> ORMap(a) {
  crdt.or_prune(map, stable)
}

@internal
pub fn internal_value_count(map: ORMap(a)) -> Int {
  crdt.or_value_count(map)
}

/// Encode a String-payload modern snapshot (version 3).
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let encoded = map |> or_map.to_json |> json.to_string
/// or_map.from_json(encoded) // -> Ok(map)
/// ```
pub fn to_json(map: ORMap(String)) -> Json {
  crdt.or_to_json_with(map, json.string)
}

/// Encode a generic modern snapshot.
///
/// The encoder handles payloads and configured register defaults at every depth.
/// Text remains a concrete String/grapheme type.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(
///   replica_id.new("A"), crdt.OrMapSpec(crdt.LwwRegisterSpec(42)),
/// )
/// let encoded = or_map.to_json_with(map, json.int) |> json.to_string
/// or_map.from_json_with(encoded, decode.int) // -> Ok(map)
/// ```
pub fn to_json_with(map: ORMap(a), encode: fn(a) -> Json) -> Json {
  crdt.or_to_json_with(map, encode)
}

/// Decode a modern String snapshot. Call `bind` before editing as another writer.
///
/// ## Examples
///
/// ```gleam
/// let source = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let encoded = source |> or_map.to_json |> json.to_string
/// let assert Ok(loaded) = or_map.from_json(encoded)
/// let local = or_map.bind(loaded, replica_id.new("B"))
/// or_map.replica_id(local) // -> replica_id.new("B")
/// ```
pub fn from_json(input: String) -> Result(ORMap(String), json.DecodeError) {
  from_json_with(input, decode.string)
}

/// Decode a generic modern snapshot, including recursive configured defaults.
///
/// Legacy map snapshots require `import_legacy` instead.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
/// let encoded = or_map.to_json_with(map, json.int) |> json.to_string
/// let assert Ok(loaded) = or_map.from_json_with(encoded, decode.int)
/// or_map.spec(loaded) // -> crdt.LwwRegisterSpec(42)
/// ```
pub fn from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(ORMap(a), json.DecodeError) {
  crdt.or_from_json_with(input, decoder)
}

/// Encode a String-payload sparse delta (version 2).
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let delta = or_map.empty_delta(map)
/// let encoded = delta |> or_map.delta_to_json |> json.to_string
/// or_map.delta_from_json(encoded) // -> Ok(delta)
/// ```
pub fn delta_to_json(delta: ORMapDelta(String)) -> Json {
  delta_to_json_with(delta, json.string)
}

/// Encode a generic sparse delta.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
/// let assert Ok(#(_, delta)) = or_map.update_delta(map, "answer", fn(_, _) {
///   Ok(crdt.NoChange(crdt.LwwRegisterSpec(42)))
/// })
/// let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
/// or_map.delta_from_json_with(encoded, decode.int) // -> Ok(delta)
/// ```
pub fn delta_to_json_with(delta: ORMapDelta(a), encode: fn(a) -> Json) -> Json {
  crdt.or_delta_to_json_with(delta, encode)
}

/// Decode a modern String delta. Legacy map deltas are intentionally rejected.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let delta = or_map.empty_delta(map)
/// let encoded = delta |> or_map.delta_to_json |> json.to_string
/// let assert Ok(decoded) = or_map.delta_from_json(encoded)
/// or_map.apply_delta(map, decoded) // -> Ok(map)
/// ```
pub fn delta_from_json(
  input: String,
) -> Result(ORMapDelta(String), json.DecodeError) {
  delta_from_json_with(input, decode.string)
}

/// Decode a generic sparse delta.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
/// let delta = or_map.empty_delta(map)
/// let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
/// let assert Ok(decoded) = or_map.delta_from_json_with(encoded, decode.int)
/// or_map.apply_delta(map, decoded) // -> Ok(map)
/// ```
pub fn delta_from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(ORMapDelta(a), json.DecodeError) {
  crdt.or_delta_from_json_with(input, decoder)
}

/// Import a coordinated legacy baseline into Initial generations.
///
/// Supply the agreed schema/default and a fresh editing identity if old allocation
/// history is missing. Distribute a modern snapshot; do not mix old map deltas.
///
/// ## Examples
///
/// Convert an agreed legacy register-map baseline to a modern snapshot:
///
/// ```gleam
/// import gleam/dynamic/decode
/// import gleam/result
/// import lattice_core/replica_id
/// import lattice_maps/crdt
/// import lattice_maps/or_map
///
/// pub fn migrate(legacy_snapshot: String) {
///   use map <- result.try(or_map.import_legacy(
///     legacy_snapshot, crdt.LwwRegisterSpec(""), decode.string,
///     replica_id.new("cutover-writer"),
///   ))
///   Ok(or_map.to_json(map))
/// }
/// ```
pub fn import_legacy(
  input: String,
  spec: CrdtSpec(a),
  decoder: Decoder(a),
  replica: ReplicaId,
) -> Result(ORMap(a), json.DecodeError) {
  crdt.or_import_legacy(input, spec, decoder, replica)
}
