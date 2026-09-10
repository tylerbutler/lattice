//// Presence State - Pure CRDT for distributed presence tracking
////
//// A causal-context add-wins observed-remove set, inspired by
//// Phoenix.Tracker.State. This module is a pure data structure with no
//// actors or side effects.
////
//// Each node (replica) tracks its own presences authoritatively. State is
//// replicated by extracting deltas and merging them at remote replicas.
//// Conflicts are resolved causally: adds win over concurrent removes.
//// Replica identities must be unique per process incarnation. Use
//// `new_incarnation` when a stable node name can restart.
////
//// ## Example
////
//// ```gleam
//// import gleam/json
//// import lattice_presence/presence_state as state
////
//// let a = state.new_incarnation("node-a")
////   |> state.join("pid-1", "room:lobby", "alice", json.object([]))
//// let b = state.new_incarnation("node-b")
////   |> state.join("pid-2", "room:lobby", "bob", json.object([]))
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
import youid/uuid

const incarnation_prefix = "lattice-presence:v1:"

const max_meta_depth = 64

/// Unique identifier for a running node incarnation in the cluster
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

/// Error returned when replicated data conflicts with the local replica identity.
///
/// This includes divergent states claiming the same name and unseen local-owned
/// causal history echoed by another replica. It indicates a stale state after a
/// restart or multiple live nodes configured with the same replica name. Assign
/// every live node a unique identity and discard stale state before retrying.
pub type MergeError {
  SameReplica(replica: Replica)
}

/// Error returned when superseding would retire this state's local writer.
///
/// Create a fresh local state after a restart instead of changing the identity
/// of an existing writer. The error includes the local and selected identities.
///
/// ## Examples
///
/// ```gleam
/// let local = new_incarnation("node-a")
/// let current = new_incarnation("node-a")
/// let assert Error(CannotSupersedeLocalReplica(local_replica, current_replica)) =
///   supersede(local, replica(current))
/// ```
pub type SupersedeError {
  CannotSupersedeLocalReplica(local_replica: Replica, current_replica: Replica)
}

// ── Core operations ─────────────────────────────────────────────────

