import gleam/dict
import gleam/json
import gleam/list
import gleam/result
import gleam/set
import lattice_presence/presence_state as state
import startest/expect

fn join_ok(
  state_: state.State,
  pid: String,
  topic: String,
  key: String,
  meta: json.Json,
) -> state.State {
  let assert Ok(joined) = state.join(state_, pid, topic, key, meta)
  joined
}

fn r(base: String) -> state.Replica {
  let assert Ok(replica) = state.new_replica(base, "test-incarnation")
  replica
}

fn merge_ok(a: state.State, b: state.State) -> state.State {
  let assert Ok(merged) = state.merge(a, b)
  merged
}

fn merge_diff_ok(a: state.State, b: state.State) -> #(state.State, state.Diff) {
  let assert Ok(merged) = state.merge_with_diff(a, b)
  merged
}

// ── new ──────────────────────────────────────────────────────────────

pub fn new_creates_empty_state_test() {
  let s = state.new(r("node1"))
  state.online_list(s) |> expect.to_equal([])
  state.replica(s) |> expect.to_equal(r("node1"))
}

pub fn replica_identity_validation_and_accessors_test() {
  state.new_replica("", "incarnation")
  |> expect.to_equal(Error(state.EmptyReplicaBase))
  state.new_replica("node", " ")
  |> expect.to_equal(Error(state.EmptyIncarnation))

  let assert Ok(replica) = state.new_replica("node", "boot-1")
  state.replica_base(replica) |> expect.to_equal("node")
  state.replica_incarnation(replica) |> expect.to_equal("boot-1")
}

// ── join ─────────────────────────────────────────────────────────────

