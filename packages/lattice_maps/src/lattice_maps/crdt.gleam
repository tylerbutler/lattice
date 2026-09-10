//// Typed recursive CRDT composition.
////
//// Maps and dispatch share this module to keep the module graph acyclic.
//// A map has one recursive child schema. Text has a concrete grapheme payload;
//// the other parameterized leaves share the application's payload type.

import gleam/bool
import gleam/dict
import gleam/dynamic/decode.{type Decoder}
import gleam/int
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/set
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_counters/g_counter.{type GCounter}
import lattice_counters/pn_counter.{type PNCounter}
import lattice_maps/internal/lww_map_engine as lww
import lattice_maps/internal/or_map_engine as observed
import lattice_registers/lww_register.{type LWWRegister}
import lattice_registers/mv_register.{type MVRegister}
import lattice_sequence/sequence.{type Sequence}
import lattice_sets/g_set.{type GSet}
import lattice_sets/or_set.{type ORSet}
import lattice_sets/two_p_set.{type TwoPSet}
import lattice_text/text.{type Text}

/// Built-in states, including recursive containers.
///
/// Registers, sets, and Sequence share the payload type `a`. Text always stores
/// String graphemes. Maps hold one recursive child schema, not a schema per key.
/// VersionVector is available through dispatch but has no constructor spec.
///
/// ## Examples
///
/// ```gleam
/// let state: crdt.Crdt(Int) = crdt.CrdtOrMap(
///   or_map.new(replica_id.new("A"), crdt.SequenceSpec),
/// )
/// crdt.type_name(state) // -> "or_map"
/// ```
pub type Crdt(a) {
  CrdtGCounter(GCounter)
  CrdtPnCounter(PNCounter)
  CrdtLwwRegister(LWWRegister(a))
  CrdtMvRegister(MVRegister(a))
  CrdtGSet(GSet(a))
  CrdtTwoPSet(TwoPSet(a))
  CrdtOrSet(ORSet(a))
  CrdtVersionVector(VersionVector)
  CrdtSequence(Sequence(a))
  CrdtText(Text)
  CrdtOrMap(ORMap(a))
  CrdtLwwMap(LWWMap(a))
}

/// A complete child schema, including configured register defaults.
///
/// `OrMapSpec` and `LwwMapSpec` each describe one child schema recursively.
/// Two maps must agree on the complete schema, including register initial values.
/// A register's current value can differ from its configured initial value.
///
/// ## Examples
///
/// ```gleam
/// let schema: crdt.CrdtSpec(Int) =
///   crdt.OrMapSpec(crdt.LwwMapSpec(crdt.LwwRegisterSpec(42)))
/// let state = crdt.default_crdt(schema, replica_id.new("A"))
/// crdt.matches_spec(state, schema) // -> True
/// ```
pub type CrdtSpec(a) {
  GCounterSpec
  PnCounterSpec
  LwwRegisterSpec(initial_value: a)
  MvRegisterSpec
  GSetSpec
  TwoPSetSpec
  OrSetSpec
  SequenceSpec
  TextSpec
  OrMapSpec(child_spec: CrdtSpec(a))
  LwwMapSpec(child_spec: CrdtSpec(a))
}

/// State deltas and sparse recursive map changes are distinct.
///
/// Use `StateDelta` for a leaf delta or an explicit full snapshot. Use
/// `OrMapChange` for a sparse nested ORMap change. LWWMap assignments use complete
/// snapshots, not a separate LWWMap delta type. `NoChange` carries a schema and
/// avoids treating a configured register default as a universal merge identity.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
/// let delta: crdt.CrdtDelta(Int) =
///   crdt.OrMapChange(or_map.empty_delta(map))
/// crdt.matches_delta(delta, crdt.OrMapSpec(crdt.LwwRegisterSpec(42)))
/// // -> True
/// ```
pub type CrdtDelta(a) {
  NoChange(CrdtSpec(a))
  StateDelta(Crdt(a))
  OrMapChange(ORMapDelta(a))
}

/// An observed-remove map with permanent newest-generation floors.
///
/// Construct and edit it through `lattice_maps/or_map`.
///
/// ## Examples
///
/// ```gleam
/// let map: crdt.ORMap(Int) =
///   or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
/// or_map.keys(map) // -> []
/// ```
pub opaque type ORMap(a) {
  ORMap(replica: ReplicaId, spec: CrdtSpec(a), state: observed.State(Crdt(a)))
}

/// A sparse, generation-qualified ORMap change.
///
/// Construct and apply changes through `lattice_maps/or_map`.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
/// let delta: crdt.ORMapDelta(Int) = or_map.empty_delta(map)
/// or_map.apply_delta(map, delta) // -> Ok(map)
/// ```
pub opaque type ORMapDelta(a) {
  ORMapDelta(
    replica: ReplicaId,
    spec: CrdtSpec(a),
    state: observed.State(CrdtDelta(a)),
  )
}

/// A map of immutable atomic child assignments.
///
/// Construct and edit it through `lattice_maps/lww_map`.
///
/// ## Examples
///
/// ```gleam
/// let map: crdt.LWWMap(Int) =
///   lww_map.new(replica_id.new("A"), crdt.SequenceSpec)
/// lww_map.keys(map) // -> []
/// ```
pub opaque type LWWMap(a) {
  LWWMap(replica: ReplicaId, spec: CrdtSpec(a), state: lww.State(Crdt(a)))
}

/// Invalid schemas and immutable writes are reported rather than replaced.
///
/// `AtKey` identifies the affected nested key. A `ConflictingWrite` means two
/// different payloads claim the same immutable modern LWW write identity.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let counter = crdt.default_crdt(crdt.GCounterSpec, local)
/// let text = crdt.default_crdt(crdt.TextSpec, local)
/// crdt.merge(counter, text, local)
/// // -> Error(crdt.TypeMismatch("g_counter", "text"))
/// ```
pub type MergeError {
  TypeMismatch(expected: String, found: String)
  SchemaMismatch
  AtKey(key: String, cause: MergeError)
  TimestampNotAdvanced(key: String, timestamp: Int, floor: Int)
  ConflictingWrite(key: String, timestamp: Int)
  ClockExhausted(key: String)
  InvalidTimestamp(key: String, timestamp: Int)
}

/// A callback failure is distinct from a composition failure.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.TextSpec)
/// or_map.update_delta(map, "body", fn(_, _) { Error("read-only") })
/// // -> Error(crdt.CallbackError("read-only"))
/// ```
pub type UpdateError(e) {
  CallbackError(e)
  CompositionError(MergeError)
}

/// Use `replica_id` to author new leaf writes, not to rewrite old authors.
///
/// The reserved `lattice-map:` namespace uses length-framed scope components.
/// OR scopes include key and generation; LWW scopes also include the new write.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(""))
/// let assert Ok(#(updated, _)) =
///   or_map.update_delta(map, "title", fn(value, context) {
///     let assert crdt.CrdtLwwRegister(register) = value
///     let written = lww_register.set(
///       register, "Ready", lww_register.timestamp(register) + 1,
///       context.replica_id,
///     )
///     Ok(crdt.StateDelta(crdt.CrdtLwwRegister(written)))
///   })
/// or_map.keys(updated) // -> ["title"]
/// ```
pub type EditContext {
  EditContext(replica_id: ReplicaId)
}

/// Return the dispatch discriminator.
///
/// ## Examples
///
/// ```gleam
/// let state = crdt.default_crdt(crdt.TextSpec, replica_id.new("A"))
/// crdt.type_name(state) // -> "text"
/// ```
pub fn type_name(value: Crdt(a)) -> String {
  case value {
    CrdtGCounter(_) -> "g_counter"
    CrdtPnCounter(_) -> "pn_counter"
    CrdtLwwRegister(_) -> "lww_register"
    CrdtMvRegister(_) -> "mv_register"
    CrdtGSet(_) -> "g_set"
    CrdtTwoPSet(_) -> "two_p_set"
    CrdtOrSet(_) -> "or_set"
    CrdtVersionVector(_) -> "version_vector"
    CrdtSequence(_) -> "sequence"
    CrdtText(_) -> "text"
    CrdtOrMap(_) -> "or_map"
    CrdtLwwMap(_) -> "lww_map"
  }
}

