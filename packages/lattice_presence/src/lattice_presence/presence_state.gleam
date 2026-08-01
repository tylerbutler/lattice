//// Presence State - Pure CRDT for distributed presence tracking
////
//// A causal-context add-wins observed-remove set, inspired by
//// Phoenix.Tracker.State. This module is a pure data structure with no
//// actors or side effects.
////
//// Each node (replica) tracks its own presences authoritatively. State is
//// replicated by extracting deltas and merging them at remote replicas.
//// Conflicts are resolved causally: adds win over concurrent removes.
////
//// ## Example
////
//// ```gleam
//// import gleam/json
//// import lattice_presence/presence_state as state
////
//// let assert Ok(replica_a) = state.new_replica("node-a", "boot-123")
//// let assert Ok(replica_b) = state.new_replica("node-b", "boot-456")
//// let assert Ok(a) =
////   state.join(state.new(replica_a), "pid-1", "room:lobby", "alice", json.object([]))
//// let assert Ok(b) =
////   state.join(state.new(replica_b), "pid-2", "room:lobby", "bob", json.object([]))
//// let assert Ok(merged) = state.merge(a, b)
//// state.get_by_topic(merged, "room:lobby")
//// // -> [#("pid-1", "alice", _), #("pid-2", "bob", _)]
//// ```

import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/set.{type Set}
import gleam/string

const max_meta_depth = 64

/// A node identity that is unique for one process incarnation.
pub opaque type Replica {
  Replica(base: String, incarnation: String)
}

/// Why a replica identity could not be constructed.
pub type ReplicaError {
  EmptyReplicaBase
  EmptyIncarnation
}

/// Construct a replica identity.
///
/// Callers must provide a fresh incarnation token whenever a process using
/// the same stable base identity restarts.
pub fn new_replica(
  base: String,
  incarnation: String,
) -> Result(Replica, ReplicaError) {
  case string.trim(base), string.trim(incarnation) {
    "", _ -> Error(EmptyReplicaBase)
    _, "" -> Error(EmptyIncarnation)
    _, _ -> Ok(Replica(base: base, incarnation: incarnation))
  }
}

/// Return the stable part of a replica identity.
pub fn replica_base(replica: Replica) -> String {
  replica.base
}

/// Return the caller-provided incarnation token.
pub fn replica_incarnation(replica: Replica) -> String {
  replica.incarnation
}

/// Whether two replica identities have the same stable base.
pub fn same_base(a: Replica, b: Replica) -> Bool {
  a.base == b.base
}

/// Monotonically increasing counter per replica
pub type Clock =
  Int

/// A tag uniquely identifies when and where an entry was created
pub type Tag {
  Tag(replica: Replica, clock: Clock)
}

/// A tracked presence entry
pub type Entry {
  Entry(
    topic: String,
    key: String,
    /// Unique identifier for the tracked entity (e.g., socket ID, user ID)
    pid: String,
    /// Arbitrary metadata
    meta: json.Json,
  )
}

/// Replica status
pub type ReplicaStatus {
  Up
  Down
}

/// The CRDT state.
///
/// ## Why not reuse `lattice_core/version_vector` or `dot_context`?
///
/// The causal context here is the Phoenix.Tracker-style pair of
/// (`context`, `clouds`): a compacted vector-clock prefix plus per-replica
/// sets of observed-but-not-yet-contiguous clocks. `merge` and `compact`
/// rely on the gap-tracking that `clouds` provides — that is what makes
/// the add-wins observed-remove semantics work with a constant-size
/// header in the common case.
///
/// `lattice_core/version_vector` is a plain `Dict(ReplicaId, Int)` with
/// no gap tracking, and `lattice_core/dot_context` stores every observed
/// dot individually (no compaction). Neither captures the invariant
/// "every clock <= `context[replica]` has been observed AND any clock
/// listed in `clouds[replica]` has been observed", which `tag_is_in`,
/// `compact`, and `next_clock` all depend on. Adopting either type would
/// either lose information or change the on-the-wire shape; reuse is
/// possible only after extending lattice_core with a compacted variant,
/// which is intentionally deferred.
pub opaque type State {
  State(
    /// This node's full replica incarnation identity
    replica: Replica,
    /// Vector clock: replica -> latest compacted clock value
    context: Dict(Replica, Clock),
    /// Per-replica sets of observed-but-not-compacted clock values.
    /// Stays small in practice because `compact` runs at the end of every
    /// `merge` and folds any contiguous prefix into `context`.
    clouds: Dict(Replica, Set(Clock)),
    /// Tag -> Entry: all tracked presences
    values: Dict(Tag, Entry),
    /// Grow-only set of replica incarnations that can never contribute dots
    /// again. This is replicated so stale peers cannot resurrect pruned data.
    retired: Set(Replica),
    /// Replica status tracking.
    ///
    /// This field is **local-only** and intentionally **not** propagated
    /// during `merge`. Up/Down transitions originate from cluster-level
    /// signals (e.g. net-kernel monitors, gossip heartbeats) that the
    /// embedder observes locally; each node is responsible for calling
    /// `replica_up` / `replica_down` when it detects the corresponding
    /// event. Replicating `replicas` via CRDT merge would conflate the
    /// per-node liveness view with the globally-replicated presence set.
    replicas: Dict(Replica, ReplicaStatus),
  )
}