pub fn join_makes_user_online_test() {
  let s = state.new(r("node1"))
  let s =
    join_ok(
      s,
      "pid1",
      "room:lobby",
      "user:alice",
      json.object([
        #("status", json.string("online")),
      ]),
    )

  let entries = state.get_by_topic(s, "room:lobby")
  list.length(entries) |> expect.to_equal(1)
  let assert [#(_pid, "user:alice", _meta)] = entries
  Nil
}

pub fn join_increments_clock_test() {
  let s = state.new(r("node1"))
  let s = join_ok(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = join_ok(s, "pid2", "room:lobby", "bob", json.object([]))

  let entries = state.get_by_topic(s, "room:lobby")
  list.length(entries) |> expect.to_equal(2)
}

pub fn join_multiple_topics_test() {
  let s = state.new(r("node1"))
  let s = join_ok(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = join_ok(s, "pid1", "room:private", "alice", json.object([]))

  state.get_by_topic(s, "room:lobby") |> list.length |> expect.to_equal(1)
  state.get_by_topic(s, "room:private") |> list.length |> expect.to_equal(1)
}

// ── leave ────────────────────────────────────────────────────────────

pub fn leave_removes_user_test() {
  let s = state.new(r("node1"))
  let s = join_ok(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = state.leave(s, "pid1", "room:lobby", "alice")

  state.get_by_topic(s, "room:lobby") |> expect.to_equal([])
}

pub fn leave_nonexistent_is_noop_test() {
  let s = state.new(r("node1"))
  let s = state.leave(s, "pid1", "room:lobby", "alice")
  state.online_list(s) |> expect.to_equal([])
}

pub fn leave_all_by_pid_test() {
  let s = state.new(r("node1"))
  let s = join_ok(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = join_ok(s, "pid1", "room:private", "alice", json.object([]))
  let s = join_ok(s, "pid2", "room:lobby", "bob", json.object([]))

  let s = state.leave_by_pid(s, "pid1")

  // pid1's entries gone, pid2's entry remains
  state.online_list(s) |> list.length |> expect.to_equal(1)
  state.get_by_topic(s, "room:private") |> expect.to_equal([])
}

// ── merge ────────────────────────────────────────────────────────────

pub fn merge_adds_remote_entries_test() {
  // Node A has alice, Node B has bob
  let a = state.new(r("node_a"))
  let a = join_ok(a, "pid1", "room:lobby", "alice", json.object([]))

  let b = state.new(r("node_b"))
  let b = join_ok(b, "pid2", "room:lobby", "bob", json.object([]))

  // Merge B into A
  let merged = merge_ok(a, b)

  // A should now see both alice and bob
  state.get_by_topic(merged, "room:lobby") |> list.length |> expect.to_equal(2)
}

pub fn merge_is_idempotent_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "pid1", "room:lobby", "alice", json.object([]))

  let b = state.new(r("node_b"))
  let b = join_ok(b, "pid2", "room:lobby", "bob", json.object([]))

  // Merge twice should not duplicate
  let merged = merge_ok(a, b)
  let merged2 = merge_ok(merged, b)

  state.get_by_topic(merged2, "room:lobby") |> list.length |> expect.to_equal(2)
}

pub fn merge_observes_remote_removals_test() {
  // Node A and B both know about alice
  let a = state.new(r("node_a"))
  let a = join_ok(a, "pid1", "room:lobby", "alice", json.object([]))

  // B merges A's state to learn about alice
  let b = state.new(r("node_b"))
  let b = merge_ok(b, a)

  // A removes alice locally
  let a = state.leave(a, "pid1", "room:lobby", "alice")

  // B merges A again — should observe the removal
  let merged = merge_ok(b, a)
  state.get_by_topic(merged, "room:lobby") |> expect.to_equal([])
}

pub fn merge_add_wins_over_concurrent_remove_test() {
  // A has alice, B learns about alice
  let a = state.new(r("node_a"))
  let a =
    join_ok(
      a,
      "pid1",
      "room:lobby",
      "alice",
      json.object([
        #("v", json.int(1)),
      ]),
    )

  let b = state.new(r("node_b"))
  let b = merge_ok(b, a)

  // Concurrently: A removes alice, B re-adds alice
  let a = state.leave(a, "pid1", "room:lobby", "alice")
  let b =
    join_ok(
      b,
      "pid1",
      "room:lobby",
      "alice",
      json.object([
        #("v", json.int(2)),
      ]),
    )

  // When A merges B, alice should be present (add wins)
  let merged = merge_ok(a, b)
  state.get_by_topic(merged, "room:lobby") |> list.length |> expect.to_equal(1)
}

pub fn merge_returns_diff_with_joins_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))
  let b = join_ok(b, "pid1", "room:lobby", "bob", json.object([]))

  let #(_merged, diff) = merge_diff_ok(a, b)

  // Diff should show bob as a join
  case dict.get(diff.joins, "room:lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

pub fn merge_returns_diff_with_leaves_test() {
  // A knows about bob (from previous merge with B)
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))
  let b = join_ok(b, "pid1", "room:lobby", "bob", json.object([]))

  let a = merge_ok(a, b)

  // B removes bob
  let b = state.leave(b, "pid1", "room:lobby", "bob")

  // Merge again — diff should show bob as a leave
  let #(_merged, diff) = merge_diff_ok(a, b)
  case dict.get(diff.leaves, "room:lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

pub fn merge_three_nodes_test() {
  // Three nodes, each with one user
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:lobby", "alice", json.object([]))

  let b = state.new(r("node_b"))
  let b = join_ok(b, "p2", "room:lobby", "bob", json.object([]))

  let c = state.new(r("node_c"))
  let c = join_ok(c, "p3", "room:lobby", "carol", json.object([]))

  // Merge all into A via two hops
  let a = merge_ok(a, b)
  let a = merge_ok(a, c)

  state.get_by_topic(a, "room:lobby") |> list.length |> expect.to_equal(3)
}

// ── Phoenix-inspired merge tests ────────────────────────────────────
// Ported from Phoenix.Tracker.StateTest

/// Phoenix test: "users from other servers merge" — full lifecycle
/// merge, idempotent re-merge, observe remove, new join after remove,
/// and metadata update via leave+join
pub fn phoenix_full_merge_lifecycle_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))

  let a = join_ok(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = join_ok(b, "pid_bob", "lobby", "bob", json.object([]))

  // Merge B into A — bob appears as join
  let #(a, diff) = merge_diff_ok(a, b)
  state.online_list(a) |> list.length |> expect.to_equal(2)
  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }

  // Merge B into A again — idempotent, no new events
  let #(a2, diff2) = merge_diff_ok(a, b)
  dict.size(diff2.joins) |> expect.to_equal(0)
  dict.size(diff2.leaves) |> expect.to_equal(0)
  state.online_list(a2) |> list.length |> expect.to_equal(2)

  // Merge A into B — alice appears as join
  let #(b, diff3) = merge_diff_ok(b, a)
  case dict.get(diff3.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  // Re-merge is idempotent
  let #(_b2, diff4) = merge_diff_ok(b, a)
  dict.size(diff4.joins) |> expect.to_equal(0)

  // A removes alice, B observes via merge
  let a = state.leave(a, "pid_alice", "lobby", "alice")
  let #(b, diff5) = merge_diff_ok(b, a)
  case dict.get(diff5.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  state.online_list(b) |> list.length |> expect.to_equal(1)

  // B adds carol
  let b = join_ok(b, "pid_carol", "lobby", "carol", json.object([]))
  state.online_list(b) |> list.length |> expect.to_equal(2)

  // A merges B — gets carol
  let #(a, diff6) = merge_diff_ok(a, b)
  case dict.get(diff6.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }

  // After full sync both nodes agree
  state.online_list(a)
  |> list.length
  |> expect.to_equal(state.online_list(b) |> list.length)
}

/// Phoenix test: metadata update via leave+join (leave_join pattern)
pub fn phoenix_update_via_leave_join_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))

  let b =
    join_ok(
      b,
      "pid_carol",
      "lobby",
      "carol",
      json.object([
        #("status", json.string("online")),
      ]),
    )

  // Sync A with B
  let a = merge_ok(a, b)

  // B updates carol by leaving then rejoining with new meta
  let b = state.leave(b, "pid_carol", "lobby", "carol")
  let b =
    join_ok(
      b,
      "pid_carol",
      "lobby",
      "carol",
      json.object([
        #("status", json.string("away")),
      ]),
    )

  // Merge into A — should see a leave and a join for carol
  let #(_a, diff) = merge_diff_ok(a, b)
  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  case dict.get(diff.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

/// Phoenix test: "basic netsplit" — replica down during mutations,
/// merge is no-op while down, replica_up restores
pub fn phoenix_netsplit_with_mutations_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))

  let a = join_ok(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = join_ok(b, "pid_bob", "lobby", "bob", json.object([]))

  // Sync
  let a = merge_ok(a, b)
  state.online_list(a) |> list.length |> expect.to_equal(2)

  // A does some mutations
  let a = join_ok(a, "pid_carol", "lobby", "carol", json.object([]))
  let a = state.leave(a, "pid_alice", "lobby", "alice")
  let a = join_ok(a, "pid_david", "lobby", "david", json.object([]))

  // Netsplit: A marks B as down
  let #(a, down_diff) = state.replica_down(a, r("node_b"))
  // bob should show as a leave
  case dict.get(down_diff.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  // Only carol and david visible (alice left, bob is down)
  state.online_list(a) |> list.length |> expect.to_equal(2)

  // Merge while down is no-op for visibility
  let #(a, noop_diff) = merge_diff_ok(a, b)
  dict.size(noop_diff.joins) |> expect.to_equal(0)
  state.online_list(a) |> list.length |> expect.to_equal(2)

  // Heal: A marks B as up — bob reappears
  let assert Ok(#(a, up_diff)) = state.replica_up(a, r("node_b"))
  case dict.get(up_diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  // carol, david, bob
  state.online_list(a) |> list.length |> expect.to_equal(3)
}

/// Phoenix test: "joins are observed via other node" (3-node with netsplit)
pub fn phoenix_joins_via_intermediate_node_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))
  let c = state.new(r("node_c"))

  let a = join_ok(a, "pid_alice", "lobby", "alice", json.object([]))

  // C learns about alice from A
  let c = merge_ok(c, a)
  state.get_by_topic(c, "lobby") |> list.length |> expect.to_equal(1)

  // Netsplit between A and C
  let #(a, _) = state.replica_down(a, r("node_c"))
  let #(c, _) = state.replica_down(c, r("node_a"))

  // A adds bob
  let a = join_ok(a, "pid_bob", "lobby", "bob", json.object([]))

  // B merges A's full state — gets both alice and bob
  let b = merge_ok(b, a)
  state.get_by_topic(b, "lobby") |> list.length |> expect.to_equal(2)

  // C retains bob, but both entries are owned by locally Down A and remain
  // hidden until replica_up.
  let #(c, diff) = merge_diff_ok(c, b)
  dict.size(diff.joins) |> expect.to_equal(0)
  state.get_by_topic(c, "lobby") |> expect.to_equal([])

  let assert Ok(#(c, up_diff)) = state.replica_up(c, r("node_a"))
  dict.get(up_diff.joins, "lobby")
  |> result.map(list.length)
  |> expect.to_equal(Ok(2))
  state.get_by_topic(c, "lobby") |> list.length |> expect.to_equal(2)
}

/// Phoenix test: "removes are observed via other node" (3-node with netsplit)
/// Tests that removes propagate through an intermediate node even during netsplit
pub fn phoenix_removes_via_intermediate_node_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))
  let c = state.new(r("node_c"))

  let a = join_ok(a, "pid_alice", "lobby", "alice", json.object([]))

  // All nodes learn about alice
  let b = merge_ok(b, a)
  let c = merge_ok(c, a)

  // B adds bob
  let b = join_ok(b, "pid_bob", "lobby", "bob", json.object([]))

  // A and C learn about bob
  let a = merge_ok(a, b)
  let c = merge_ok(c, b)
  state.get_by_topic(c, "lobby") |> list.length |> expect.to_equal(2)

  // Netsplit between A and C (B can talk to both)
  let #(a, _) = state.replica_down(a, r("node_c"))
  let #(c, _) = state.replica_down(c, r("node_a"))

  // A removes alice
  let a = state.leave(a, "pid_alice", "lobby", "alice")

  // B observes remove via A
  let b = merge_ok(b, a)

  // C observes the remove via B, but alice was already hidden when A went
  // Down, so no duplicate leave is emitted.
  let #(c, diff) = merge_diff_ok(c, b)
  dict.size(diff.leaves) |> expect.to_equal(0)
  state.get_by_topic(c, "lobby") |> list.length |> expect.to_equal(1)
}