/// Return a schema's outer discriminator.
///
/// This name alone does not identify a complete recursive schema or its defaults.
///
/// ## Examples
///
/// ```gleam
/// crdt.spec_name(crdt.OrMapSpec(crdt.LwwRegisterSpec(42))) // -> "or_map"
/// ```
pub fn spec_name(spec: CrdtSpec(a)) -> String {
  case spec {
    GCounterSpec -> "g_counter"
    PnCounterSpec -> "pn_counter"
    LwwRegisterSpec(_) -> "lww_register"
    MvRegisterSpec -> "mv_register"
    GSetSpec -> "g_set"
    TwoPSetSpec -> "two_p_set"
    OrSetSpec -> "or_set"
    SequenceSpec -> "sequence"
    TextSpec -> "text"
    OrMapSpec(_) -> "or_map"
    LwwMapSpec(_) -> "lww_map"
  }
}

/// Create a valid empty/default child for the configured schema.
///
/// Maps start without entries; Sequence and Text start empty. A register uses
/// its configured initial value at timestamp zero.
///
/// ## Examples
///
/// ```gleam
/// let assert crdt.CrdtLwwRegister(register) =
///   crdt.default_crdt(crdt.LwwRegisterSpec(42), replica_id.new("A"))
/// lww_register.value(register) // -> 42
/// ```
pub fn default_crdt(spec: CrdtSpec(a), replica: ReplicaId) -> Crdt(a) {
  case spec {
    GCounterSpec -> CrdtGCounter(g_counter.new(replica))
    PnCounterSpec -> CrdtPnCounter(pn_counter.new(replica))
    LwwRegisterSpec(initial) ->
      CrdtLwwRegister(lww_register.new(initial, 0, replica))
    MvRegisterSpec -> CrdtMvRegister(mv_register.new(replica))
    GSetSpec -> CrdtGSet(g_set.new())
    TwoPSetSpec -> CrdtTwoPSet(two_p_set.new())
    OrSetSpec -> CrdtOrSet(or_set.new(replica))
    SequenceSpec -> CrdtSequence(sequence.new(replica))
    TextSpec -> CrdtText(text.new(replica))
    OrMapSpec(child) -> CrdtOrMap(or_new(replica, child))
    LwwMapSpec(child) -> CrdtLwwMap(lww_new(replica, child))
  }
}

/// Check complete recursive schema agreement.
///
/// ## Examples
///
/// ```gleam
/// let state = crdt.default_crdt(
///   crdt.OrMapSpec(crdt.LwwRegisterSpec(42)), replica_id.new("A"),
/// )
/// crdt.matches_spec(state, crdt.OrMapSpec(crdt.LwwRegisterSpec(42)))
/// // -> True
/// crdt.matches_spec(state, crdt.OrMapSpec(crdt.LwwRegisterSpec(0)))
/// // -> False
/// ```
pub fn matches_spec(value: Crdt(a), spec: CrdtSpec(a)) -> Bool {
  case value, spec {
    CrdtOrMap(map), OrMapSpec(child) -> map.spec == child
    CrdtLwwMap(map), LwwMapSpec(child) -> map.spec == child
    _, _ -> type_name(value) == spec_name(spec)
  }
}

fn check_spec(value: Crdt(a), spec: CrdtSpec(a)) -> Result(Nil, MergeError) {
  use <- bool.guard(matches_spec(value, spec), Ok(Nil))
  case type_name(value) == spec_name(spec) {
    True -> Error(SchemaMismatch)
    False -> Error(TypeMismatch(spec_name(spec), type_name(value)))
  }
}

fn same_spec(a: CrdtSpec(a), b: CrdtSpec(a)) -> Result(Nil, MergeError) {
  use <- bool.guard(a == b, Ok(Nil))
  case spec_name(a) == spec_name(b) {
    True -> Error(SchemaMismatch)
    False -> Error(TypeMismatch(spec_name(a), spec_name(b)))
  }
}

/// The delta identity is explicit; configured initial values are not bottoms.
///
/// The replica argument does not affect `NoChange`. It is not an authored write.
///
/// ## Examples
///
/// ```gleam
/// crdt.default_delta(crdt.LwwRegisterSpec(42), replica_id.new("A"))
/// // -> crdt.NoChange(crdt.LwwRegisterSpec(42))
/// ```
pub fn default_delta(spec: CrdtSpec(a), _replica: ReplicaId) -> CrdtDelta(a) {
  NoChange(spec)
}

/// Return whether this delta has no leaf or membership changes.
///
/// A `StateDelta` is not treated as empty, even if its child looks like a default.
/// An ORMap update that returns `NoChange` still refreshes outer membership.
///
/// ## Examples
///
/// ```gleam
/// crdt.is_empty_delta(crdt.NoChange(crdt.LwwRegisterSpec(42))) // -> True
/// ```
pub fn is_empty_delta(value: CrdtDelta(a)) -> Bool {
  case value {
    NoChange(_) -> True
    OrMapChange(delta) ->
      dict.is_empty(delta.state.entries) && delta.state.clock == 0
    StateDelta(_) -> False
  }
}

/// Bind local editing identity without changing historical IDs or write authors.
///
/// Use this after loading or adopting a remote state. It does not author a new
/// LWWRegister write; use `lww_register.set` for that operation.
///
/// ## Examples
///
/// ```gleam
/// let original = crdt.CrdtLwwRegister(
///   lww_register.new("Old write", 1, replica_id.new("A")),
/// )
/// crdt.bind(original, replica_id.new("B")) // -> original
/// ```
pub fn bind(value: Crdt(a), replica: ReplicaId) -> Crdt(a) {
  case value {
    CrdtGCounter(c) -> CrdtGCounter(g_counter.merge(g_counter.new(replica), c))
    CrdtPnCounter(c) ->
      CrdtPnCounter(pn_counter.merge(pn_counter.new(replica), c))
    CrdtMvRegister(c) ->
      CrdtMvRegister(mv_register.merge(mv_register.new(replica), c))
    CrdtOrSet(c) -> CrdtOrSet(or_set.merge(or_set.new(replica), c))
    CrdtSequence(c) -> CrdtSequence(sequence.bind(c, replica))
    CrdtText(c) -> CrdtText(text.bind(c, replica))
    CrdtOrMap(c) -> CrdtOrMap(or_bind(c, replica))
    CrdtLwwMap(c) -> CrdtLwwMap(lww_bind(c, replica))
    CrdtLwwRegister(_) | CrdtGSet(_) | CrdtTwoPSet(_) | CrdtVersionVector(_) ->
      value
  }
}

/// Merge states with an explicit receiving identity, including incoming-only children.
///
/// ORMaps join children within the winning generation. LWWMaps select atomic
/// child assignments instead. Different variants or recursive schemas return
/// `Error`; a mismatch is never replaced by a default state.
///
/// ## Examples
///
/// ```gleam
/// let a = crdt.default_crdt(
///   crdt.OrMapSpec(crdt.TextSpec), replica_id.new("A"),
/// )
/// let b = crdt.default_crdt(
///   crdt.OrMapSpec(crdt.TextSpec), replica_id.new("B"),
/// )
/// let local = replica_id.new("C")
/// let assert Ok(crdt.CrdtOrMap(merged)) = crdt.merge(a, b, local)
/// or_map.replica_id(merged) // -> local
/// ```
pub fn merge(
  a: Crdt(a),
  b: Crdt(a),
  replica: ReplicaId,
) -> Result(Crdt(a), MergeError) {
  let merged = case a, b {
    CrdtGCounter(a), CrdtGCounter(b) -> Ok(CrdtGCounter(g_counter.merge(a, b)))
    CrdtPnCounter(a), CrdtPnCounter(b) ->
      Ok(CrdtPnCounter(pn_counter.merge(a, b)))
    CrdtLwwRegister(a), CrdtLwwRegister(b) ->
      Ok(CrdtLwwRegister(lww_register.merge(a, b)))
    CrdtMvRegister(a), CrdtMvRegister(b) ->
      Ok(CrdtMvRegister(mv_register.merge(a, b)))
    CrdtGSet(a), CrdtGSet(b) -> Ok(CrdtGSet(g_set.merge(a, b)))
    CrdtTwoPSet(a), CrdtTwoPSet(b) -> Ok(CrdtTwoPSet(two_p_set.merge(a, b)))
    CrdtOrSet(a), CrdtOrSet(b) -> Ok(CrdtOrSet(or_set.merge(a, b)))
    CrdtVersionVector(a), CrdtVersionVector(b) ->
      Ok(CrdtVersionVector(version_vector.merge(a, b)))
    CrdtSequence(a), CrdtSequence(b) ->
      Ok(CrdtSequence(sequence.merge(a, b, replica)))
    CrdtText(a), CrdtText(b) -> Ok(CrdtText(text.merge(a, b, replica)))
    CrdtOrMap(a), CrdtOrMap(b) ->
      or_merge_as(a, b, replica) |> result.map(CrdtOrMap)
    CrdtLwwMap(a), CrdtLwwMap(b) ->
      lww_merge_as(a, b, replica) |> result.map(CrdtLwwMap)
    _, _ -> Error(TypeMismatch(type_name(a), type_name(b)))
  }
  result.map(merged, bind(_, replica))
}