/// Create a new empty state for a globally unique replica incarnation.
///
/// Reusing `replica` after a process or node restart is unsafe because peers
/// may retain causal history for the previous incarnation. Use
/// `new_incarnation` when the same stable replica name can restart.
///
/// ## Examples
///
/// ```gleam
/// let state = new("node-a-019d449c-2c82-71bb-b4bf-6505df7ad7c2")
/// replica(state)
/// // -> "node-a-019d449c-2c82-71bb-b4bf-6505df7ad7c2"
/// ```
pub fn new(replica: Replica) -> State {
  State(
    replica: replica,
    context: dict.new(),
    clouds: dict.new(),
    values: dict.new(),
    replicas: dict.from_list([#(replica, Up)]),
  )
}

/// Create a new empty state with a fresh incarnation of a stable replica name.
///
/// The generated replica identity is safe to use in the existing string-valued
/// replication and JSON formats. Use `base_replica` to recover `base`.
///
/// ## Examples
///
/// ```gleam
/// let state = new_incarnation("node-a")
/// base_replica(replica(state))
/// // -> "node-a"
/// ```
pub fn new_incarnation(base: String) -> State {
  let token = uuid.v4() |> uuid.to_base64
  new(incarnation_prefix <> token <> ":" <> base)
}

/// Add a tracked presence. Increments the local clock.
pub fn join(
  state state: State,
  pid pid: String,
  topic topic: String,
  key key: String,
  meta meta: json.Json,
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
///
/// Returns `Error(SameReplica(...))` when the states claim the same replica
/// name but their replicated data differs, or when remote carries local-owned
/// tags or causal history that local has not observed, even via another peer.
/// History for removed entries is checked too. Echoes of already-known local
/// tags remain valid, and identical same-replica states are an idempotent no-op.
/// This check does not replace the requirement for unique incarnation identities.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(merged) = merge(new("node-a"), new("node-b"))
/// ```
pub fn merge(local: State, remote: State) -> Result(State, MergeError) {
  case merge_with_diff(local, remote) {
    Ok(#(merged, _)) -> Ok(merged)
    Error(error) -> Error(error)
  }
}

/// Merge remote state into local state and return a diff of what changed.
///
/// Returns `Error(SameReplica(...))` under the same conditions as `merge`.
/// Values owned by an earlier incarnation of the local state's stable replica
/// are not admitted. Their causal context is still merged so syncing the
/// restarted state back to peers removes any cached entries from that earlier
/// incarnation.
///
/// ## Examples
///
/// ```gleam
/// let assert Ok(#(merged, diff)) =
///   merge_with_diff(new("node-a"), new("node-b"))
/// ```
pub fn merge_with_diff(
  local: State,
  remote: State,
) -> Result(#(State, Diff), MergeError) {
  use <- bool.guard(
    local.replica == remote.replica,
    case replicated_data_equal(local, remote) {
      True -> Ok(#(local, Diff(joins: dict.new(), leaves: dict.new())))
      False -> Error(SameReplica(replica: local.replica))
    },
  )
  use <- bool.guard(
    remote_has_unseen_local_history(local, remote),
    Error(SameReplica(replica: local.replica)),
  )
  Ok(merge_distinct_replicas(local, remote))
}

fn remote_has_unseen_local_history(local: State, remote: State) -> Bool {
  // The sole writer of this identity cannot learn new local-owned events
  // from gossip. Check retained history as well as active tags.
  let local_clock = result.unwrap(dict.get(local.context, local.replica), 0)
  let local_cloud =
    result.unwrap(dict.get(local.clouds, local.replica), set.new())
  // Cover the entire incoming prefix, not just its endpoint or maximum.
  // Local clouds may extend that prefix without having been compacted yet.
  let #(local_clock, _) = compact_cloud(local_clock, local_cloud)
  let remote_clock = result.unwrap(dict.get(remote.context, local.replica), 0)
  use <- bool.guard(remote_clock > local_clock, True)

  let remote_cloud =
    result.unwrap(dict.get(remote.clouds, local.replica), set.new())
  let unseen_cloud =
    set.fold(remote_cloud, False, fn(unseen, clock) {
      unseen
      || !tag_is_in(
        local.context,
        local.clouds,
        Tag(replica: local.replica, clock: clock),
      )
    })
  unseen_cloud
  || dict.fold(remote.values, False, fn(unseen, tag, _) {
    unseen
    || {
      tag.replica == local.replica
      && !tag_is_in(local.context, local.clouds, tag)
    }
  })
}

fn merge_distinct_replicas(local: State, remote: State) -> #(State, Diff) {
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
      && {
        tag.replica == local.replica || !same_base(tag.replica, local.replica)
      }
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

fn replicated_data_equal(a: State, b: State) -> Bool {
  a.context == b.context && a.clouds == b.clouds && a.values == b.values
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
/// Remove cloud clocks already covered by context, then advance context through
/// the remaining contiguous prefix.
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
        let cloud = set.filter(cloud, fn(clock) { clock > base })
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
  use <- bool.guard(!set.contains(cloud, base + 1), #(base, cloud))
  compact_cloud(base + 1, set.delete(cloud, base + 1))
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

/// Get the replica name this state was created with.
pub fn replica(state: State) -> Replica {
  state.replica
}

/// Get the stable replica name from an incarnation identity.
///
/// Replica values not created by `new_incarnation` are returned unchanged.
///
/// ## Examples
///
/// ```gleam
/// let state = new_incarnation("node-a")
/// base_replica(replica(state))
/// // -> "node-a"
/// ```
pub fn base_replica(replica: Replica) -> String {
  case replica {
    "lattice-presence:v1:" <> encoded ->
      case string.split_once(encoded, on: ":") {
        Ok(#(token, base)) ->
          case uuid.from_base64(token) {
            Ok(_) -> base
            Error(Nil) -> replica
          }
        Error(Nil) -> replica
      }
    _ -> replica
  }
}

/// Return whether two replica identities share the same stable name.
///
/// ## Examples
///
/// ```gleam
/// let first = new_incarnation("node-a")
/// let second = new_incarnation("node-a")
/// same_base(replica(first), replica(second))
/// // -> True
/// ```
pub fn same_base(first: Replica, second: Replica) -> Bool {
  base_replica(first) == base_replica(second)
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

/// Permanently remove all entries for a downed replica.
///
/// The replica's causal high-water mark is retained so entries held by a
/// lagging peer cannot be re-admitted later. If the replica is not marked
/// `Down`, the state is returned unchanged.
pub fn remove_down_replica(state: State, replica: Replica) -> State {
  use <- bool.guard(dict.get(state.replicas, replica) != Ok(Down), state)

  let context_clock = result.unwrap(dict.get(state.context, replica), 0)
  let cloud_clock =
    dict.get(state.clouds, replica)
    |> result.map(fn(cloud) { set.fold(cloud, 0, int.max) })
    |> result.unwrap(0)
  let high_water = int.max(context_clock, cloud_clock)
  let new_context = case high_water > 0 {
    True -> dict.insert(state.context, replica, high_water)
    False -> state.context
  }

  State(
    ..state,
    values: dict.filter(state.values, fn(tag, _) { tag.replica != replica }),
    context: new_context,
    clouds: dict.delete(state.clouds, replica),
    replicas: dict.delete(state.replicas, replica),
  )
}

/// Retire locally known alternatives to a caller-selected replica identity.
///
/// The caller must choose the authoritative `current_replica`, for example
/// through cluster membership. An inbound sync alone does not establish that
/// authority; UUIDs and message arrival order do not rank incarnations.
///
/// Returns `Error(CannotSupersedeLocalReplica(...))` before any work if the
/// selected identity differs from the local writer but shares its base. This
/// applies even when the local writer has no entries, is Down, or has no
/// liveness entry. Selecting the local identity itself or an identity of
/// another base is valid.
///
/// On `Ok(#(state, diff))`, other known identities with the same base have been
/// marked Down and pruned using `remove_down_replica`. Leaves are combined by
/// topic as `#(key, pid, meta)` tuples, preserving duplicates without an ordering
/// guarantee. Joins are empty, and already-Down identities emit no new leaves.
/// The selected identity and unrelated bases are unchanged: the selected
/// identity need not be known and is neither inserted nor marked Up.
///
/// Pruning retains the existing context/cloud high-water marks, not clocks
/// from uncovered value tags. Covered stale tags cannot return, but unseen
/// higher tags can: this is not a permanent ban on an identity. Repeating the
/// call without intervening changes leaves the state unchanged with no diff.
///
/// ## Examples
///
/// ```gleam
/// let old = new_incarnation("node-a")
///   |> join("pid-1", "lobby", "alice", json.null())
/// let current = new_incarnation("node-a")
/// let assert Ok(peer) = merge(new("observer"), old)
/// let assert Ok(#(peer, diff)) = supersede(peer, replica(current))
/// dict.get(diff.leaves, "lobby")
/// // -> Ok([#("alice", "pid-1", json.null())])
/// ```
pub fn supersede(
  state: State,
  current_replica: Replica,
) -> Result(#(State, Diff), SupersedeError) {
  use <- bool.guard(
    state.replica != current_replica
      && same_base(state.replica, current_replica),
    Error(CannotSupersedeLocalReplica(
      local_replica: state.replica,
      current_replica: current_replica,
    )),
  )

  let known_replicas =
    list.flatten([
      [state.replica],
      dict.keys(state.replicas),
      dict.keys(state.context),
      dict.keys(state.clouds),
    ])
    |> set.from_list
  let known_replicas =
    dict.fold(state.values, known_replicas, fn(known, tag, _) {
      set.insert(known, tag.replica)
    })

  let #(state, leaves) =
    set.fold(known_replicas, #(state, dict.new()), fn(acc, known) {
      let #(state, leaves) = acc
      use <- bool.guard(
        known == current_replica || !same_base(known, current_replica),
        acc,
      )
      let #(state, diff) = replica_down(state, known)
      #(
        remove_down_replica(state, known),
        dict.combine(leaves, diff.leaves, list.append),
      )
    })
  Ok(#(state, Diff(joins: dict.new(), leaves: leaves)))
}

// -- JSON serialization --

/// Encode replicated state to JSON, omitting local replica liveness.
///
/// ## Examples
///
/// ```gleam
/// new("node-a") |> to_json |> json.to_string
/// // -> "{\"replica\":\"node-a\",\"context\":{},\"clouds\":{},\"values\":[]}"
/// ```
pub fn to_json(state: State) -> json.Json {
  json.object([
    #("replica", json.string(state.replica)),
    #("context", encode_context(state.context)),
    #("clouds", encode_clouds(state.clouds)),
    #("values", encode_values(state.values)),
  ])
}

/// Encode replicated state to a JSON string.
///
/// ## Examples
///
/// ```gleam
/// new("node-a") |> to_json_string
/// // -> "{\"replica\":\"node-a\",\"context\":{},\"clouds\":{},\"values\":[]}"
/// ```
pub fn to_json_string(state: State) -> String {
  to_json(state) |> json.to_string
}

/// Decode a JSON string into a state with only its own replica marked `Up`.
///
/// The serialized replica identity is retained. Merge a remote snapshot into
/// the local state before making local edits.
///
/// ## Examples
///
/// ```gleam
/// new("node-a") |> to_json_string |> from_json
/// // -> Ok(new("node-a"))
/// ```
pub fn from_json(json_string: String) -> Result(State, json.DecodeError) {
  json.parse(from: json_string, using: decoder())
}

/// Decode replicated state, including when embedded in a sync envelope.
///
/// Local replica liveness is reset, as with `from_json`.
///
/// ## Examples
///
/// ```gleam
/// let envelope_decoder = {
///   use state <- decode.field("state", decoder())
///   decode.success(state)
/// }
/// let payload = json.object([#("state", to_json(new("node-a")))])
/// json.parse(json.to_string(payload), envelope_decoder)
/// // -> Ok(new("node-a"))
/// ```
pub fn decoder() -> decode.Decoder(State) {
  use replica <- decode.field("replica", decode.string)
  use context <- decode.field("context", context_decoder())
  use clouds <- decode.field("clouds", clouds_decoder())
  use values <- decode.field("values", values_decoder())
  decode.success(State(
    replica: replica,
    context: context,
    clouds: clouds,
    values: values,
    replicas: dict.from_list([#(replica, Up)]),
  ))
}

fn encode_context(context: Dict(String, Int)) -> json.Json {
  context
  |> dict.to_list
  |> list.map(fn(kv) { #(kv.0, json.int(kv.1)) })
  |> json.object
}

fn context_decoder() -> decode.Decoder(Dict(String, Int)) {
  decode.dict(decode.string, decode.int)
  |> decode.then(fn(context) {
    case all_dict_values(context, fn(clock) { clock >= 0 }) {
      True -> decode.success(context)
      False -> decode.failure(context, "non-negative context clocks")
    }
  })
}

fn encode_clouds(clouds: Dict(String, Set(Int))) -> json.Json {
  clouds
  |> dict.to_list
  |> list.map(fn(kv) { #(kv.0, json.array(set.to_list(kv.1), json.int)) })
  |> json.object
}

fn clouds_decoder() -> decode.Decoder(Dict(String, Set(Int))) {
  decode.dict(decode.string, decode.list(decode.int))
  |> decode.then(fn(d) {
    case all_cloud_clocks_positive(d) {
      True ->
        decode.success(
          dict.map_values(d, fn(_, clocks) { set.from_list(clocks) }),
        )
      False -> decode.failure(dict.new(), "positive cloud clocks")
    }
  })
}

fn encode_tag(tag: Tag) -> json.Json {
  json.object([
    #("replica", json.string(tag.replica)),
    #("clock", json.int(tag.clock)),
  ])
}

fn tag_decoder() -> decode.Decoder(Tag) {
  use replica <- decode.field("replica", decode.string)
  use clock <- decode.field("clock", decode.int)
  case clock > 0 {
    True -> decode.success(Tag(replica: replica, clock: clock))
    False ->
      decode.failure(Tag(replica: replica, clock: clock), "positive tag clock")
  }
}

fn encode_entry(entry: Entry) -> json.Json {
  json.object([
    #("topic", json.string(entry.topic)),
    #("key", json.string(entry.key)),
    #("pid", json.string(entry.pid)),
    // `meta` is embedded as a raw JSON value (not a stringified blob) so
    // payloads are smaller and self-describing on the wire. Decoding uses
    // `json_value_decoder` to reconstruct the `json.Json` opaque value.
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
  |> list.map(fn(kv) {
    json.object([
      #("tag", encode_tag(kv.0)),
      #("entry", encode_entry(kv.1)),
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
  |> decode.map(dict.from_list)
}

fn all_dict_values(
  values: Dict(String, Int),
  predicate: fn(Int) -> Bool,
) -> Bool {
  dict.fold(values, True, fn(valid, _, value) { valid && predicate(value) })
}

fn all_cloud_clocks_positive(values: Dict(String, List(Int))) -> Bool {
  dict.fold(values, True, fn(valid, _, clocks) {
    valid && list.all(clocks, fn(clock) { clock > 0 })
  })
}

/// Decoder that reconstructs a json.Json value from parsed JSON. Uses
/// standard decoder combinators instead of BEAM-specific dynamic.classify
/// so the same code works on both the Erlang and JavaScript targets.
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
      |> decode.then(fn(opt) {
        case opt {
          option.None -> decode.success(json.null())
          option.Some(_) -> decode.failure(json.null(), "null")
        }
      }),
    decode.list(decode.dynamic)
      |> decode.then(fn(items) { json_value_list(items, [], depth + 1) }),
    decode.dict(decode.string, decode.dynamic)
      |> decode.then(fn(d) {
        let pairs = dict.to_list(d)
        json_value_dict(pairs, [], depth + 1)
      }),
  ])
}

// `json_value_list` and `json_value_dict` share the same recursive
// structure but produce different `json.Json` shapes (array vs. object)
// and consume different element types. Unifying them through a higher-
// order helper obscures the decoder shape without saving real code, so
// they are kept as two parallel functions.
fn json_value_list(
  items: List(decode.Dynamic),
  acc: List(json.Json),
  depth: Int,
) -> decode.Decoder(json.Json) {
  case items {
    [] -> decode.success(json.preprocessed_array(list.reverse(acc)))
    [item, ..rest] ->
      case decode.run(item, json_value_decoder_at(depth)) {
        Ok(val) -> json_value_list(rest, [val, ..acc], depth)
        // Decode boundary: per-element decode errors are replaced with a
        // single domain-specific decoder failure.
        // nolint: thrown_away_error
        Error(_) -> decode.failure(json.null(), "valid JSON value in array")
      }
  }
}

fn json_value_dict(
  pairs: List(#(String, decode.Dynamic)),
  acc: List(#(String, json.Json)),
  depth: Int,
) -> decode.Decoder(json.Json) {
  case pairs {
    [] -> decode.success(json.object(list.reverse(acc)))
    [#(key, value), ..rest] ->
      case decode.run(value, json_value_decoder_at(depth)) {
        Ok(val) -> json_value_dict(rest, [#(key, val), ..acc], depth)
        // Decode boundary: per-field decode errors are replaced with a
        // single domain-specific decoder failure.
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
  case dict.get(state.replicas, replica) {
    Ok(Up) -> True
    Ok(Down) -> False
    // Unknown replicas assumed up (first contact)
    Error(Nil) -> True
  }
}