// ── extract (delta) ──────────────────────────────────────────────────

pub fn extract_produces_delta_for_new_replica_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:lobby", "alice", json.object([]))
  let a = join_ok(a, "p2", "room:lobby", "bob", json.object([]))

  // Extract what a fresh replica needs from A (everything)
  let delta = state.extract_full_state(a)

  // Delta should contain both entries
  dict.size(state.internal_values(delta)) |> expect.to_equal(2)
}

pub fn extract_returns_full_state_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:lobby", "alice", json.object([]))

  // Extract returns full state — merge handles deduplication
  let extracted = state.extract_full_state(a)
  dict.size(state.internal_values(extracted)) |> expect.to_equal(1)
}

pub fn extract_includes_all_entries_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:lobby", "alice", json.object([]))
  let a = join_ok(a, "p2", "room:lobby", "bob", json.object([]))

  // A adds a third entry
  let a = join_ok(a, "p3", "room:lobby", "carol", json.object([]))

  // Extract returns all 3 entries (full state)
  let extracted = state.extract_full_state(a)
  dict.size(state.internal_values(extracted)) |> expect.to_equal(3)
}

/// Phoenix test: extract-based merge workflow (mirrors Phoenix's merge(a, extract(b, ...)))
pub fn phoenix_extract_merge_workflow_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))

  let a = join_ok(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = join_ok(b, "pid_bob", "lobby", "bob", json.object([]))

  // Merge using extract (like Phoenix does)
  let delta_b = state.extract_full_state(b)
  let #(a, diff) = merge_diff_ok(a, delta_b)
  state.online_list(a) |> list.length |> expect.to_equal(2)
  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }

  // Second extract-merge is idempotent
  let delta_b2 = state.extract_full_state(b)
  let #(a2, diff2) = merge_diff_ok(a, delta_b2)
  dict.size(diff2.joins) |> expect.to_equal(0)
  dict.size(diff2.leaves) |> expect.to_equal(0)
  state.online_list(a2) |> list.length |> expect.to_equal(2)
}