/// Validate a delta against the complete child schema.
///
/// ## Examples
///
/// ```gleam
/// let delta = crdt.NoChange(crdt.LwwRegisterSpec(42))
/// crdt.matches_delta(delta, crdt.LwwRegisterSpec(42)) // -> True
/// crdt.matches_delta(delta, crdt.LwwRegisterSpec(0)) // -> False
/// ```
pub fn matches_delta(delta: CrdtDelta(a), spec: CrdtSpec(a)) -> Bool {
  case delta {
    NoChange(given) -> given == spec
    StateDelta(value) -> matches_spec(value, spec)
    OrMapChange(delta) -> spec == OrMapSpec(delta.spec)
  }
}

fn check_delta(
  delta: CrdtDelta(a),
  spec: CrdtSpec(a),
) -> Result(Nil, MergeError) {
  case delta {
    NoChange(given) -> same_spec(spec, given)
    StateDelta(value) -> check_spec(value, spec)
    OrMapChange(delta) -> same_spec(spec, OrMapSpec(delta.spec))
  }
}

/// Apply a typed change without trusting a caller-supplied replacement state.
///
/// The current state and the delta must both match `spec`. The returned state is
/// bound to `replica`; nested ORMap changes retain their generation checks.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let before = sequence.new(local)
/// let assert Ok(#(after, change)) =
///   sequence.insert_with_delta(before, 0, 42)
/// crdt.apply_delta(
///   crdt.CrdtSequence(before), crdt.StateDelta(crdt.CrdtSequence(change)),
///   crdt.SequenceSpec, local,
/// )
/// // -> Ok(crdt.CrdtSequence(after))
/// ```
pub fn apply_delta(
  value: Crdt(a),
  delta: CrdtDelta(a),
  spec: CrdtSpec(a),
  replica: ReplicaId,
) -> Result(Crdt(a), MergeError) {
  use _ <- result.try(check_spec(value, spec))
  use _ <- result.try(check_delta(delta, spec))
  case delta, value {
    NoChange(_), _ -> Ok(bind(value, replica))
    StateDelta(change), _ -> merge(value, change, replica)
    OrMapChange(change), CrdtOrMap(map) ->
      or_apply_delta(or_bind(map, replica), change) |> result.map(CrdtOrMap)
    OrMapChange(_), _ -> Error(TypeMismatch("or_map", type_name(value)))
  }
}

/// Batch sparse ORMap changes without expanding them to child snapshots.
///
/// A batch that includes an explicit `StateDelta` snapshot may remain a snapshot.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let map = or_map.new(local, crdt.LwwRegisterSpec(42))
/// let assert Ok(#(_, change)) =
///   or_map.update_with_delta(map, "answer", fn(value) { value })
/// let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
/// crdt.merge_deltas(
///   crdt.NoChange(schema), crdt.OrMapChange(change), schema, local,
/// )
/// // -> Ok(crdt.OrMapChange(change))
/// ```
pub fn merge_deltas(
  a: CrdtDelta(a),
  b: CrdtDelta(a),
  spec: CrdtSpec(a),
  replica: ReplicaId,
) -> Result(CrdtDelta(a), MergeError) {
  use _ <- result.try(check_delta(a, spec))
  use _ <- result.try(check_delta(b, spec))
  case a, b {
    NoChange(_), _ -> Ok(b)
    _, NoChange(_) -> Ok(a)
    OrMapChange(a), OrMapChange(b) ->
      or_merge_deltas(a, b) |> result.map(OrMapChange)
    StateDelta(a), other ->
      apply_delta(a, other, spec, replica) |> result.map(StateDelta)
    other, StateDelta(b) ->
      apply_delta(b, other, spec, replica) |> result.map(StateDelta)
  }
}

fn frame(value: String) -> String {
  int.to_string(string.byte_size(value)) <> ":" <> value
}

fn scope(replica: ReplicaId, parts: List(String)) -> ReplicaId {
  replica_id.new(
    "lattice-map:"
    <> frame(replica_id.to_string(replica))
    <> string.concat(list.map(parts, frame)),
  )
}

fn generation_parts(generation: observed.Generation) -> List(String) {
  case generation {
    observed.Initial -> ["initial"]
    observed.Generation(clock, creator) -> [
      "generation",
      int.to_string(clock),
      replica_id.to_string(creator),
    ]
  }
}

fn or_identity(
  replica: ReplicaId,
  key: String,
  generation: observed.Generation,
) -> ReplicaId {
  scope(replica, ["or", key, ..generation_parts(generation)])
}

fn membership_identity(
  replica: ReplicaId,
  key: String,
  generation: observed.Generation,
) -> ReplicaId {
  scope(replica, ["or-membership", key, ..generation_parts(generation)])
}

fn map_default(spec: CrdtSpec(a), identity: ReplicaId) -> Crdt(a) {
  case spec {
    // A configured default is not an authored write. All receivers must agree
    // on its author, including when a membership-only delta arrives first.
    LwwRegisterSpec(initial) ->
      CrdtLwwRegister(lww_register.new(
        initial,
        0,
        replica_id.new("lattice-map:default"),
      ))
    _ -> default_crdt(spec, identity)
  }
}

@internal
pub fn or_new(replica: ReplicaId, spec: CrdtSpec(a)) -> ORMap(a) {
  ORMap(replica, spec, observed.new())
}

@internal
pub fn or_replica(map: ORMap(a)) -> ReplicaId {
  map.replica
}

@internal
pub fn or_spec(map: ORMap(a)) -> CrdtSpec(a) {
  map.spec
}

@internal
pub fn or_bind(map: ORMap(a), replica: ReplicaId) -> ORMap(a) {
  ORMap(
    replica,
    map.spec,
    observed.State(
      ..map.state,
      entries: dict.map_values(map.state.entries, fn(key, entry) {
        observed.Entry(
          ..entry,
          membership: or_set.merge(
            or_set.new(membership_identity(replica, key, entry.generation)),
            entry.membership,
          ),
          value: option_bind(
            entry.value,
            or_identity(replica, key, entry.generation),
          ),
        )
      }),
    ),
  )
}

fn option_bind(
  value: option.Option(Crdt(a)),
  replica: ReplicaId,
) -> option.Option(Crdt(a)) {
  case value {
    Some(value) -> Some(bind(value, replica))
    None -> None
  }
}

@internal
pub fn or_get(map: ORMap(a), key: String) -> Result(Crdt(a), Nil) {
  use entry <- result.try(dict.get(map.state.entries, key))
  case observed.active(entry, key), entry.value {
    True, Some(value) ->
      Ok(bind(value, or_identity(map.replica, key, entry.generation)))
    _, _ -> Error(Nil)
  }
}

@internal
pub fn or_keys(map: ORMap(a)) -> List(String) {
  dict.fold(map.state.entries, [], fn(keys, key, entry) {
    case observed.active(entry, key), entry.value {
      True, Some(_) -> [key, ..keys]
      _, _ -> keys
    }
  })
}