/// A diff representing changes between two states
pub type Diff {
  Diff(
    joins: Dict(String, List(#(String, String, json.Json))),
    leaves: Dict(String, List(#(String, String, json.Json))),
  )
}

/// A merge cannot safely combine divergent histories claiming one identity.
pub type MergeError {
  DivergentReplicaIdentity(Replica)
}

/// Why a replica lifecycle operation was rejected.
pub type LifecycleError {
  ReplicaNotDown(Replica)
  ReplicaRetired(Replica)
}

// ── Core operations ─────────────────────────────────────────────────

/// Create a new empty state for this replica
pub fn new(replica: Replica) -> State {
  State(
    replica: replica,
    context: dict.new(),
    clouds: dict.new(),
    values: dict.new(),
    retired: set.new(),
    replicas: dict.from_list([#(replica, Up)]),
  )
}

/// Add a tracked presence. Increments the local clock.
///
/// Returns `ReplicaRetired` if this state's local incarnation was retired by
/// replicated lifecycle metadata.
pub fn join(
  state state: State,
  pid pid: String,
  topic topic: String,
  key key: String,
  meta meta: json.Json,
) -> Result(State, LifecycleError) {
  use <- bool.guard(
    set.contains(state.retired, state.replica),
    Error(ReplicaRetired(state.replica)),
  )
  let clock = next_clock(state, state.replica)
  let tag = Tag(replica: state.replica, clock: clock)
  let entry = Entry(topic: topic, key: key, pid: pid, meta: meta)
  let cloud =
    result.unwrap(dict.get(state.clouds, state.replica), set.new())
    |> set.insert(clock)
  let new_clouds = dict.insert(state.clouds, state.replica, cloud)
  let new_values = dict.insert(state.values, tag, entry)
  Ok(compact(State(..state, clouds: new_clouds, values: new_values)))
}

/// Remove a specific presence by pid, topic, and key.
///
/// Only entries owned by this replica are removable — leaving a foreign
/// replica's entry would not be causally observed (this node's context
/// doesn't cover the foreign tag), so it would silently reappear on the
/// next merge. Foreign entries are filtered out at the source instead.
pub fn leave(
  state state: State,
  pid pid: String,
  topic topic: String,
  key key: String,
) -> State {
  let new_values =
    dict.filter(state.values, fn(tag, entry) {
      tag.replica != state.replica
      || entry.pid != pid
      || entry.topic != topic
      || entry.key != key
    })
  State(..state, values: new_values)
}

/// Remove all presences for a pid owned by this replica.
///
/// As with `leave`, only locally-owned entries are eligible — see that
/// function's docs for the rationale.
pub fn leave_by_pid(state: State, pid: String) -> State {
  let new_values =
    dict.filter(state.values, fn(tag, entry) {
      tag.replica != state.replica || entry.pid != pid
    })
  State(..state, values: new_values)
}

// ── Query operations ────────────────────────────────────────────────

/// Collect entries from non-down replicas that satisfy `predicate`.
fn visible_entries(state: State, predicate: fn(Entry) -> Bool) -> List(Entry) {
  dict.fold(state.values, [], fn(acc, tag, entry) {
    case is_replica_up(state, tag.replica) && predicate(entry) {
      True -> [entry, ..acc]
      False -> acc
    }
  })
}

/// List all online presences across all topics (from non-down replicas)
pub fn online_list(state: State) -> List(#(String, String, String, json.Json)) {
  visible_entries(state, fn(_) { True })
  |> list.map(fn(entry) { #(entry.pid, entry.topic, entry.key, entry.meta) })
}

/// Get all presences for a topic (from non-down replicas)
pub fn get_by_topic(
  state: State,
  topic: String,
) -> List(#(String, String, json.Json)) {
  visible_entries(state, fn(entry) { entry.topic == topic })
  |> list.map(fn(entry) { #(entry.pid, entry.key, entry.meta) })
}

/// Get presences for a specific key within a topic
pub fn get_by_key(
  state state: State,
  topic topic: String,
  key key: String,
) -> List(#(String, json.Json)) {
  visible_entries(state, fn(entry) { entry.topic == topic && entry.key == key })
  |> list.map(fn(entry) { #(entry.pid, entry.meta) })
}

// ── Merge ───────────────────────────────────────────────────────────

/// Merge remote state into local state.
///
/// `replicas` (per-node liveness view) is **not** merged because it is
/// local-only view state, not part of the replicated CRDT payload.
pub fn merge(local: State, remote: State) -> Result(State, MergeError) {
  use #(merged, _) <- result.try(merge_with_diff(local, remote))
  Ok(merged)
}

/// Merge remote state into local state and return a diff of what changed.
pub fn merge_with_diff(
  local: State,
  remote: State,
) -> Result(#(State, Diff), MergeError) {
  use _ <- result.try(reject_conflicting_tags(local.values, remote.values))
  let visible_before = visible_values(local)
  let retired = set.union(local.retired, remote.retired)
  let local_values =
    dict.filter(local.values, fn(tag, _) { !set.contains(retired, tag.replica) })
  let remote_values =
    dict.filter(remote.values, fn(tag, _) {
      !set.contains(retired, tag.replica)
    })
  // 1. Find new entries from remote (tags we haven't seen)
  let joins =
    dict.to_list(remote_values)
    |> list.filter(fn(kv) {
      let #(tag, _) = kv
      !tag_is_in(local.context, local.clouds, tag)
    })

  // 2. Find entries we should remove (in remote's causal context but not in
  //    remote's values)
  let removes =
    dict.to_list(local_values)
    |> list.filter(fn(kv) {
      let #(tag, _) = kv
      tag_is_in(remote.context, remote.clouds, tag)
      && !dict.has_key(remote_values, tag)
    })

  // 3. Apply changes
  let new_values =
    list.fold(removes, local_values, fn(vals, kv) {
      let #(tag, _) = kv
      dict.delete(vals, tag)
    })
  let new_values =
    list.fold(joins, new_values, fn(vals, kv) {
      let #(tag, entry) = kv
      dict.insert(vals, tag, entry)
    })

  // 4. Advance context: take max of local and remote for each replica
  let new_context =
    merge_contexts(local.context, remote.context)
    |> dict.filter(fn(replica, _) { !set.contains(retired, replica) })

  // 5. Merge clouds
  let new_clouds =
    merge_clouds(local.clouds, remote.clouds)
    |> dict.filter(fn(replica, _) { !set.contains(retired, replica) })

  let new_state =
    State(
      ..local,
      context: new_context,
      clouds: new_clouds,
      values: new_values,
      retired: retired,
      replicas: dict.filter(local.replicas, fn(replica, _) {
        !set.contains(retired, replica)
      }),
    )
    |> compact

  // Lifecycle visibility is local view state, so report only entries whose
  // visibility actually changed. In particular, retain merged values owned by
  // Down replicas without emitting joins; replica_up reports those later.
  let visible_after = visible_values(new_state)
  let joined =
    dict.filter(visible_after, fn(tag, _) { !dict.has_key(visible_before, tag) })
  let left =
    dict.filter(visible_before, fn(tag, _) { !dict.has_key(visible_after, tag) })
  let diff =
    Diff(
      joins: entries_to_topic_diff(dict.values(joined)),
      leaves: entries_to_topic_diff(dict.values(left)),
    )

  Ok(#(new_state, diff))
}

fn visible_values(state: State) -> Dict(Tag, Entry) {
  dict.filter(state.values, fn(tag, _) { is_replica_up(state, tag.replica) })
}

fn reject_conflicting_tags(
  local: Dict(Tag, Entry),
  remote: Dict(Tag, Entry),
) -> Result(Nil, MergeError) {
  reject_conflicting_tag_list(dict.to_list(local), remote)
}

fn reject_conflicting_tag_list(
  entries: List(#(Tag, Entry)),
  remote: Dict(Tag, Entry),
) -> Result(Nil, MergeError) {
  case entries {
    [] -> Ok(Nil)
    [#(tag, entry), ..rest] ->
      case dict.get(remote, tag) {
        Ok(other) if other != entry ->
          Error(DivergentReplicaIdentity(tag.replica))
        _ -> reject_conflicting_tag_list(rest, remote)
      }
  }
}

/// Check if a tag is "in" a causal context (either compacted or in clouds)
fn tag_is_in(
  context: Dict(Replica, Clock),
  clouds: Dict(Replica, Set(Clock)),
  tag: Tag,
) -> Bool {
  case dict.get(context, tag.replica) {
    Ok(clock) if clock >= tag.clock -> True
    _ -> {
      case dict.get(clouds, tag.replica) {
        Ok(cloud) -> set.contains(cloud, tag.clock)
        Error(Nil) -> False
      }
    }
  }
}

/// Merge two vector clocks (take max per replica)
fn merge_contexts(
  a: Dict(Replica, Clock),
  b: Dict(Replica, Clock),
) -> Dict(Replica, Clock) {
  dict.combine(a, b, int.max)
}

/// Merge cloud sets
fn merge_clouds(
  a: Dict(Replica, Set(Clock)),
  b: Dict(Replica, Set(Clock)),
) -> Dict(Replica, Set(Clock)) {
  dict.combine(a, b, fn(sa, sb) { set.union(sa, sb) })
}

/// Compact clouds into context where possible
///
/// If context[replica] + 1 is in the cloud, advance context and remove from
/// cloud. Repeat until no more compaction possible.
pub fn compact(state: State) -> State {
  let #(new_context, new_clouds) =
    dict.fold(
      state.clouds,
      #(state.context, state.clouds),
      fn(acc, replica, cloud) {
        let #(ctx, clouds) = acc
        let base = case dict.get(ctx, replica) {
          Ok(c) -> c
          Error(Nil) -> 0
        }
        let #(new_base, remaining) = compact_cloud(base, cloud)
        let new_ctx = case new_base > base {
          True -> dict.insert(ctx, replica, new_base)
          False -> ctx
        }
        let new_clouds = case set.size(remaining) {
          0 -> dict.delete(clouds, replica)
          _ -> dict.insert(clouds, replica, remaining)
        }
        #(new_ctx, new_clouds)
      },
    )

  State(..state, context: new_context, clouds: new_clouds)
}

/// Compact a single cloud: advance base clock through contiguous values
fn compact_cloud(base: Clock, cloud: Set(Clock)) -> #(Clock, Set(Clock)) {
  let uncovered = set.filter(cloud, fn(clock) { clock > base })
  use <- bool.guard(!set.contains(uncovered, base + 1), #(base, uncovered))
  compact_cloud(base + 1, set.delete(uncovered, base + 1))
}

/// Group entries by topic for diff reporting
fn entries_to_topic_diff(
  entries: List(Entry),
) -> Dict(String, List(#(String, String, json.Json))) {
  list.fold(entries, dict.new(), fn(acc, entry) {
    let existing = case dict.get(acc, entry.topic) {
      Ok(l) -> l
      Error(Nil) -> []
    }
    dict.insert(acc, entry.topic, [
      #(entry.key, entry.pid, entry.meta),
      ..existing
    ])
  })
}

// ── Extract (delta) ─────────────────────────────────────────────────

/// Extract state for sending to a remote replica.
///
/// Currently returns the full local state. Remote's `merge` handles
/// deduplication of entries it already has, and absence of an entry
/// combined with coverage in `context` represents an observed removal.
///
/// A future delta-extraction variant will use the remote's known
/// `context` to filter to only the tags the remote hasn't seen — that
/// will be exposed as a separate function rather than retrofitted onto
/// this one.
pub fn extract_full_state(state: State) -> State {
  state
}

// ── Introspection ───────────────────────────────────────────────────

/// Get the replica identity this state was created with.
pub fn replica(state: State) -> Replica {
  state.replica
}

/// Get the compacted vector clock.
pub fn compacted_clocks(state: State) -> Dict(Replica, Clock) {
  state.context
}

/// Return the number of entries retained by the CRDT state.
pub fn entry_count(state: State) -> Int {
  dict.size(state.values)
}

/// Return the number of uncompacted cloud entries retained by the state.
pub fn cloud_count(state: State) -> Int {
  dict.size(state.clouds)
}

@internal
pub fn internal_values(state: State) -> Dict(Tag, Entry) {
  state.values
}

@internal
pub fn internal_clouds(state: State) -> Dict(Replica, Set(Clock)) {
  state.clouds
}

/// Return the replicated grow-only retired-incarnation set.
pub fn retired_replicas(state: State) -> Set(Replica) {
  state.retired
}

// ── Replica lifecycle ────────────────────────────────────────────────

/// Collect all entries currently owned by `replica`.
fn entries_for_replica(state: State, replica: Replica) -> List(Entry) {
  dict.fold(state.values, [], fn(acc, tag, entry) {
    case tag.replica == replica {
      True -> [entry, ..acc]
      False -> acc
    }
  })
}

/// Mark a replica as down. Returns entries that are now invisible (leaves).
///
/// Idempotent: if the replica is already `Down`, the state is unchanged
/// and the returned diff is empty.
pub fn replica_down(state: State, replica: Replica) -> #(State, Diff) {
  case dict.get(state.replicas, replica) {
    Ok(Down) -> #(state, Diff(joins: dict.new(), leaves: dict.new()))
    _ -> {
      let new_replicas = dict.insert(state.replicas, replica, Down)
      let new_state = State(..state, replicas: new_replicas)
      let hidden = entries_for_replica(state, replica)
      let diff = Diff(joins: dict.new(), leaves: entries_to_topic_diff(hidden))
      #(new_state, diff)
    }
  }
}

/// Mark a replica as up. Returns entries that are now visible again (joins).
///
/// Idempotent: if the replica is already `Up` (or unknown — unknown
/// replicas are assumed up), the state is unchanged and the returned
/// diff is empty. Retired identities are rejected.
pub fn replica_up(
  state: State,
  replica: Replica,
) -> Result(#(State, Diff), LifecycleError) {
  use <- bool.guard(
    set.contains(state.retired, replica),
    Error(ReplicaRetired(replica)),
  )
  case dict.get(state.replicas, replica) {
    Ok(Down) -> {
      let new_replicas = dict.insert(state.replicas, replica, Up)
      let new_state = State(..state, replicas: new_replicas)
      let restored = entries_for_replica(state, replica)
      let diff =
        Diff(joins: entries_to_topic_diff(restored), leaves: dict.new())
      Ok(#(new_state, diff))
    }
    Ok(Up) -> Ok(#(state, Diff(joins: dict.new(), leaves: dict.new())))
    Error(Nil) -> {
      // First contact: record as Up but emit no diff (it was already
      // treated as up by `is_replica_up`).
      let new_replicas = dict.insert(state.replicas, replica, Up)
      Ok(#(
        State(..state, replicas: new_replicas),
        Diff(joins: dict.new(), leaves: dict.new()),
      ))
    }
  }
}

/// Permanently prune a down replica and replicate its retired identity.
pub fn remove_down_replica(
  state: State,
  replica: Replica,
) -> Result(#(State, Diff), LifecycleError) {
  use <- bool.guard(
    dict.get(state.replicas, replica) != Ok(Down),
    Error(ReplicaNotDown(replica)),
  )
  Ok(prune_replica(state, replica))
}

fn prune_replica(state: State, replica: Replica) -> #(State, Diff) {
  let removed = case is_replica_up(state, replica) {
    True -> entries_for_replica(state, replica)
    False -> []
  }
  let new_values =
    dict.filter(state.values, fn(tag, _) { tag.replica != replica })
  let new_context = dict.delete(state.context, replica)
  let new_clouds = dict.delete(state.clouds, replica)
  let new_replicas = dict.delete(state.replicas, replica)
  #(
    State(
      ..state,
      values: new_values,
      context: new_context,
      clouds: new_clouds,
      retired: set.insert(state.retired, replica),
      replicas: new_replicas,
    ),
    Diff(joins: dict.new(), leaves: entries_to_topic_diff(removed)),
  )
}

/// Replace older known incarnations of the same base with `new_replica`.
///
/// Every other incarnation sharing the base is pruned and tombstoned. The
/// state's local identity is never changed; restarted processes should create
/// a fresh state with `new_replica` before merging and superseding old state.
pub fn supersede(
  state: State,
  new_replica: Replica,
) -> Result(#(State, Diff), LifecycleError) {
  use <- bool.guard(
    set.contains(state.retired, new_replica),
    Error(ReplicaRetired(new_replica)),
  )
  let known =
    dict.keys(state.context)
    |> list.append(dict.keys(state.clouds))
    |> list.append(dict.keys(state.replicas))
    |> list.append(dict.keys(state.values) |> list.map(fn(tag) { tag.replica }))
    |> set.from_list
    |> set.to_list
    |> list.filter(fn(replica) {
      replica != new_replica && same_base(replica, new_replica)
    })
  let #(pruned, leaves) =
    list.fold(known, #(state, []), fn(acc, old_replica) {
      let #(current, removed) = acc
      let #(next, diff) = prune_replica(current, old_replica)
      #(next, list.append(dict.to_list(diff.leaves), removed))
    })
  let leaves =
    list.fold(leaves, dict.new(), fn(acc, pair) {
      let #(topic, entries) = pair
      let existing = result.unwrap(dict.get(acc, topic), [])
      dict.insert(acc, topic, list.append(entries, existing))
    })
  let new_replicas = case dict.get(pruned.replicas, new_replica) {
    Error(Nil) -> dict.insert(pruned.replicas, new_replica, Up)
    Ok(_) -> pruned.replicas
  }
  Ok(#(
    State(..pruned, replicas: new_replicas),
    Diff(joins: dict.new(), leaves: leaves),
  ))
}

// ── Serialization ───────────────────────────────────────────────────

/// Encode replicated state as JSON.
///
/// Replica-keyed maps are arrays of records so structured identities never
/// depend on delimiter parsing. Local liveness is intentionally omitted.
pub fn to_json(state: State) -> json.Json {
  json.object([
    #("replica", encode_replica(state.replica)),
    #("context", encode_context(state.context)),
    #("clouds", encode_clouds(state.clouds)),
    #("values", encode_values(state.values)),
    #("retired", encode_retired(state.retired)),
  ])
}

/// Encode replicated state as a JSON string.
pub fn to_json_string(state: State) -> String {
  to_json(state) |> json.to_string
}

/// Decode a JSON string into presence state.
pub fn from_json(json_string: String) -> Result(State, json.DecodeError) {
  json.parse(from: json_string, using: decoder())
}

/// Decode presence state, for use inside larger protocol decoders.
pub fn decoder() -> decode.Decoder(State) {
  use replica <- decode.field("replica", replica_decoder())
  use context <- decode.field("context", context_decoder())
  use clouds <- decode.field("clouds", clouds_decoder())
  use values <- decode.field("values", values_decoder())
  use retired <- decode.field("retired", retired_decoder())
  let replicas = case set.contains(retired, replica) {
    True -> dict.new()
    False -> dict.from_list([#(replica, Up)])
  }
  validate_decoded_state(State(
    replica: replica,
    context: context,
    clouds: clouds,
    values: values,
    retired: retired,
    replicas: replicas,
  ))
}

fn encode_retired(retired: Set(Replica)) -> json.Json {
  retired
  |> set.to_list
  |> json.array(encode_replica)
}

fn retired_decoder() -> decode.Decoder(Set(Replica)) {
  decode.list(replica_decoder())
  |> decode.then(fn(replicas) {
    let retired = set.from_list(replicas)
    case set.size(retired) == list.length(replicas) {
      True -> decode.success(retired)
      False -> decode.failure(retired, "unique retired replicas")
    }
  })
}

fn validate_decoded_state(state: State) -> decode.Decoder(State) {
  let invalid_context =
    dict.to_list(state.context)
    |> list.any(fn(pair) {
      let #(replica, clock) = pair
      clock <= 0 || set.contains(state.retired, replica)
    })
  let invalid_cloud =
    dict.to_list(state.clouds)
    |> list.any(fn(pair) {
      let #(replica, clocks) = pair
      let base = result.unwrap(dict.get(state.context, replica), 0)
      set.contains(state.retired, replica)
      || set.size(clocks) == 0
      || list.any(set.to_list(clocks), fn(clock) { clock <= base })
      || set.contains(clocks, base + 1)
    })
  let invalid_value =
    dict.to_list(state.values)
    |> list.any(fn(pair) {
      let #(tag, _) = pair
      set.contains(state.retired, tag.replica)
      || !tag_is_in(state.context, state.clouds, tag)
    })
  case invalid_context || invalid_cloud || invalid_value {
    True -> decode.failure(state, "canonical causally-covered state")
    False -> decode.success(state)
  }
}

fn encode_replica(replica: Replica) -> json.Json {
  json.object([
    #("base", json.string(replica.base)),
    #("incarnation", json.string(replica.incarnation)),
  ])
}

fn replica_decoder() -> decode.Decoder(Replica) {
  use base <- decode.field("base", decode.string)
  use incarnation <- decode.field("incarnation", decode.string)
  case new_replica(base, incarnation) {
    Ok(replica) -> decode.success(replica)
    Error(EmptyReplicaBase) ->
      decode.failure(
        Replica(base: base, incarnation: incarnation),
        "non-empty replica base and incarnation",
      )
    Error(EmptyIncarnation) ->
      decode.failure(
        Replica(base: base, incarnation: incarnation),
        "non-empty replica base and incarnation",
      )
  }
}

fn encode_context(context: Dict(Replica, Clock)) -> json.Json {
  context
  |> dict.to_list
  |> list.map(fn(pair) {
    json.object([
      #("replica", encode_replica(pair.0)),
      #("clock", json.int(pair.1)),
    ])
  })
  |> json.preprocessed_array
}

fn context_decoder() -> decode.Decoder(Dict(Replica, Clock)) {
  decode.list({
    use replica <- decode.field("replica", replica_decoder())
    use clock <- decode.field("clock", decode.int)
    case clock > 0 {
      True -> decode.success(#(replica, clock))
      False -> decode.failure(#(replica, clock), "positive context clock")
    }
  })
  |> decode.then(unique_dict_decoder)
}

fn encode_clouds(clouds: Dict(Replica, Set(Clock))) -> json.Json {
  clouds
  |> dict.to_list
  |> list.map(fn(pair) {
    json.object([
      #("replica", encode_replica(pair.0)),
      #("clocks", json.array(set.to_list(pair.1), json.int)),
    ])
  })
  |> json.preprocessed_array
}

fn clouds_decoder() -> decode.Decoder(Dict(Replica, Set(Clock))) {
  decode.list({
    use replica <- decode.field("replica", replica_decoder())
    use clocks <- decode.field("clocks", decode.list(decode.int))
    let unique = set.from_list(clocks)
    case
      clocks != []
      && list.all(clocks, fn(clock) { clock > 0 })
      && set.size(unique) == list.length(clocks)
    {
      True -> decode.success(#(replica, unique))
      False -> decode.failure(#(replica, set.new()), "positive cloud clocks")
    }
  })
  |> decode.then(unique_dict_decoder)
}

fn unique_dict_decoder(pairs: List(#(a, b))) -> decode.Decoder(Dict(a, b)) {
  let decoded = dict.from_list(pairs)
  case dict.size(decoded) == list.length(pairs) {
    True -> decode.success(decoded)
    False -> decode.failure(decoded, "unique replica records")
  }
}

fn encode_tag(tag: Tag) -> json.Json {
  json.object([
    #("replica", encode_replica(tag.replica)),
    #("clock", json.int(tag.clock)),
  ])
}

fn tag_decoder() -> decode.Decoder(Tag) {
  use replica <- decode.field("replica", replica_decoder())
  use clock <- decode.field("clock", decode.int)
  let tag = Tag(replica: replica, clock: clock)
  case clock > 0 {
    True -> decode.success(tag)
    False -> decode.failure(tag, "positive tag clock")
  }
}

fn encode_entry(entry: Entry) -> json.Json {
  json.object([
    #("topic", json.string(entry.topic)),
    #("key", json.string(entry.key)),
    #("pid", json.string(entry.pid)),
    #("meta", entry.meta),
  ])
}

fn entry_decoder() -> decode.Decoder(Entry) {
  use topic <- decode.field("topic", decode.string)
  use key <- decode.field("key", decode.string)
  use pid <- decode.field("pid", decode.string)
  use meta <- decode.field("meta", json_value_decoder())
  decode.success(Entry(topic: topic, key: key, pid: pid, meta: meta))
}

fn encode_values(values: Dict(Tag, Entry)) -> json.Json {
  values
  |> dict.to_list
  |> list.map(fn(pair) {
    json.object([
      #("tag", encode_tag(pair.0)),
      #("entry", encode_entry(pair.1)),
    ])
  })
  |> json.preprocessed_array
}

fn values_decoder() -> decode.Decoder(Dict(Tag, Entry)) {
  decode.list({
    use tag <- decode.field("tag", tag_decoder())
    use entry <- decode.field("entry", entry_decoder())
    decode.success(#(tag, entry))
  })
  |> decode.then(fn(pairs) {
    let decoded = dict.from_list(pairs)
    case dict.size(decoded) == list.length(pairs) {
      True -> decode.success(decoded)
      False -> decode.failure(decoded, "unique presence tags")
    }
  })
}

fn json_value_decoder() -> decode.Decoder(json.Json) {
  json_value_decoder_at(0)
}

fn json_value_decoder_at(depth: Int) -> decode.Decoder(json.Json) {
  case depth > max_meta_depth {
    True -> decode.failure(json.null(), "metadata depth within limit")
    False -> json_value_decoder_within_limit(depth)
  }
}

fn json_value_decoder_within_limit(depth: Int) -> decode.Decoder(json.Json) {
  decode.one_of(decode.string |> decode.map(json.string), [
    decode.int |> decode.map(json.int),
    decode.float |> decode.map(json.float),
    decode.bool |> decode.map(json.bool),
    decode.optional(decode.string)
      |> decode.then(fn(value) {
        case value {
          option.None -> decode.success(json.null())
          option.Some(_) -> decode.failure(json.null(), "null")
        }
      }),
    decode.list(decode.dynamic)
      |> decode.then(fn(items) { json_value_list(items, [], depth + 1) }),
    decode.dict(decode.string, decode.dynamic)
      |> decode.then(fn(fields) {
        json_value_dict(dict.to_list(fields), [], depth + 1)
      }),
  ])
}

fn json_value_list(
  items: List(decode.Dynamic),
  acc: List(json.Json),
  depth: Int,
) -> decode.Decoder(json.Json) {
  case items {
    [] -> decode.success(json.preprocessed_array(list.reverse(acc)))
    [item, ..rest] ->
      case decode.run(item, json_value_decoder_at(depth)) {
        Ok(value) -> json_value_list(rest, [value, ..acc], depth)
        // Decode boundary: replace nested detail with a metadata-specific error.
        // nolint: thrown_away_error
        Error(_) -> decode.failure(json.null(), "valid JSON value in array")
      }
  }
}

fn json_value_dict(
  fields: List(#(String, decode.Dynamic)),
  acc: List(#(String, json.Json)),
  depth: Int,
) -> decode.Decoder(json.Json) {
  case fields {
    [] -> decode.success(json.object(list.reverse(acc)))
    [#(key, dynamic), ..rest] ->
      case decode.run(dynamic, json_value_decoder_at(depth)) {
        Ok(value) -> json_value_dict(rest, [#(key, value), ..acc], depth)
        // Decode boundary: replace nested detail with a metadata-specific error.
        // nolint: thrown_away_error
        Error(_) -> decode.failure(json.null(), "valid JSON value in object")
      }
  }
}

// ── Internal helpers ────────────────────────────────────────────────

fn next_clock(state: State, replica: Replica) -> Clock {
  // Read max of both compacted context and uncompacted cloud values so
  // we never reuse a clock still pending in the cloud. The set.fold is
  // O(cloud size), which stays small because compact() runs after every
  // merge — tracking the max incrementally would optimize a non-hot path.
  let ctx_clock = case dict.get(state.context, replica) {
    Ok(c) -> c
    Error(Nil) -> 0
  }
  let cloud_max = case dict.get(state.clouds, replica) {
    Ok(cloud) -> set.fold(cloud, 0, int.max)
    Error(Nil) -> 0
  }
  int.max(ctx_clock, cloud_max) + 1
}

fn is_replica_up(state: State, replica: Replica) -> Bool {
  use <- bool.guard(set.contains(state.retired, replica), False)
  case dict.get(state.replicas, replica) {
    Ok(Up) -> True
    Ok(Down) -> False
    // Unknown replicas assumed up (first contact)
    Error(Nil) -> True
  }
}