/// Phoenix test: extract-based remove observation
pub fn phoenix_extract_observes_remove_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))

  let a = join_ok(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = join_ok(b, "pid_bob", "lobby", "bob", json.object([]))

  // Sync both directions
  let a = merge_ok(a, state.extract_full_state(b))
  let b = merge_ok(b, state.extract_full_state(a))

  // A removes alice
  let a = state.leave(a, "pid_alice", "lobby", "alice")

  // B merges A's extract — should observe alice's removal
  let #(b, diff) = merge_diff_ok(b, state.extract_full_state(a))
  case dict.get(diff.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  state.online_list(b) |> list.length |> expect.to_equal(1)
}

/// Phoenix test: "get_by_topic" with multiple replicas and down/up filtering
pub fn phoenix_get_by_topic_with_replica_status_test() {
  let s1 = state.new(r("node1"))
  let s2 = state.new(r("node2"))
  let s3 = state.new(r("node3"))

  // Each node adds entries
  let s1 = join_ok(s1, "pid1", "topic", "key1", json.object([]))
  let s1 = join_ok(s1, "pid1", "topic", "key2", json.object([]))
  let s2 = join_ok(s2, "pid2", "topic", "user2", json.object([]))
  let s3 = join_ok(s3, "pid3", "topic", "user3", json.object([]))

  // s1 sees only local entries
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(2)

  // Merge all into s1
  let s1 = merge_ok(s1, s2)
  let s1 = merge_ok(s1, s3)

  // All 4 entries visible
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(4)

  // One replica down — 3 entries visible
  let #(s1, _) = state.replica_down(s1, r("node2"))
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(3)

  // Two replicas down — 2 entries visible (only local)
  let #(s1, _) = state.replica_down(s1, r("node3"))
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(2)

  // Different topic returns empty
  state.get_by_topic(s1, "another:topic") |> expect.to_equal([])
}

/// Phoenix test: "get_by_key" with multiple pids for same key
pub fn phoenix_get_by_key_test() {
  let s = state.new(r("node1"))

  state.get_by_key(s, "topic", "key1") |> expect.to_equal([])

  let s =
    join_ok(
      s,
      "pid1",
      "topic",
      "key1",
      json.object([
        #("device", json.string("browser")),
      ]),
    )
  let s =
    join_ok(
      s,
      "pid2",
      "topic",
      "key1",
      json.object([
        #("device", json.string("ios")),
      ]),
    )
  let s =
    join_ok(
      s,
      "pid2",
      "topic",
      "key2",
      json.object([
        #("device", json.string("ios")),
      ]),
    )

  // Two entries for key1
  state.get_by_key(s, "topic", "key1") |> list.length |> expect.to_equal(2)

  // Different topic/key returns empty
  state.get_by_key(s, "another_topic", "key1") |> expect.to_equal([])
  state.get_by_key(s, "topic", "another_key") |> expect.to_equal([])
}

/// Phoenix test: "remove_down_replicas" — permanent deletion
pub fn phoenix_remove_down_replicas_test() {
  let s1 = state.new(r("node1"))
  let s2 = state.new(r("node2"))

  let s1 = join_ok(s1, "pid_alice", "lobby", "alice", json.object([]))
  let s2 = join_ok(s2, "pid_bob", "lobby", "bob", json.object([]))

  // Sync
  let s2 = merge_ok(s2, s1)
  state.online_list(s2) |> list.length |> expect.to_equal(2)

  // Mark node1 as down
  let #(s2, _) = state.replica_down(s2, r("node1"))

  // Permanently remove node1
  let assert Ok(#(s2, remove_diff)) = state.remove_down_replica(s2, r("node1"))
  // It was already hidden by replica_down, so pruning emits no duplicate leave.
  dict.size(remove_diff.leaves) |> expect.to_equal(0)

  // A retired incarnation cannot be marked up.
  state.replica_up(s2, r("node1"))
  |> expect.to_equal(Error(state.ReplicaRetired(r("node1"))))
  state.online_list(s2) |> list.length |> expect.to_equal(1)
}

// ── edge cases ───────────────────────────────────────────────────────

pub fn clocks_returns_vector_clock_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:1", "k1", json.object([]))
  let a = join_ok(a, "p2", "room:1", "k2", json.object([]))

  let clocks = state.compacted_clocks(a)
  case dict.get(clocks, r("node_a")) {
    Ok(2) -> Nil
    _ -> panic as "expected failure"
  }
}

pub fn compact_reduces_clouds_test() {
  // After local joins, context should be fully compacted (no clouds)
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:1", "k1", json.object([]))
  let a = join_ok(a, "p2", "room:1", "k2", json.object([]))

  let compacted = state.compact(a)
  case dict.get(state.internal_clouds(compacted), r("node_a")) {
    Ok(cloud) -> set.size(cloud) |> expect.to_equal(0)
    Error(_) -> Nil
  }
}

pub fn merge_with_empty_state_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:1", "k1", json.object([]))

  let empty = state.new(r("node_b"))

  // Merging empty into non-empty should be a no-op
  let #(merged, diff) = merge_diff_ok(a, empty)
  state.get_by_topic(merged, "room:1") |> list.length |> expect.to_equal(1)
  dict.size(diff.joins) |> expect.to_equal(0)
  dict.size(diff.leaves) |> expect.to_equal(0)
}