@internal
pub fn or_values(map: ORMap(a)) -> List(Crdt(a)) {
  list.filter_map(or_keys(map), or_get(map, _))
}

@internal
pub fn or_value_count(map: ORMap(a)) -> Int {
  dict.fold(map.state.entries, 0, fn(count, _, entry) {
    case entry.value {
      Some(_) -> count + 1
      None -> count
    }
  })
}

@internal
pub fn or_empty_delta(map: ORMap(a)) -> ORMapDelta(a) {
  ORMapDelta(map.replica, map.spec, observed.new())
}

@internal
pub fn or_update_delta(
  map: ORMap(a),
  key: String,
  callback: fn(Crdt(a), EditContext) -> Result(CrdtDelta(a), e),
) -> Result(#(ORMap(a), ORMapDelta(a)), UpdateError(e)) {
  let needs_generation = case dict.get(map.state.entries, key) {
    Ok(entry) -> !observed.active(entry, key)
    Error(Nil) -> False
  }
  use <- bool.guard(
    needs_generation && map.state.clock >= 9_007_199_254_740_991,
    Error(CompositionError(ClockExhausted(key))),
  )
  let entry = observed.prepare(map.state, key, map.replica)
  let identity = or_identity(map.replica, key, entry.generation)
  let current = case entry.value {
    Some(value) -> bind(value, identity)
    None -> map_default(map.spec, identity)
  }
  use change <- result.try(
    callback(current, EditContext(identity)) |> result.map_error(CallbackError),
  )
  use _ <- result.try(
    check_delta(change, map.spec)
    |> result.map_error(fn(error) { CompositionError(AtKey(key, error)) }),
  )
  use change <- result.try(
    case entry.value, map.spec {
      // The configured register default is real state, not a merge identity.
      // Include it on creation/reset so every delivery order sees the same join.
      None, LwwRegisterSpec(_) ->
        apply_delta(current, change, map.spec, identity)
        |> result.map(StateDelta)
      _, _ -> Ok(change)
    }
    |> result.map_error(fn(error) { CompositionError(AtKey(key, error)) }),
  )
  let membership =
    or_set.merge(
      or_set.new(membership_identity(map.replica, key, entry.generation)),
      entry.membership,
    )
  let #(_, membership_delta) = or_set.add_with_delta(membership, key)
  let delta =
    ORMapDelta(
      map.replica,
      map.spec,
      observed.singleton(
        key,
        observed.Entry(entry.generation, membership_delta, Some(change)),
        map.state.clock,
      ),
    )
  use updated <- result.try(
    or_apply_delta(map, delta) |> result.map_error(CompositionError),
  )
  Ok(#(updated, delta))
}

@internal
pub fn or_update_with_delta(
  map: ORMap(a),
  key: String,
  callback: fn(Crdt(a)) -> Crdt(a),
) -> Result(#(ORMap(a), ORMapDelta(a)), MergeError) {
  let outcome =
    or_update_delta(map, key, fn(value, _) { Ok(StateDelta(callback(value))) })
  case outcome {
    Ok(value) -> Ok(value)
    Error(CompositionError(AtKey(_, TypeMismatch(expected, found)))) ->
      Error(TypeMismatch(expected, found))
    Error(CompositionError(error)) -> Error(error)
    Error(CallbackError(error)) -> Error(error)
  }
}

@internal
pub fn or_remove_with_delta(
  map: ORMap(a),
  key: String,
) -> #(ORMap(a), ORMapDelta(a)) {
  let #(state, delta) = observed.remove(map.state, key)
  #(ORMap(..map, state: state), ORMapDelta(map.replica, map.spec, delta))
}

@internal
pub fn or_merge_as(
  a: ORMap(a),
  b: ORMap(a),
  replica: ReplicaId,
) -> Result(ORMap(a), MergeError) {
  use _ <- result.try(same_spec(a.spec, b.spec))
  use state <- result.try(
    observed.join(a.state, b.state, fn(key, generation, left, right) {
      let identity = or_identity(replica, key, generation)
      let value = case left, right {
        Some(a), Some(b) -> merge(a, b, identity) |> result.map(Some)
        Some(a), None -> Ok(Some(bind(a, identity)))
        None, Some(b) -> Ok(Some(bind(b, identity)))
        None, None -> Ok(None)
      }
      result.map_error(value, AtKey(key, _))
    }),
  )
  Ok(or_bind(ORMap(replica, a.spec, state), replica))
}

@internal
pub fn or_apply_delta(
  map: ORMap(a),
  delta: ORMapDelta(a),
) -> Result(ORMap(a), MergeError) {
  use _ <- result.try(same_spec(map.spec, delta.spec))
  use state <- result.try(
    observed.join(map.state, delta.state, fn(key, generation, left, right) {
      let identity = or_identity(map.replica, key, generation)
      let value = case left, right {
        None, Some(StateDelta(value)) -> {
          use _ <- result.try(check_spec(value, map.spec))
          Ok(Some(bind(value, identity)))
        }
        _, Some(change) -> {
          let baseline = case left {
            Some(value) -> value
            None -> map_default(map.spec, identity)
          }
          apply_delta(baseline, change, map.spec, identity) |> result.map(Some)
        }
        Some(value), None -> Ok(Some(bind(value, identity)))
        None, None -> Ok(None)
      }
      result.map_error(value, AtKey(key, _))
    }),
  )
  Ok(or_bind(ORMap(..map, state: state), map.replica))
}

@internal
pub fn or_merge_deltas(
  a: ORMapDelta(a),
  b: ORMapDelta(a),
) -> Result(ORMapDelta(a), MergeError) {
  use _ <- result.try(same_spec(a.spec, b.spec))
  use state <- result.try(
    observed.join(a.state, b.state, fn(key, generation, left, right) {
      let value = case left, right {
        Some(a_delta), Some(b_delta) ->
          merge_deltas(
            a_delta,
            b_delta,
            a.spec,
            or_identity(a.replica, key, generation),
          )
          |> result.map(Some)
        Some(value), None | None, Some(value) -> Ok(Some(value))
        None, None -> Ok(None)
      }
      result.map_error(value, AtKey(key, _))
    }),
  )
  Ok(ORMapDelta(..a, state: state))
}

@internal
pub fn or_prune(map: ORMap(a), stable: VersionVector) -> ORMap(a) {
  ORMap(..map, state: observed.prune(map.state, stable))
}

@internal
pub fn lww_new(replica: ReplicaId, spec: CrdtSpec(a)) -> LWWMap(a) {
  LWWMap(replica, spec, lww.new())
}

@internal
pub fn lww_replica(map: LWWMap(a)) -> ReplicaId {
  map.replica
}

@internal
pub fn lww_spec(map: LWWMap(a)) -> CrdtSpec(a) {
  map.spec
}

@internal
pub fn lww_bind(map: LWWMap(a), replica: ReplicaId) -> LWWMap(a) {
  LWWMap(..map, replica: replica)
}

fn lww_error(error: lww.Error) -> MergeError {
  case error {
    lww.TimestampNotAdvanced(key, timestamp, floor) ->
      TimestampNotAdvanced(key, timestamp, floor)
    lww.ConflictingWrite(key, timestamp) -> ConflictingWrite(key, timestamp)
    lww.InvalidTimestamp(key, timestamp) -> InvalidTimestamp(key, timestamp)
  }
}

@internal
pub fn lww_get(map: LWWMap(a), key: String) -> Result(Crdt(a), Nil) {
  case dict.get(map.state.entries, key) {
    Ok(lww.Entry(Some(value), timestamp, _)) ->
      Ok(bind(
        value,
        scope(map.replica, ["lww-view", key, int.to_string(timestamp)]),
      ))
    _ -> Error(Nil)
  }
}

