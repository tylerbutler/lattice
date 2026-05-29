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
//// let a = state.new("node-a")
////   |> state.join("pid-1", "room:lobby", "alice", json.object([]))
//// let b = state.new("node-b")
////   |> state.join("pid-2", "room:lobby", "bob", json.object([]))
//// let merged = state.merge(a, b)
//// state.get_by_topic(merged, "room:lobby")
//// // -> [#("pid-1", "alice", _), #("pid-2", "bob", _)]
//// ```

import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/set.{type Set}

/// Unique identifier for a node in the cluster
pub type Replica =
  String

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
    /// This node's replica name
    replica: Replica,
    /// Vector clock: replica -> latest compacted clock value
    context: Dict(Replica, Clock),
    /// Per-replica sets of observed-but-not-compacted clock values.
    /// Stays small in practice because `compact` runs at the end of every
    /// `merge` and folds any contiguous prefix into `context`.
    clouds: Dict(Replica, Set(Clock)),
    /// Tag -> Entry: all tracked presences
    values: Dict(Tag, Entry),
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

// ── Core operations ─────────────────────────────────────────────────

/// Create a new empty state for this replica
pub fn new(replica: Replica) -> State {
  State(
    replica: replica,
    context: dict.new(),
    clouds: dict.new(),
    values: dict.new(),
    replicas: dict.from_list([#(replica, Up)]),
  )
}

/// Add a tracked presence. Increments the local clock.
pub fn join(
  state: State,
  pid: String,
  topic: String,
  key: String,
  meta: json.Json,
) -> State {
  let clock = next_clock(state, state.replica)
  let tag = Tag(replica: state.replica, clock: clock)
  let entry = Entry(topic: topic, key: key, pid: pid, meta: meta)
  let new_context = dict.insert(state.context, state.replica, clock)
  let new_values = dict.insert(state.values, tag, entry)
  State(..state, context: new_context, values: new_values)
}

/// Remove a specific presence by pid, topic, and key.
///
/// Only entries owned by this replica are removable — leaving a foreign
/// replica's entry would not be causally observed (this node's context
/// doesn't cover the foreign tag), so it would silently reappear on the
/// next merge. Foreign entries are filtered out at the source instead.
pub fn leave(state: State, pid: String, topic: String, key: String) -> State {
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
  state: State,
  topic: String,
  key: String,
) -> List(#(String, json.Json)) {
  visible_entries(state, fn(entry) { entry.topic == topic && entry.key == key })
  |> list.map(fn(entry) { #(entry.pid, entry.meta) })
}

// ── Merge ───────────────────────────────────────────────────────────

/// Merge remote state into local state.
///
/// `replicas` (per-node liveness view) is **not** merged because it is
/// local-only view state, not part of the replicated CRDT payload.
pub fn merge(local: State, remote: State) -> State {
  let #(merged, _) = merge_with_diff(local, remote)
  merged
}

/// Merge remote state into local state and return a diff of what changed.
pub fn merge_with_diff(local: State, remote: State) -> #(State, Diff) {
  // The `joins` and `removes` lists are materialized (rather than folded
  // straight into the new values dict) because they are reused below to
  // build the `Diff`. Doing it as a single dict.fold would save one
  // allocation but require a second pass for the diff.

  // 1. Find new entries from remote (tags we haven't seen)
  let joins =
    dict.to_list(remote.values)
    |> list.filter(fn(kv) {
      let #(tag, _) = kv
      !tag_is_in(local.context, local.clouds, tag)
    })

  // 2. Find entries we should remove (in remote's causal context but not in
  //    remote's values)
  let removes =
    dict.to_list(local.values)
    |> list.filter(fn(kv) {
      let #(tag, _) = kv
      tag.replica != local.replica
      && tag_is_in(remote.context, remote.clouds, tag)
      && !dict.has_key(remote.values, tag)
    })

  // 3. Apply changes
  let new_values =
    list.fold(removes, local.values, fn(vals, kv) {
      let #(tag, _) = kv
      dict.delete(vals, tag)
    })
  let new_values =
    list.fold(joins, new_values, fn(vals, kv) {
      let #(tag, entry) = kv
      dict.insert(vals, tag, entry)
    })

  // 4. Advance context: take max of local and remote for each replica
  let new_context = merge_contexts(local.context, remote.context)

  // 5. Merge clouds
  let new_clouds = merge_clouds(local.clouds, remote.clouds)

  // 6. Build diff
  let join_diff = entries_to_topic_diff(list.map(joins, fn(kv) { kv.1 }))
  let leave_diff = entries_to_topic_diff(list.map(removes, fn(kv) { kv.1 }))
  let diff = Diff(joins: join_diff, leaves: leave_diff)

  let new_state =
    State(..local, context: new_context, clouds: new_clouds, values: new_values)

  #(compact(new_state), diff)
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
  case set.contains(cloud, base + 1) {
    True -> compact_cloud(base + 1, set.delete(cloud, base + 1))
    False -> #(base, cloud)
  }
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

/// Get the current vector clock
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
/// diff is empty.
pub fn replica_up(state: State, replica: Replica) -> #(State, Diff) {
  case dict.get(state.replicas, replica) {
    Ok(Down) -> {
      let new_replicas = dict.insert(state.replicas, replica, Up)
      let new_state = State(..state, replicas: new_replicas)
      let restored = entries_for_replica(state, replica)
      let diff =
        Diff(joins: entries_to_topic_diff(restored), leaves: dict.new())
      #(new_state, diff)
    }
    Ok(Up) -> #(state, Diff(joins: dict.new(), leaves: dict.new()))
    Error(Nil) -> {
      // First contact: record as Up but emit no diff (it was already
      // treated as up by `is_replica_up`).
      let new_replicas = dict.insert(state.replicas, replica, Up)
      #(
        State(..state, replicas: new_replicas),
        Diff(joins: dict.new(), leaves: dict.new()),
      )
    }
  }
}

/// Permanently remove all entries and context for a downed replica
pub fn remove_down_replica(state: State, replica: Replica) -> State {
  let new_values =
    dict.filter(state.values, fn(tag, _) { tag.replica != replica })
  let new_context = dict.delete(state.context, replica)
  let new_clouds = dict.delete(state.clouds, replica)
  let new_replicas = dict.delete(state.replicas, replica)
  State(
    ..state,
    values: new_values,
    context: new_context,
    clouds: new_clouds,
    replicas: new_replicas,
  )
}

@internal
pub fn replicated_parts(
  state: State,
) -> #(
  Replica,
  Dict(Replica, Clock),
  Dict(Replica, Set(Clock)),
  Dict(Tag, Entry),
) {
  #(state.replica, state.context, state.clouds, state.values)
}

@internal
pub fn from_replicated_parts(
  replica: Replica,
  context: Dict(Replica, Clock),
  clouds: Dict(Replica, Set(Clock)),
  values: Dict(Tag, Entry),
) -> State {
  State(
    replica: replica,
    context: context,
    clouds: clouds,
    values: values,
    replicas: dict.from_list([#(replica, Up)]),
  )
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
  case dict.get(state.replicas, replica) {
    Ok(Up) -> True
    Ok(Down) -> False
    // Unknown replicas assumed up (first contact)
    Error(Nil) -> True
  }
}