pub fn get_by_key_multiple_pids_test() {
  let a = state.new(r("node_a"))
  let a =
    join_ok(
      a,
      "pid1",
      "room:lobby",
      "user:alice",
      json.object([
        #("device", json.string("desktop")),
      ]),
    )
  let a =
    join_ok(
      a,
      "pid2",
      "room:lobby",
      "user:alice",
      json.object([
        #("device", json.string("mobile")),
      ]),
    )

  let results = state.get_by_key(a, "room:lobby", "user:alice")
  list.length(results) |> expect.to_equal(2)
}

pub fn leave_only_removes_matching_entry_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "pid1", "room:lobby", "alice", json.object([]))
  let a = join_ok(a, "pid1", "room:lobby", "bob", json.object([]))
  let a = state.leave(a, "pid1", "room:lobby", "alice")

  state.get_by_topic(a, "room:lobby") |> list.length |> expect.to_equal(1)
}

pub fn joins_propagate_through_intermediate_node_test() {
  // A -> B -> C chain: A's join should reach C via B
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:lobby", "alice", json.object([]))

  let b = state.new(r("node_b"))
  let b = merge_ok(b, a)

  let c = state.new(r("node_c"))
  let c = merge_ok(c, b)

  // C should see alice
  state.get_by_topic(c, "room:lobby") |> list.length |> expect.to_equal(1)
}

pub fn removes_propagate_through_intermediate_node_test() {
  // All three nodes sync, then A removes, propagate via B to C
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "room:lobby", "alice", json.object([]))

  let b = state.new(r("node_b"))
  let b = merge_ok(b, a)

  let c = state.new(r("node_c"))
  let c = merge_ok(c, b)

  // A removes alice
  let a = state.leave(a, "p1", "room:lobby", "alice")

  // Propagate: A -> B -> C
  let b = merge_ok(b, a)
  let c = merge_ok(c, b)

  state.get_by_topic(c, "room:lobby") |> expect.to_equal([])
}