@internal
pub fn lww_set(
  map: LWWMap(a),
  key: String,
  value: Crdt(a),
  timestamp: Int,
) -> Result(LWWMap(a), MergeError) {
  use _ <- result.try(
    check_spec(value, map.spec) |> result.map_error(AtKey(key, _)),
  )
  use _ <- result.try(
    lww.check_timestamp(map.state, key, timestamp)
    |> result.map_error(lww_error),
  )
  // Loading an ORMap binds it to its stored identity and normalizes membership.
  // Freeze that same representation without changing historical IDs or authors.
  let value = case value {
    CrdtOrMap(child) -> CrdtOrMap(or_bind(child, child.replica))
    other -> other
  }
  Ok(
    LWWMap(
      ..map,
      state: lww.put(
        map.state,
        key,
        lww.Entry(Some(value), timestamp, lww.Modern(map.replica)),
      ),
    ),
  )
}

@internal
pub fn lww_update(
  map: LWWMap(a),
  key: String,
  timestamp: Int,
  callback: fn(Crdt(a), EditContext) -> Result(Crdt(a), e),
) -> Result(LWWMap(a), UpdateError(e)) {
  use _ <- result.try(
    lww.check_timestamp(map.state, key, timestamp)
    |> result.map_error(fn(error) { CompositionError(lww_error(error)) }),
  )
  let identity =
    scope(map.replica, ["lww-write", key, int.to_string(timestamp)])
  let current = case dict.get(map.state.entries, key) {
    Ok(lww.Entry(Some(value), _, _)) -> bind(value, identity)
    _ -> default_crdt(map.spec, identity)
  }
  use value <- result.try(
    callback(current, EditContext(identity)) |> result.map_error(CallbackError),
  )
  lww_set(map, key, value, timestamp) |> result.map_error(CompositionError)
}

@internal
pub fn lww_remove(
  map: LWWMap(a),
  key: String,
  timestamp: Int,
) -> Result(LWWMap(a), MergeError) {
  use _ <- result.try(
    lww.check_timestamp(map.state, key, timestamp)
    |> result.map_error(lww_error),
  )
  Ok(
    LWWMap(
      ..map,
      state: lww.put(
        map.state,
        key,
        lww.Entry(None, timestamp, lww.Modern(map.replica)),
      ),
    ),
  )
}

@internal
pub fn lww_keys(map: LWWMap(a)) -> List(String) {
  dict.fold(map.state.entries, [], fn(keys, key, entry) {
    case entry.value {
      Some(_) -> [key, ..keys]
      None -> keys
    }
  })
}

@internal
pub fn lww_values(map: LWWMap(a)) -> List(Crdt(a)) {
  list.filter_map(lww_keys(map), lww_get(map, _))
}

@internal
pub fn lww_tombstone_count(map: LWWMap(a)) -> Int {
  dict.size(map.state.entries) - list.length(lww_keys(map))
}

@internal
pub fn lww_pruned_timestamp(map: LWWMap(a)) -> Int {
  map.state.pruned_timestamp
}

@internal
pub fn lww_prune(map: LWWMap(a), stable: Int) -> LWWMap(a) {
  LWWMap(..map, state: lww.prune(map.state, stable))
}

@internal
pub fn lww_merge_as(
  a: LWWMap(a),
  b: LWWMap(a),
  replica: ReplicaId,
) -> Result(LWWMap(a), MergeError) {
  use _ <- result.try(same_spec(a.spec, b.spec))
  use state <- result.try(
    lww.merge(a.state, b.state, fn(a, b) { a == b })
    |> result.map_error(lww_error),
  )
  Ok(LWWMap(replica, a.spec, state))
}

fn invalid(
  expected: String,
  found: String,
  path: List(String),
) -> json.DecodeError {
  json.UnableToDecode([decode.DecodeError(expected, found, path)])
}

fn json_at_key(error: json.DecodeError, key: String) -> json.DecodeError {
  case error {
    json.UnableToDecode(errors) ->
      json.UnableToDecode(
        list.map(errors, fn(error) {
          decode.DecodeError(..error, path: ["entries", key, ..error.path])
        }),
      )
    other -> other
  }
}

fn envelope(kind: String, version: Int, state: Json) -> Json {
  json.object([
    #("type", json.string(kind)),
    #("v", json.int(version)),
    #("state", state),
  ])
}

fn check_envelope(
  input: String,
  kind: String,
  versions: List(Int),
) -> Result(Nil, json.DecodeError) {
  let decoder = {
    use tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(tag, version))
  }
  use #(tag, version) <- result.try(json.parse(input, decoder))
  case tag == kind && list.contains(versions, version) {
    True -> Ok(Nil)
    False ->
      Error(
        invalid(
          kind <> " supported protocol version",
          tag <> ":" <> int.to_string(version),
          [],
        ),
      )
  }
}

fn embedded(value: Json) -> Json {
  json.string(json.to_string(value))
}

fn optional_json(value: option.Option(a), encode: fn(a) -> Json) -> Json {
  case value {
    Some(value) -> encode(value)
    None -> json.null()
  }
}

fn parse_optional(
  value: option.Option(String),
  parser: fn(String) -> Result(a, json.DecodeError),
) -> Result(option.Option(a), json.DecodeError) {
  case value {
    Some(value) -> result.map(parser(value), Some)
    None -> Ok(None)
  }
}