/// Phoenix test: clocks advance correctly through merges
pub fn phoenix_clocks_advance_through_merge_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))

  let a = join_ok(a, "p1", "lobby", "alice", json.object([]))
  let b = join_ok(b, "p2", "lobby", "bob", json.object([]))

  let b = merge_ok(b, a)

  let clocks = state.compacted_clocks(b)
  case dict.get(clocks, r("node_a")) {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }
  case dict.get(clocks, r("node_b")) {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }

  // A leaves then rejoins — clock advances to 2
  let a = state.leave(a, "p1", "lobby", "alice")
  // leave doesn't advance clock, but re-join does:
  let a = join_ok(a, "p1", "lobby", "alice", json.object([]))

  let b = merge_ok(b, a)
  case dict.get(state.compacted_clocks(b), r("node_a")) {
    Ok(2) -> Nil
    _ -> panic as "expected failure"
  }
}

/// All clouds should be empty after merge (fully compacted)
pub fn phoenix_clouds_empty_after_merge_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))

  let a = join_ok(a, "p1", "lobby", "alice", json.object([]))
  let b = join_ok(b, "p2", "lobby", "bob", json.object([]))

  let b = merge_ok(b, a)

  // All clouds should be compacted away
  dict.to_list(state.internal_clouds(b))
  |> list.all(fn(kv) {
    let #(_, cloud) = kv
    set.is_empty(cloud)
  })
  |> expect.to_be_true
}

/// After merge produces non-empty clouds for local replica,
/// next join must get a clock higher than any cloud entry
pub fn next_clock_accounts_for_cloud_values_test() {
  // Node A: join at clock 1, then clock 2
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "lobby", "alice", json.object([]))
  let a = join_ok(a, "p2", "lobby", "bob", json.object([]))
  // a.context["node_a"] == 2

  // Node B: join at clock 1, then clock 2, then clock 3
  let b = state.new(r("node_b"))
  let b = join_ok(b, "p3", "lobby", "carol", json.object([]))
  let b = join_ok(b, "p4", "lobby", "dave", json.object([]))
  let b = join_ok(b, "p5", "lobby", "eve", json.object([]))
  // b.context["node_b"] == 3

  // Merge B into A -- A now knows about node_b clocks 1..3
  let _a = merge_ok(a, b)

  // Now construct a scenario with interleaved clocks that leave clouds.
  // Create a second state for node_a with only clock 1 (simulating partial info)
  let a2 = state.new(r("node_a"))
  let _a2 = join_ok(a2, "p6", "lobby", "frank", json.object([]))
  // a2.context["node_a"] == 1

  // Create a third state for node_a with clock 3 only
  // We do this by building state that has node_a at clock 3 via three joins
  let a3 = state.new(r("node_a"))
  let a3 = join_ok(a3, "p7", "lobby", "g1", json.object([]))
  let a3 = join_ok(a3, "p8", "lobby", "g2", json.object([]))
  let a3 = join_ok(a3, "p9", "lobby", "g3", json.object([]))
  // a3.context["node_a"] == 3, remove entries for clocks 1 and 2
  let a3 = state.leave(a3, "p7", "lobby", "g1")
  let _a3 = state.leave(a3, "p8", "lobby", "g2")
  // a3 still has context["node_a"] == 3 but only tag(node_a, 3) in values

  // Merge a3 into a2: a2 has context["node_a"]==1, a3 has context["node_a"]==3
  // After merge, context["node_a"] == max(1,3) == 3
  // The cloud for node_a should be empty since context covers 1..3
  // But let us construct a trickier scenario: partial overlap via clouds.

  // Better approach: directly test that after merging states that produce
  // non-empty clouds for the local replica, the next join skips past them.

  // Node X joins at clocks 1, 2, 3
  let x = state.new(r("node_x"))
  let x = join_ok(x, "px1", "lobby", "x1", json.object([]))
  let x = join_ok(x, "px2", "lobby", "x2", json.object([]))
  let _x = join_ok(x, "px3", "lobby", "x3", json.object([]))
  // x.context["node_x"] == 3

  // Decode a valid replicated state with a gap at clock 2.
  let assert Ok(merged) =
    state.from_json(
      "{\"replica\":{\"base\":\"node_x\",\"incarnation\":\"test-incarnation\"},\"context\":[{\"replica\":{\"base\":\"node_x\",\"incarnation\":\"test-incarnation\"},\"clock\":1}],\"clouds\":[{\"replica\":{\"base\":\"node_x\",\"incarnation\":\"test-incarnation\"},\"clocks\":[3]}],\"retired\":[],\"values\":[]}",
    )

  // The next join should produce clock 4 without falsely filling gap 2.
  let after_join =
    join_ok(merged, "pnew", "lobby", "new_entry", json.object([]))

  state.compacted_clocks(after_join)
  |> dict.get(r("node_x"))
  |> expect.to_equal(Ok(1))
  state.internal_clouds(after_join)
  |> dict.get(r("node_x"))
  |> expect.to_equal(Ok(set.from_list([3, 4])))

  // Also verify the entry is actually present
  state.get_by_topic(after_join, "lobby") |> list.length |> expect.to_equal(1)
}

pub fn divergent_same_incarnation_is_rejected_test() {
  let identity = r("node")
  let a = state.new(identity) |> join_ok("p1", "room", "a", json.null())
  let b = state.new(identity) |> join_ok("p2", "room", "b", json.null())

  state.merge(a, b)
  |> expect.to_equal(Error(state.DivergentReplicaIdentity(identity)))
}

pub fn divergent_same_incarnation_through_relays_is_rejected_test() {
  let identity = r("node")
  let a = state.new(identity) |> join_ok("p1", "room", "a", json.null())
  let b = state.new(identity) |> join_ok("p2", "room", "b", json.null())
  let relay_a = merge_ok(state.new(r("relay-a")), a)
  let relay_b = merge_ok(state.new(r("relay-b")), b)

  state.merge(relay_a, relay_b)
  |> expect.to_equal(Error(state.DivergentReplicaIdentity(identity)))
  state.merge(relay_b, relay_a)
  |> expect.to_equal(Error(state.DivergentReplicaIdentity(identity)))
}

pub fn same_incarnation_older_newer_snapshots_merge_both_directions_test() {
  let identity = r("node")
  let older = state.new(identity) |> join_ok("p1", "room", "a", json.null())
  let newer = older |> join_ok("p2", "room", "b", json.null())
  let old_new = merge_ok(older, newer)
  let new_old = merge_ok(newer, older)

  state.internal_values(old_new)
  |> expect.to_equal(state.internal_values(newer))
  state.internal_values(new_old)
  |> expect.to_equal(state.internal_values(newer))
}