fn unique_pairs(
  pairs: List(#(String, a)),
) -> Result(dict.Dict(String, a), json.DecodeError) {
  let entries = dict.from_list(pairs)
  case dict.size(entries) == list.length(pairs) {
    True -> Ok(entries)
    False -> Error(invalid("unique keys", "duplicate key", ["entries"]))
  }
}

/// Encode a recursive schema, including the register's configured initial value.
///
/// ## Examples
///
/// ```gleam
/// let schema = crdt.OrMapSpec(crdt.LwwMapSpec(crdt.LwwRegisterSpec(42)))
/// let encoded = crdt.spec_to_json_with(schema, json.int) |> json.to_string
/// crdt.spec_from_json_with(encoded, decode.int) // -> Ok(schema)
/// ```
pub fn spec_to_json_with(spec: CrdtSpec(a), encode: fn(a) -> Json) -> Json {
  let fields = case spec {
    LwwRegisterSpec(initial) -> [#("initial", encode(initial))]
    OrMapSpec(child) | LwwMapSpec(child) -> [
      #("child", embedded(spec_to_json_with(child, encode))),
    ]
    _ -> []
  }
  json.object([#("type", json.string(spec_name(spec))), ..fields])
}

/// Decode a complete recursive schema.
///
/// The payload decoder also decodes configured register initial values.
///
/// ## Examples
///
/// ```gleam
/// let schema = crdt.OrMapSpec(crdt.LwwRegisterSpec(42))
/// let encoded = crdt.spec_to_json_with(schema, json.int) |> json.to_string
/// let assert Ok(decoded) = crdt.spec_from_json_with(encoded, decode.int)
/// decoded == schema // -> True
/// ```
pub fn spec_from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(CrdtSpec(a), json.DecodeError) {
  use kind <- result.try(
    json.parse(input, {
      use kind <- decode.field("type", decode.string)
      decode.success(kind)
    }),
  )
  case kind {
    "g_counter" -> Ok(GCounterSpec)
    "pn_counter" -> Ok(PnCounterSpec)
    "lww_register" ->
      json.parse(input, {
        use initial <- decode.field("initial", decoder)
        decode.success(LwwRegisterSpec(initial))
      })
    "mv_register" -> Ok(MvRegisterSpec)
    "g_set" -> Ok(GSetSpec)
    "two_p_set" -> Ok(TwoPSetSpec)
    "or_set" -> Ok(OrSetSpec)
    "sequence" -> Ok(SequenceSpec)
    "text" -> Ok(TextSpec)
    "or_map" | "lww_map" -> {
      use child <- result.try(
        json.parse(input, {
          use child <- decode.field("child", decode.string)
          decode.success(child)
        }),
      )
      use child <- result.try(spec_from_json_with(child, decoder))
      Ok(case kind {
        "or_map" -> OrMapSpec(child)
        _ -> LwwMapSpec(child)
      })
    }
    _ -> Error(invalid("known child schema", kind, ["type"]))
  }
}

/// Encode String payloads, preserving existing standalone leaf formats.
///
/// Maps use the modern recursive protocols. Text uses a distinct dispatch
/// wrapper around its unchanged standalone Sequence envelope.
///
/// ## Examples
///
/// ```gleam
/// let state = crdt.CrdtGSet(g_set.new() |> g_set.add("ready"))
/// let encoded = state |> crdt.to_json |> json.to_string
/// crdt.from_json(encoded) // -> Ok(state)
/// ```
pub fn to_json(value: Crdt(String)) -> Json {
  case value {
    CrdtOrSet(value) -> or_set.to_json(value)
    _ -> to_json_with(value, json.string)
  }
}

/// Encode generic payloads. Text has a distinct dispatch envelope.
///
/// The encoder is used at every generic payload position, including map schema
/// defaults. Generic ORSet values use their value/tag-entry protocol.
///
/// ## Examples
///
/// ```gleam
/// let state = crdt.default_crdt(
///   crdt.OrMapSpec(crdt.LwwRegisterSpec(42)), replica_id.new("A"),
/// )
/// let encoded = crdt.to_json_with(state, json.int) |> json.to_string
/// crdt.from_json_with(encoded, decode.int) // -> Ok(state)
/// ```
pub fn to_json_with(value: Crdt(a), encode: fn(a) -> Json) -> Json {
  case value {
    CrdtGCounter(value) -> g_counter.to_json(value)
    CrdtPnCounter(value) -> pn_counter.to_json(value)
    CrdtLwwRegister(value) -> lww_register.to_json_with(value, encode)
    CrdtMvRegister(value) -> mv_register.to_json_with(value, encode)
    CrdtGSet(value) -> g_set.to_json_with(value, encode)
    CrdtTwoPSet(value) -> two_p_set.to_json_with(value, encode)
    CrdtOrSet(value) -> or_set.to_json_with(value, encode)
    CrdtVersionVector(value) -> version_vector.to_json(value)
    CrdtSequence(value) -> sequence.to_json(value, encode)
    CrdtText(value) -> envelope("text", 1, embedded(text.to_json(value)))
    CrdtOrMap(value) -> or_to_json_with(value, encode)
    CrdtLwwMap(value) -> lww_to_json_with(value, encode)
  }
}

/// Decode String states, including legacy String leaf codecs (not legacy maps).
///
/// Use the map facades' explicit import adapters for legacy map baselines.
///
/// ## Examples
///
/// ```gleam
/// let state = crdt.default_crdt(crdt.LwwRegisterSpec(""), replica_id.new("A"))
/// let encoded = state |> crdt.to_json |> json.to_string
/// crdt.from_json(encoded) // -> Ok(state)
/// ```
pub fn from_json(input: String) -> Result(Crdt(String), json.DecodeError) {
  use kind <- result.try(dispatch_tag(input))
  case kind {
    "or_set" -> {
      use version <- result.try(
        json.parse(input, {
          use version <- decode.field("v", decode.int)
          decode.success(version)
        }),
      )
      case version {
        1 | 2 -> legacy_or_set(input, decode.string) |> result.map(CrdtOrSet)
        _ -> from_json_with(input, decode.string)
      }
    }
    _ -> from_json_with(input, decode.string)
  }
}

fn dispatch_tag(input: String) -> Result(String, json.DecodeError) {
  json.parse(input, {
    use kind <- decode.field("type", decode.string)
    decode.success(kind)
  })
}

fn legacy_or_set(
  input: String,
  decoder: Decoder(a),
) -> Result(ORSet(a), json.DecodeError) {
  use legacy <- result.try(or_set.from_json(input))
  or_set.from_json_with(
    or_set.to_json_with(legacy, json.string) |> json.to_string,
    decoder,
  )
}

/// Decode a generic state; bare Sequence envelopes always dispatch as Sequence.
///
/// Bind the result before editing as another writer. A bare Sequence of Strings
/// is not inferred to be Text; only the explicit Text dispatch wrapper is Text.
///
/// ## Examples
///
/// ```gleam
/// let state = crdt.default_crdt(crdt.LwwRegisterSpec(42), replica_id.new("A"))
/// let encoded = crdt.to_json_with(state, json.int) |> json.to_string
/// let assert Ok(decoded) = crdt.from_json_with(encoded, decode.int)
/// crdt.matches_spec(decoded, crdt.LwwRegisterSpec(42)) // -> True
/// ```
pub fn from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(Crdt(a), json.DecodeError) {
  use kind <- result.try(dispatch_tag(input))
  case kind {
    "g_counter" -> g_counter.from_json(input) |> result.map(CrdtGCounter)
    "pn_counter" -> pn_counter.from_json(input) |> result.map(CrdtPnCounter)
    "lww_register" ->
      lww_register.from_json_with(input, decoder) |> result.map(CrdtLwwRegister)
    "mv_register" ->
      mv_register.from_json_with(input, decoder) |> result.map(CrdtMvRegister)
    "g_set" -> g_set.from_json_with(input, decoder) |> result.map(CrdtGSet)
    "two_p_set" ->
      two_p_set.from_json_with(input, decoder) |> result.map(CrdtTwoPSet)
    "or_set" -> or_set.from_json_with(input, decoder) |> result.map(CrdtOrSet)
    "version_vector" ->
      version_vector.from_json(input) |> result.map(CrdtVersionVector)
    "sequence" -> sequence.from_json(input, decoder) |> result.map(CrdtSequence)
    "text" -> {
      use _ <- result.try(check_envelope(input, "text", [1]))
      use payload <- result.try(
        json.parse(input, {
          use payload <- decode.field("state", decode.string)
          decode.success(payload)
        }),
      )
      text.from_json(payload) |> result.map(CrdtText)
    }
    "or_map" -> or_from_json_with(input, decoder) |> result.map(CrdtOrMap)
    "lww_map" -> lww_from_json_with(input, decoder) |> result.map(CrdtLwwMap)
    _ -> Error(invalid("known CRDT type", kind, ["type"]))
  }
}

/// Encode a String-payload dispatch delta.
///
/// ## Examples
///
/// ```gleam
/// let delta = crdt.NoChange(crdt.LwwRegisterSpec(""))
/// let encoded = delta |> crdt.delta_to_json |> json.to_string
/// crdt.delta_from_json(encoded) // -> Ok(delta)
/// ```
pub fn delta_to_json(delta: CrdtDelta(String)) -> Json {
  delta_to_json_with(delta, json.string)
}

/// Encode a typed dispatch delta without expanding nested ORMap changes.
///
/// ## Examples
///
/// ```gleam
/// let map = or_map.new(replica_id.new("A"), crdt.LwwRegisterSpec(42))
/// let delta = crdt.OrMapChange(or_map.empty_delta(map))
/// let encoded = crdt.delta_to_json_with(delta, json.int) |> json.to_string
/// crdt.delta_from_json_with(encoded, decode.int) // -> Ok(delta)
/// ```
pub fn delta_to_json_with(delta: CrdtDelta(a), encode: fn(a) -> Json) -> Json {
  let #(kind, payload) = case delta {
    NoChange(spec) -> #("none", spec_to_json_with(spec, encode))
    StateDelta(value) -> #("state", to_json_with(value, encode))
    OrMapChange(value) -> #("or_map", or_delta_to_json_with(value, encode))
  }
  envelope(
    "crdt_delta",
    1,
    json.object([#("kind", json.string(kind)), #("payload", embedded(payload))]),
  )
}

/// Decode a String-payload dispatch delta.
///
/// ## Examples
///
/// ```gleam
/// let delta = crdt.NoChange(crdt.LwwRegisterSpec(""))
/// let encoded = delta |> crdt.delta_to_json |> json.to_string
/// let assert Ok(decoded) = crdt.delta_from_json(encoded)
/// crdt.is_empty_delta(decoded) // -> True
/// ```
pub fn delta_from_json(
  input: String,
) -> Result(CrdtDelta(String), json.DecodeError) {
  delta_from_json_with(input, decode.string)
}

/// Decode a typed dispatch delta.
///
/// Apply it with `apply_delta` and the receiver's expected schema. Decoding a
/// change does not establish that it belongs to a particular receiving map.
///
/// ## Examples
///
/// ```gleam
/// let local = replica_id.new("A")
/// let schema = crdt.LwwRegisterSpec(42)
/// let delta = crdt.NoChange(schema)
/// let encoded = crdt.delta_to_json_with(delta, json.int) |> json.to_string
/// let assert Ok(decoded) = crdt.delta_from_json_with(encoded, decode.int)
/// let state = crdt.default_crdt(schema, local)
/// crdt.apply_delta(state, decoded, schema, local) // -> Ok(state)
/// ```
pub fn delta_from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(CrdtDelta(a), json.DecodeError) {
  use _ <- result.try(check_envelope(input, "crdt_delta", [1]))
  use #(kind, payload) <- result.try(
    json.parse(input, {
      use state <- decode.field("state", {
        use kind <- decode.field("kind", decode.string)
        use payload <- decode.field("payload", decode.string)
        decode.success(#(kind, payload))
      })
      decode.success(state)
    }),
  )
  case kind {
    "none" -> spec_from_json_with(payload, decoder) |> result.map(NoChange)
    "state" -> from_json_with(payload, decoder) |> result.map(StateDelta)
    "or_map" ->
      or_delta_from_json_with(payload, decoder) |> result.map(OrMapChange)
    _ -> Error(invalid("none, state, or or_map delta", kind, ["kind"]))
  }
}

fn generation_json(generation: observed.Generation) -> Json {
  case generation {
    observed.Initial ->
      json.object([#("clock", json.int(0)), #("creator", json.null())])
    observed.Generation(clock, creator) ->
      json.object([
        #("clock", json.int(clock)),
        #("creator", json.string(replica_id.to_string(creator))),
      ])
  }
}

fn generation_decoder() -> Decoder(observed.Generation) {
  use clock <- decode.field("clock", decode.int)
  use creator <- decode.field("creator", decode.optional(decode.string))
  case clock, creator {
    0, None -> decode.success(observed.Initial)
    clock, Some(creator) if clock > 0 && clock <= 9_007_199_254_740_991 ->
      decode.success(observed.Generation(clock, replica_id.new(creator)))
    _, _ ->
      decode.failure(
        observed.Initial,
        "Initial or positive safe generation with creator",
      )
  }
}

fn or_state_json(
  replica: ReplicaId,
  spec: CrdtSpec(a),
  state: observed.State(value),
  encode: fn(a) -> Json,
  encode_child: fn(value) -> Json,
) -> Json {
  json.object([
    #("replica_id", json.string(replica_id.to_string(replica))),
    #("spec", embedded(spec_to_json_with(spec, encode))),
    #("clock", json.int(state.clock)),
    #(
      "entries",
      json.array(dict.to_list(state.entries), fn(pair) {
        let #(key, entry) = pair
        json.object([
          #("key", json.string(key)),
          #("generation", generation_json(entry.generation)),
          #(
            "membership",
            embedded(or_set.to_json_with(entry.membership, json.string)),
          ),
          #(
            "value",
            optional_json(entry.value, fn(child) {
              embedded(encode_child(child))
            }),
          ),
        ])
      }),
    ),
  ])
}

@internal
pub fn or_to_json_with(map: ORMap(a), encode: fn(a) -> Json) -> Json {
  envelope(
    "or_map",
    3,
    or_state_json(map.replica, map.spec, map.state, encode, to_json_with(
      _,
      encode,
    )),
  )
}

@internal
pub fn or_delta_to_json_with(
  delta: ORMapDelta(a),
  encode: fn(a) -> Json,
) -> Json {
  envelope(
    "or_map_delta",
    2,
    or_state_json(
      delta.replica,
      delta.spec,
      delta.state,
      encode,
      delta_to_json_with(_, encode),
    ),
  )
}

fn parse_or_state(
  input: String,
  decoder: Decoder(a),
  parse_child: fn(String, CrdtSpec(a)) -> Result(value, json.DecodeError),
) -> Result(#(ReplicaId, CrdtSpec(a), observed.State(value)), json.DecodeError) {
  let entry_decoder = {
    use key <- decode.field("key", decode.string)
    use generation <- decode.field("generation", generation_decoder())
    use membership <- decode.field("membership", decode.string)
    use value <- decode.field("value", decode.optional(decode.string))
    decode.success(#(key, generation, membership, value))
  }
  use #(replica, spec, clock, entries) <- result.try(
    json.parse(input, {
      use state <- decode.field("state", {
        use replica <- decode.field("replica_id", decode.string)
        use spec <- decode.field("spec", decode.string)
        use clock <- decode.field("clock", decode.int)
        use entries <- decode.field("entries", decode.list(entry_decoder))
        decode.success(#(replica, spec, clock, entries))
      })
      decode.success(state)
    }),
  )
  use _ <- result.try(case clock >= 0 && clock <= 9_007_199_254_740_991 {
    True -> Ok(Nil)
    False ->
      Error(
        invalid("safe nonnegative allocation clock", int.to_string(clock), [
          "clock",
        ]),
      )
  })
  use spec <- result.try(spec_from_json_with(spec, decoder))
  use entries <- result.try(
    list.try_map(entries, fn(entry) {
      let #(key, generation, membership, value) = entry
      use <- bool.guard(
        observed.clock(generation) > clock,
        Error(invalid("clock covering all generations", key, ["clock"])),
      )
      use membership <- result.try(or_set.from_json_with(
        membership,
        decode.string,
      ))
      use <- bool.guard(
        set.to_list(or_set.value(membership))
          |> list.any(fn(member) { member != key }),
        Error(
          invalid("membership only for entry key", key, [
            "entries",
            key,
            "membership",
          ]),
        ),
      )
      use value <- result.try(
        parse_optional(value, parse_child(_, spec))
        |> result.map_error(json_at_key(_, key)),
      )
      Ok(#(key, observed.Entry(generation, membership, value)))
    }),
  )
  use entries <- result.try(unique_pairs(entries))
  Ok(#(replica_id.new(replica), spec, observed.State(clock, entries)))
}

fn parse_checked_child(
  input: String,
  spec: CrdtSpec(a),
  decoder: Decoder(a),
) -> Result(Crdt(a), json.DecodeError) {
  use value <- result.try(from_json_with(input, decoder))
  case matches_spec(value, spec) {
    True -> Ok(value)
    False ->
      Error(
        invalid("matching recursive child schema", type_name(value), ["value"]),
      )
  }
}

@internal
pub fn or_from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(ORMap(a), json.DecodeError) {
  use _ <- result.try(check_envelope(input, "or_map", [3]))
  use #(replica, spec, state) <- result.try(
    parse_or_state(input, decoder, fn(input, spec) {
      parse_checked_child(input, spec, decoder)
    }),
  )
  use _ <- result.try(
    list.try_fold(dict.to_list(state.entries), Nil, fn(_, pair) {
      let #(key, entry) = pair
      case observed.active(entry, key), entry.value {
        True, None ->
          Error(
            invalid("value for active membership", "null", [
              "entries", key, "value",
            ]),
          )
        _, _ -> Ok(Nil)
      }
    }),
  )
  Ok(or_bind(ORMap(replica, spec, state), replica))
}

@internal
pub fn or_delta_from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(ORMapDelta(a), json.DecodeError) {
  use _ <- result.try(check_envelope(input, "or_map_delta", [2]))
  use #(replica, spec, state) <- result.try(
    parse_or_state(input, decoder, fn(input, spec) {
      use delta <- result.try(delta_from_json_with(input, decoder))
      case matches_delta(delta, spec) {
        True -> Ok(delta)
        False ->
          Error(
            invalid("matching recursive delta schema", "mismatch", ["value"]),
          )
      }
    }),
  )
  Ok(ORMapDelta(replica, spec, state))
}

fn provenance_json(provenance: lww.Provenance) -> Json {
  case provenance {
    lww.Modern(writer) ->
      json.object([
        #("kind", json.string("modern")),
        #("writer", json.string(replica_id.to_string(writer))),
      ])
    lww.Legacy(tie_key) ->
      json.object([
        #("kind", json.string("legacy")),
        #("tie_key", json.string(tie_key)),
      ])
  }
}

fn provenance_decoder() -> Decoder(lww.Provenance) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "modern" -> {
      use writer <- decode.field("writer", decode.string)
      decode.success(lww.Modern(replica_id.new(writer)))
    }
    "legacy" -> {
      use tie_key <- decode.field("tie_key", decode.string)
      decode.success(lww.Legacy(tie_key))
    }
    _ -> decode.failure(lww.Legacy(""), "modern or legacy provenance")
  }
}

@internal
pub fn lww_to_json_with(map: LWWMap(a), encode: fn(a) -> Json) -> Json {
  envelope(
    "lww_map",
    3,
    json.object([
      #("replica_id", json.string(replica_id.to_string(map.replica))),
      #("spec", embedded(spec_to_json_with(map.spec, encode))),
      #("pruned_timestamp", json.int(map.state.pruned_timestamp)),
      #(
        "entries",
        json.array(dict.to_list(map.state.entries), fn(pair) {
          let #(key, entry) = pair
          json.object([
            #("key", json.string(key)),
            #("timestamp", json.int(entry.timestamp)),
            #("provenance", provenance_json(entry.provenance)),
            #(
              "value",
              optional_json(entry.value, fn(child) {
                embedded(to_json_with(child, encode))
              }),
            ),
          ])
        }),
      ),
    ]),
  )
}

@internal
pub fn lww_from_json_with(
  input: String,
  decoder: Decoder(a),
) -> Result(LWWMap(a), json.DecodeError) {
  use _ <- result.try(check_envelope(input, "lww_map", [3]))
  let entry_decoder = {
    use key <- decode.field("key", decode.string)
    use timestamp <- decode.field("timestamp", decode.int)
    use provenance <- decode.field("provenance", provenance_decoder())
    use value <- decode.field("value", decode.optional(decode.string))
    decode.success(#(key, timestamp, provenance, value))
  }
  use #(replica, spec, pruned, entries) <- result.try(
    json.parse(input, {
      use state <- decode.field("state", {
        use replica <- decode.field("replica_id", decode.string)
        use spec <- decode.field("spec", decode.string)
        use pruned <- decode.field("pruned_timestamp", decode.int)
        use entries <- decode.field("entries", decode.list(entry_decoder))
        decode.success(#(replica, spec, pruned, entries))
      })
      decode.success(state)
    }),
  )
  use <- bool.guard(
    pruned < 0 || pruned > 9_007_199_254_740_991,
    Error(
      invalid("nonnegative prune floor", int.to_string(pruned), [
        "pruned_timestamp",
      ]),
    ),
  )
  use spec <- result.try(spec_from_json_with(spec, decoder))
  use entries <- result.try(
    list.try_map(entries, fn(entry) {
      let #(key, timestamp, provenance, value) = entry
      let modern = case provenance {
        lww.Modern(_) -> True
        lww.Legacy(_) -> False
      }
      use <- bool.guard(
        { modern && timestamp <= 0 }
          || timestamp > 9_007_199_254_740_991
          || timestamp < -9_007_199_254_740_991,
        Error(invalid("positive write timestamp", key, ["entries", key])),
      )
      use value <- result.try(
        parse_optional(value, parse_checked_child(_, spec, decoder))
        |> result.map_error(json_at_key(_, key)),
      )
      Ok(#(key, lww.Entry(value, timestamp, provenance)))
    }),
  )
  use entries <- result.try(unique_pairs(entries))
  Ok(LWWMap(replica_id.new(replica), spec, lww.State(entries, pruned)))
}

@internal
pub fn or_import_legacy(
  input: String,
  spec: CrdtSpec(a),
  decoder: Decoder(a),
  replica: ReplicaId,
) -> Result(ORMap(a), json.DecodeError) {
  use _ <- result.try(check_envelope(input, "or_map", [1, 2]))
  use #(old_spec, membership, entries, bounds) <- result.try(
    json.parse(input, {
      use state <- decode.field("state", {
        use spec <- decode.field("crdt_spec", decode.string)
        use membership <- decode.field("key_set", decode.string)
        use entries <- decode.field(
          "values",
          decode.list({
            use key <- decode.field("key", decode.string)
            use child <- decode.field("crdt", decode.string)
            decode.success(#(key, child))
          }),
        )
        use bounds <- decode.optional_field(
          "remove_bounds",
          dict.new(),
          decode.dict(decode.string, version_vector.decoder()),
        )
        decode.success(#(spec, membership, entries, bounds))
      })
      decode.success(state)
    }),
  )
  use <- bool.guard(
    old_spec != spec_name(spec),
    Error(invalid(spec_name(spec), old_spec, ["crdt_spec"])),
  )
  use membership <- result.try(legacy_or_set(membership, decode.string))
  use pairs <- result.try(
    list.try_map(entries, fn(pair) {
      use kind <- result.try(dispatch_tag(pair.1))
      use child <- result.try(case kind {
        "or_set" -> legacy_or_set(pair.1, decoder) |> result.map(CrdtOrSet)
        _ -> from_json_with(pair.1, decoder)
      })
      use <- bool.guard(
        !matches_spec(child, spec),
        Error(invalid("matching legacy child schema", kind, ["values", pair.0])),
      )
      Ok(#(pair.0, child))
    }),
  )
  use children <- result.try(unique_pairs(pairs))
  let keys =
    dict.keys(children)
    |> list.append(set.to_list(or_set.value(membership)))
    |> list.append(dict.keys(bounds))
    |> list.unique
  use entries <- result.try(
    list.try_map(keys, fn(key) {
      let child = case dict.get(children, key) {
        Ok(child) -> Some(child)
        Error(Nil) -> None
      }
      use <- bool.guard(
        or_set.contains(membership, key) && child == None,
        Error(invalid("active legacy child baseline", key, ["values"])),
      )
      // Split the old global membership context without inventing new live tags.
      let per_key = or_set.remove_where(membership, fn(other) { other != key })
      Ok(#(key, observed.Entry(observed.Initial, per_key, child)))
    }),
  )
  Ok(or_bind(
    ORMap(replica, spec, observed.State(0, dict.from_list(entries))),
    replica,
  ))
}

@internal
pub fn lww_import_legacy(
  input: String,
  spec: CrdtSpec(String),
  replica: ReplicaId,
) -> Result(LWWMap(String), json.DecodeError) {
  use _ <- result.try(check_envelope(input, "lww_map", [1, 2]))
  use <- bool.guard(
    spec_name(spec) != "lww_register",
    Error(invalid("explicit LwwRegisterSpec", spec_name(spec), ["spec"])),
  )
  use #(entries, pruned) <- result.try(
    json.parse(input, {
      use state <- decode.field("state", {
        use entries <- decode.field(
          "entries",
          decode.list({
            use key <- decode.field("key", decode.string)
            use value <- decode.field("value", decode.optional(decode.string))
            use timestamp <- decode.field("timestamp", decode.int)
            decode.success(#(key, value, timestamp))
          }),
        )
        use pruned <- decode.optional_field("pruned_timestamp", 0, decode.int)
        decode.success(#(entries, pruned))
      })
      decode.success(state)
    }),
  )
  use <- bool.guard(
    pruned < 0 || pruned > 9_007_199_254_740_991,
    Error(
      invalid("safe nonnegative prune floor", int.to_string(pruned), [
        "pruned_timestamp",
      ]),
    ),
  )
  use entries <- result.try(
    list.try_map(entries, fn(entry) {
      let #(key, value, timestamp) = entry
      use <- bool.guard(
        timestamp > 9_007_199_254_740_991 || timestamp < -9_007_199_254_740_991,
        Error(
          invalid("safe write timestamp", int.to_string(timestamp), [
            "entries",
            key,
          ]),
        ),
      )
      let #(child, tie_key) = case value {
        Some(value) -> #(
          Some(
            CrdtLwwRegister(lww_register.new(
              value,
              timestamp,
              scope(replica_id.new("legacy"), ["lww-import", key, value]),
            )),
          ),
          value,
        )
        None -> #(None, "")
      }
      Ok(#(key, lww.Entry(child, timestamp, lww.Legacy(tie_key))))
    }),
  )
  use entries <- result.try(unique_pairs(entries))
  Ok(LWWMap(replica, spec, lww.State(entries, pruned)))
}