pub fn exact_same_incarnation_replay_is_noop_test() {
  let a = state.new(r("node")) |> join_ok("p1", "room", "a", json.null())
  let assert Ok(#(replayed, diff)) = state.merge_with_diff(a, a)

  state.internal_values(replayed) |> expect.to_equal(state.internal_values(a))
  dict.size(diff.joins) |> expect.to_equal(0)
  dict.size(diff.leaves) |> expect.to_equal(0)
}

pub fn same_base_distinct_incarnations_merge_test() {
  let assert Ok(old) = state.new_replica("node", "old")
  let assert Ok(new) = state.new_replica("node", "new")
  let a = state.new(old) |> join_ok("p1", "room", "a", json.null())
  let b = state.new(new) |> join_ok("p2", "room", "b", json.null())
  let merged = merge_ok(a, b)

  state.online_list(merged) |> list.length |> expect.to_equal(2)
  state.same_base(old, new) |> expect.to_be_true
}

pub fn remove_live_replica_is_rejected_test() {
  let s = state.new(r("node"))
  state.remove_down_replica(s, r("node"))
  |> expect.to_equal(Error(state.ReplicaNotDown(r("node"))))
}

pub fn remove_down_replica_tombstone_blocks_stale_replay_test() {
  let a = state.new(r("a"))
  let stale_seen = state.new(r("b")) |> join_ok("p1", "room", "b1", json.null())
  let stale_higher = stale_seen |> join_ok("p2", "room", "b2", json.null())
  let a = merge_ok(a, stale_seen)
  let #(a, _) = state.replica_down(a, r("b"))
  let assert Ok(#(a, _)) = state.remove_down_replica(a, r("b"))
  let replayed = merge_ok(a, stale_higher)

  state.online_list(replayed) |> expect.to_equal([])
  set.contains(state.retired_replicas(replayed), r("b"))
  |> expect.to_be_true
  dict.get(state.compacted_clocks(replayed), r("b"))
  |> expect.to_equal(Error(Nil))
}

pub fn retired_merge_emits_leave_for_visible_entry_test() {
  let remote =
    state.new(r("remote"))
    |> join_ok("p1", "room", "remote", json.object([#("v", json.int(1))]))
  let local = merge_ok(state.new(r("local")), remote)
  let retiring = merge_ok(state.new(r("retiring")), remote)
  let #(retiring, _) = state.replica_down(retiring, r("remote"))
  let assert Ok(#(retiring, _)) =
    state.remove_down_replica(retiring, r("remote"))

  let #(merged, diff) = merge_diff_ok(local, retiring)

  state.get_by_topic(merged, "room") |> expect.to_equal([])
  dict.get(diff.leaves, "room")
  |> expect.to_equal(
    Ok([#("remote", "p1", json.object([#("v", json.int(1))]))]),
  )
  dict.size(diff.joins) |> expect.to_equal(0)
}

pub fn down_replica_merge_defers_join_until_replica_up_test() {
  let remote =
    state.new(r("remote"))
    |> join_ok("p1", "room", "remote", json.null())
  let #(local, _) = state.replica_down(state.new(r("local")), r("remote"))

  let #(local, merge_diff) = merge_diff_ok(local, remote)
  dict.size(merge_diff.joins) |> expect.to_equal(0)
  dict.size(merge_diff.leaves) |> expect.to_equal(0)
  state.get_by_topic(local, "room") |> expect.to_equal([])

  let assert Ok(#(local, up_diff)) = state.replica_up(local, r("remote"))
  dict.get(up_diff.joins, "room")
  |> expect.to_equal(Ok([#("remote", "p1", json.null())]))

  let assert Ok(#(_local, second_up_diff)) =
    state.replica_up(local, r("remote"))
  dict.size(second_up_diff.joins) |> expect.to_equal(0)
  dict.size(second_up_diff.leaves) |> expect.to_equal(0)
}

pub fn supersede_prunes_old_incarnations_and_is_idempotent_test() {
  let assert Ok(old) = state.new_replica("node", "old")
  let assert Ok(new) = state.new_replica("node", "new")
  let other = r("other")
  let old_state = state.new(old) |> join_ok("old-p", "room", "old", json.null())
  let other_state =
    state.new(other) |> join_ok("other-p", "room", "other", json.null())
  let combined = merge_ok(old_state, other_state)

  let stale_higher = old_state |> join_ok("old-p2", "room", "old2", json.null())
  let assert Ok(#(superseded, diff)) = state.supersede(combined, new)
  state.replica(superseded) |> expect.to_equal(old)
  state.online_list(superseded) |> list.length |> expect.to_equal(1)
  dict.size(diff.leaves) |> expect.to_equal(1)
  set.contains(state.retired_replicas(superseded), old) |> expect.to_be_true
  let replayed = merge_ok(superseded, stale_higher)
  state.online_list(replayed) |> list.length |> expect.to_equal(1)

  let assert Ok(#(again, second_diff)) = state.supersede(superseded, new)
  state.internal_values(again)
  |> expect.to_equal(state.internal_values(superseded))
  dict.size(second_diff.leaves) |> expect.to_equal(0)
}

pub fn supersede_on_relay_preserves_unrelated_local_identity_test() {
  let assert Ok(old) = state.new_replica("node", "old")
  let assert Ok(new) = state.new_replica("node", "new")
  let relay = r("relay")
  let combined =
    merge_ok(
      state.new(relay),
      state.new(old) |> join_ok("old", "room", "old", json.null()),
    )
  let assert Ok(#(superseded, _)) = state.supersede(combined, new)

  state.replica(superseded) |> expect.to_equal(relay)
  set.contains(state.retired_replicas(superseded), old) |> expect.to_be_true
}

pub fn supersede_preserves_new_incarnation_down_status_test() {
  let assert Ok(new) = state.new_replica("node", "new")
  let relay = r("relay")
  let new_state = state.new(new) |> join_ok("new", "room", "new", json.null())
  let combined = merge_ok(state.new(relay), new_state)
  let #(combined, down_diff) = state.replica_down(combined, new)
  dict.size(down_diff.leaves) |> expect.to_equal(1)

  let assert Ok(#(superseded, diff)) = state.supersede(combined, new)
  state.online_list(superseded) |> expect.to_equal([])
  dict.size(diff.joins) |> expect.to_equal(0)
  dict.size(diff.leaves) |> expect.to_equal(0)

  let assert Ok(#(up, up_diff)) = state.replica_up(superseded, new)
  state.online_list(up) |> list.length |> expect.to_equal(1)
  dict.size(up_diff.joins) |> expect.to_equal(1)
}

pub fn retired_local_identity_cannot_join_or_be_marked_up_test() {
  let local = r("local")
  let peer = r("peer")
  let local_snapshot =
    state.new(local) |> join_ok("p", "room", "local", json.null())
  let peer_state = merge_ok(state.new(peer), local_snapshot)
  let #(peer_state, _) = state.replica_down(peer_state, local)
  let assert Ok(#(peer_state, _)) = state.remove_down_replica(peer_state, local)
  let retired_local = merge_ok(local_snapshot, peer_state)

  state.join(retired_local, "new", "room", "new", json.null())
  |> expect.to_equal(Error(state.ReplicaRetired(local)))
  state.replica_up(retired_local, local)
  |> expect.to_equal(Error(state.ReplicaRetired(local)))

  let assert Ok(roundtripped) =
    state.from_json(state.to_json_string(retired_local))
  state.join(roundtripped, "new", "room", "new", json.null())
  |> expect.to_equal(Error(state.ReplicaRetired(local)))
}

pub fn decoder_rejects_context_cloud_overlap_test() {
  let payload =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"context\":[{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clock\":3}],\"clouds\":[{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clocks\":[1,3,4,6]}],\"retired\":[],\"values\":[]}"
  let _ = state.from_json(payload) |> expect.to_be_error
  Nil
}
