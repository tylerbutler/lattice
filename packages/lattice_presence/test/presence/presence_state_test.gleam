import gleam/dict
import gleam/json
import gleam/list
import gleam/set
import lattice_presence/presence_state as state
import startest/expect

// ── new ──────────────────────────────────────────────────────────────

pub fn new_creates_empty_state_test() {
  let s = state.new("node1")
  state.online_list(s) |> expect.to_equal([])
  state.replica(s) |> expect.to_equal("node1")
}

pub fn new_incarnation_creates_unique_replica_identity_test() {
  let first = state.new_incarnation("node:west")
  let second = state.new_incarnation("node:west")

  state.replica(first) |> expect.to_not_equal(state.replica(second))
  state.base_replica(state.replica(first)) |> expect.to_equal("node:west")
  state.base_replica(state.replica(second)) |> expect.to_equal("node:west")
  state.same_base(state.replica(first), state.replica(second))
  |> expect.to_equal(True)
}

pub fn base_replica_preserves_caller_supplied_identity_test() {
  let replica = "lattice-presence:v1:not-a-uuid:node:west"

  state.base_replica(replica) |> expect.to_equal(replica)
  state.same_base(replica, state.replica(state.new(replica)))
  |> expect.to_equal(True)
  state.same_base(replica, "node:west") |> expect.to_equal(False)
}

// ── join ─────────────────────────────────────────────────────────────

pub fn join_makes_user_online_test() {
  let s = state.new("node1")
  let s =
    state.join(
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
  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = state.join(s, "pid2", "room:lobby", "bob", json.object([]))

  let entries = state.get_by_topic(s, "room:lobby")
  list.length(entries) |> expect.to_equal(2)
}

pub fn join_multiple_topics_test() {
  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = state.join(s, "pid1", "room:private", "alice", json.object([]))

  state.get_by_topic(s, "room:lobby") |> list.length |> expect.to_equal(1)
  state.get_by_topic(s, "room:private") |> list.length |> expect.to_equal(1)
}

// ── leave ────────────────────────────────────────────────────────────

pub fn leave_removes_user_test() {
  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = state.leave(s, "pid1", "room:lobby", "alice")

  state.get_by_topic(s, "room:lobby") |> expect.to_equal([])
}

pub fn leave_nonexistent_is_noop_test() {
  let s = state.new("node1")
  let s = state.leave(s, "pid1", "room:lobby", "alice")
  state.online_list(s) |> expect.to_equal([])
}

pub fn leave_all_by_pid_test() {
  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "alice", json.object([]))
  let s = state.join(s, "pid1", "room:private", "alice", json.object([]))
  let s = state.join(s, "pid2", "room:lobby", "bob", json.object([]))

  let s = state.leave_by_pid(s, "pid1")

  // pid1's entries gone, pid2's entry remains
  state.online_list(s) |> list.length |> expect.to_equal(1)
  state.get_by_topic(s, "room:private") |> expect.to_equal([])
}

// ── merge ────────────────────────────────────────────────────────────

pub fn merge_adds_remote_entries_test() {
  // Node A has alice, Node B has bob
  let a = state.new("node_a")
  let a = state.join(a, "pid1", "room:lobby", "alice", json.object([]))

  let b = state.new("node_b")
  let b = state.join(b, "pid2", "room:lobby", "bob", json.object([]))

  // Merge B into A
  let assert Ok(merged) = state.merge(a, b)

  // A should now see both alice and bob
  state.get_by_topic(merged, "room:lobby") |> list.length |> expect.to_equal(2)
}

pub fn restarted_replica_fresh_join_survives_old_higher_clock_test() {
  let before_restart =
    state.new_incarnation("node-a")
    |> state.join("old-pid-1", "room:lobby", "old-1", json.object([]))
    |> state.join("old-pid-2", "room:lobby", "old-2", json.object([]))
  let assert Ok(peer) =
    state.new_incarnation("node-b")
    |> state.merge(before_restart)

  let after_restart =
    state.new_incarnation("node-a")
    |> state.join("fresh-pid", "room:lobby", "fresh", json.object([]))
  let assert Ok(peer) = state.merge(peer, after_restart)

  state.get_by_key(peer, "room:lobby", "fresh")
  |> list.length
  |> expect.to_equal(1)
}

pub fn restarted_replica_rejects_and_removes_cached_old_entry_test() {
  let before_restart =
    state.new_incarnation("node-a")
    |> state.join("old-pid", "room:lobby", "old", json.object([]))
  let assert Ok(peer) =
    state.new_incarnation("node-b")
    |> state.merge(before_restart)

  let after_restart = state.new_incarnation("node-a")
  let assert Ok(#(after_restart, diff)) =
    state.merge_with_diff(after_restart, peer)
  state.get_by_topic(after_restart, "room:lobby") |> expect.to_equal([])
  dict.size(diff.joins) |> expect.to_equal(0)

  let assert Ok(peer) = state.merge(peer, after_restart)
  state.get_by_topic(peer, "room:lobby") |> expect.to_equal([])
}

pub fn merge_is_idempotent_test() {
  let a = state.new("node_a")
  let a = state.join(a, "pid1", "room:lobby", "alice", json.object([]))

  let b = state.new("node_b")
  let b = state.join(b, "pid2", "room:lobby", "bob", json.object([]))

  // Merge twice should not duplicate
  let assert Ok(merged) = state.merge(a, b)
  let assert Ok(merged2) = state.merge(merged, b)

  state.get_by_topic(merged2, "room:lobby") |> list.length |> expect.to_equal(2)
}

pub fn merge_observes_remote_removals_test() {
  // Node A and B both know about alice
  let a = state.new("node_a")
  let a = state.join(a, "pid1", "room:lobby", "alice", json.object([]))

  // B merges A's state to learn about alice
  let b = state.new("node_b")
  let assert Ok(b) = state.merge(b, a)

  // A removes alice locally
  let a = state.leave(a, "pid1", "room:lobby", "alice")

  // B merges A again — should observe the removal
  let assert Ok(merged) = state.merge(b, a)
  state.get_by_topic(merged, "room:lobby") |> expect.to_equal([])
}

pub fn merge_add_wins_over_concurrent_remove_test() {
  // A has alice, B learns about alice
  let a = state.new("node_a")
  let a =
    state.join(
      a,
      "pid1",
      "room:lobby",
      "alice",
      json.object([
        #("v", json.int(1)),
      ]),
    )

  let b = state.new("node_b")
  let assert Ok(b) = state.merge(b, a)

  // Concurrently: A removes alice, B re-adds alice
  let a = state.leave(a, "pid1", "room:lobby", "alice")
  let b =
    state.join(
      b,
      "pid1",
      "room:lobby",
      "alice",
      json.object([
        #("v", json.int(2)),
      ]),
    )

  // When A merges B, alice should be present (add wins)
  let assert Ok(merged) = state.merge(a, b)
  state.get_by_topic(merged, "room:lobby") |> list.length |> expect.to_equal(1)
}

pub fn merge_returns_diff_with_joins_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")
  let b = state.join(b, "pid1", "room:lobby", "bob", json.object([]))

  let assert Ok(#(_merged, diff)) = state.merge_with_diff(a, b)

  // Diff should show bob as a join
  case dict.get(diff.joins, "room:lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

pub fn merge_returns_diff_with_leaves_test() {
  // A knows about bob (from previous merge with B)
  let a = state.new("node_a")
  let b = state.new("node_b")
  let b = state.join(b, "pid1", "room:lobby", "bob", json.object([]))

  let assert Ok(a) = state.merge(a, b)

  // B removes bob
  let b = state.leave(b, "pid1", "room:lobby", "bob")

  // Merge again — diff should show bob as a leave
  let assert Ok(#(_merged, diff)) = state.merge_with_diff(a, b)
  case dict.get(diff.leaves, "room:lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

pub fn merge_three_nodes_test() {
  // Three nodes, each with one user
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:lobby", "alice", json.object([]))

  let b = state.new("node_b")
  let b = state.join(b, "p2", "room:lobby", "bob", json.object([]))

  let c = state.new("node_c")
  let c = state.join(c, "p3", "room:lobby", "carol", json.object([]))

  // Merge all into A via two hops
  let assert Ok(a) = state.merge(a, b)
  let assert Ok(a) = state.merge(a, c)

  state.get_by_topic(a, "room:lobby") |> list.length |> expect.to_equal(3)
}

// ── Phoenix-inspired merge tests ────────────────────────────────────
// Ported from Phoenix.Tracker.StateTest

/// Phoenix test: "users from other servers merge" — full lifecycle
/// merge, idempotent re-merge, observe remove, new join after remove,
/// and metadata update via leave+join
pub fn phoenix_full_merge_lifecycle_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")

  let a = state.join(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = state.join(b, "pid_bob", "lobby", "bob", json.object([]))

  // Merge B into A — bob appears as join
  let assert Ok(#(a, diff)) = state.merge_with_diff(a, b)
  state.online_list(a) |> list.length |> expect.to_equal(2)
  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }

  // Merge B into A again — idempotent, no new events
  let assert Ok(#(a2, diff2)) = state.merge_with_diff(a, b)
  dict.size(diff2.joins) |> expect.to_equal(0)
  dict.size(diff2.leaves) |> expect.to_equal(0)
  state.online_list(a2) |> list.length |> expect.to_equal(2)

  // Merge A into B — alice appears as join
  let assert Ok(#(b, diff3)) = state.merge_with_diff(b, a)
  case dict.get(diff3.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  // Re-merge is idempotent
  let assert Ok(#(_b2, diff4)) = state.merge_with_diff(b, a)
  dict.size(diff4.joins) |> expect.to_equal(0)

  // A removes alice, B observes via merge
  let a = state.leave(a, "pid_alice", "lobby", "alice")
  let assert Ok(#(b, diff5)) = state.merge_with_diff(b, a)
  case dict.get(diff5.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  state.online_list(b) |> list.length |> expect.to_equal(1)

  // B adds carol
  let b = state.join(b, "pid_carol", "lobby", "carol", json.object([]))
  state.online_list(b) |> list.length |> expect.to_equal(2)

  // A merges B — gets carol
  let assert Ok(#(a, diff6)) = state.merge_with_diff(a, b)
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
  let a = state.new("node_a")
  let b = state.new("node_b")

  let b =
    state.join(
      b,
      "pid_carol",
      "lobby",
      "carol",
      json.object([
        #("status", json.string("online")),
      ]),
    )

  // Sync A with B
  let assert Ok(a) = state.merge(a, b)

  // B updates carol by leaving then rejoining with new meta
  let b = state.leave(b, "pid_carol", "lobby", "carol")
  let b =
    state.join(
      b,
      "pid_carol",
      "lobby",
      "carol",
      json.object([
        #("status", json.string("away")),
      ]),
    )

  // Merge into A — should see a leave and a join for carol
  let assert Ok(#(_a, diff)) = state.merge_with_diff(a, b)
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
  let a = state.new("node_a")
  let b = state.new("node_b")

  let a = state.join(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = state.join(b, "pid_bob", "lobby", "bob", json.object([]))

  // Sync
  let assert Ok(a) = state.merge(a, b)
  state.online_list(a) |> list.length |> expect.to_equal(2)

  // A does some mutations
  let a = state.join(a, "pid_carol", "lobby", "carol", json.object([]))
  let a = state.leave(a, "pid_alice", "lobby", "alice")
  let a = state.join(a, "pid_david", "lobby", "david", json.object([]))

  // Netsplit: A marks B as down
  let #(a, down_diff) = state.replica_down(a, "node_b")
  // bob should show as a leave
  case dict.get(down_diff.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  // Only carol and david visible (alice left, bob is down)
  state.online_list(a) |> list.length |> expect.to_equal(2)

  // Merge while down is no-op for visibility
  let assert Ok(#(a, noop_diff)) = state.merge_with_diff(a, b)
  dict.size(noop_diff.joins) |> expect.to_equal(0)
  state.online_list(a) |> list.length |> expect.to_equal(2)

  // Heal: A marks B as up — bob reappears
  let #(a, up_diff) = state.replica_up(a, "node_b")
  case dict.get(up_diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  // carol, david, bob
  state.online_list(a) |> list.length |> expect.to_equal(3)
}

/// Phoenix test: "joins are observed via other node" (3-node with netsplit)
pub fn phoenix_joins_via_intermediate_node_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")
  let c = state.new("node_c")

  let a = state.join(a, "pid_alice", "lobby", "alice", json.object([]))

  // C learns about alice from A
  let assert Ok(c) = state.merge(c, a)
  state.get_by_topic(c, "lobby") |> list.length |> expect.to_equal(1)

  // Netsplit between A and C
  let #(a, _) = state.replica_down(a, "node_c")
  let #(c, _) = state.replica_down(c, "node_a")

  // A adds bob
  let a = state.join(a, "pid_bob", "lobby", "bob", json.object([]))

  // B merges A's full state — gets both alice and bob
  let assert Ok(b) = state.merge(b, a)
  state.get_by_topic(b, "lobby") |> list.length |> expect.to_equal(2)

  // C merges B — should get bob (which C hasn't seen yet)
  let assert Ok(#(_c, diff)) = state.merge_with_diff(c, b)
  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

/// Phoenix test: "removes are observed via other node" (3-node with netsplit)
/// Tests that removes propagate through an intermediate node even during netsplit
pub fn phoenix_removes_via_intermediate_node_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")
  let c = state.new("node_c")

  let a = state.join(a, "pid_alice", "lobby", "alice", json.object([]))

  // All nodes learn about alice
  let assert Ok(b) = state.merge(b, a)
  let assert Ok(c) = state.merge(c, a)

  // B adds bob
  let b = state.join(b, "pid_bob", "lobby", "bob", json.object([]))

  // A and C learn about bob
  let assert Ok(a) = state.merge(a, b)
  let assert Ok(c) = state.merge(c, b)
  state.get_by_topic(c, "lobby") |> list.length |> expect.to_equal(2)

  // Netsplit between A and C (B can talk to both)
  let #(a, _) = state.replica_down(a, "node_c")
  let #(c, _) = state.replica_down(c, "node_a")

  // A removes alice
  let a = state.leave(a, "pid_alice", "lobby", "alice")

  // B observes remove via A
  let assert Ok(b) = state.merge(b, a)

  // C observes remove via B (not directly from A due to netsplit)
  let assert Ok(#(_c, diff)) = state.merge_with_diff(c, b)
  case dict.get(diff.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

// ── extract (delta) ──────────────────────────────────────────────────

pub fn extract_produces_delta_for_new_replica_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:lobby", "alice", json.object([]))
  let a = state.join(a, "p2", "room:lobby", "bob", json.object([]))

  // Extract what a fresh replica needs from A (everything)
  let delta = state.extract_full_state(a)

  // Delta should contain both entries
  dict.size(state.internal_values(delta)) |> expect.to_equal(2)
}

pub fn extract_returns_full_state_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:lobby", "alice", json.object([]))

  // Extract returns full state — merge handles deduplication
  let extracted = state.extract_full_state(a)
  dict.size(state.internal_values(extracted)) |> expect.to_equal(1)
}

pub fn extract_includes_all_entries_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:lobby", "alice", json.object([]))
  let a = state.join(a, "p2", "room:lobby", "bob", json.object([]))

  // A adds a third entry
  let a = state.join(a, "p3", "room:lobby", "carol", json.object([]))

  // Extract returns all 3 entries (full state)
  let extracted = state.extract_full_state(a)
  dict.size(state.internal_values(extracted)) |> expect.to_equal(3)
}

/// Phoenix test: extract-based merge workflow (mirrors Phoenix's merge(a, extract(b, ...)))
pub fn phoenix_extract_merge_workflow_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")

  let a = state.join(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = state.join(b, "pid_bob", "lobby", "bob", json.object([]))

  // Merge using extract (like Phoenix does)
  let delta_b = state.extract_full_state(b)
  let assert Ok(#(a, diff)) = state.merge_with_diff(a, delta_b)
  state.online_list(a) |> list.length |> expect.to_equal(2)
  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }

  // Second extract-merge is idempotent
  let delta_b2 = state.extract_full_state(b)
  let assert Ok(#(a2, diff2)) = state.merge_with_diff(a, delta_b2)
  dict.size(diff2.joins) |> expect.to_equal(0)
  dict.size(diff2.leaves) |> expect.to_equal(0)
  state.online_list(a2) |> list.length |> expect.to_equal(2)
}

/// Phoenix test: extract-based remove observation
pub fn phoenix_extract_observes_remove_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")

  let a = state.join(a, "pid_alice", "lobby", "alice", json.object([]))
  let b = state.join(b, "pid_bob", "lobby", "bob", json.object([]))

  // Sync both directions
  let assert Ok(a) = state.merge(a, state.extract_full_state(b))
  let assert Ok(b) = state.merge(b, state.extract_full_state(a))

  // A removes alice
  let a = state.leave(a, "pid_alice", "lobby", "alice")

  // B merges A's extract — should observe alice's removal
  let assert Ok(#(b, diff)) =
    state.merge_with_diff(b, state.extract_full_state(a))
  case dict.get(diff.leaves, "lobby") {
    Ok(leaves) -> list.length(leaves) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
  state.online_list(b) |> list.length |> expect.to_equal(1)
}

/// Phoenix test: "get_by_topic" with multiple replicas and down/up filtering
pub fn phoenix_get_by_topic_with_replica_status_test() {
  let s1 = state.new("node1")
  let s2 = state.new("node2")
  let s3 = state.new("node3")

  // Each node adds entries
  let s1 = state.join(s1, "pid1", "topic", "key1", json.object([]))
  let s1 = state.join(s1, "pid1", "topic", "key2", json.object([]))
  let s2 = state.join(s2, "pid2", "topic", "user2", json.object([]))
  let s3 = state.join(s3, "pid3", "topic", "user3", json.object([]))

  // s1 sees only local entries
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(2)

  // Merge all into s1
  let assert Ok(s1) = state.merge(s1, s2)
  let assert Ok(s1) = state.merge(s1, s3)

  // All 4 entries visible
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(4)

  // One replica down — 3 entries visible
  let #(s1, _) = state.replica_down(s1, "node2")
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(3)

  // Two replicas down — 2 entries visible (only local)
  let #(s1, _) = state.replica_down(s1, "node3")
  state.get_by_topic(s1, "topic") |> list.length |> expect.to_equal(2)

  // Different topic returns empty
  state.get_by_topic(s1, "another:topic") |> expect.to_equal([])
}

/// Phoenix test: "get_by_key" with multiple pids for same key
pub fn phoenix_get_by_key_test() {
  let s = state.new("node1")

  state.get_by_key(s, "topic", "key1") |> expect.to_equal([])

  let s =
    state.join(
      s,
      "pid1",
      "topic",
      "key1",
      json.object([
        #("device", json.string("browser")),
      ]),
    )
  let s =
    state.join(
      s,
      "pid2",
      "topic",
      "key1",
      json.object([
        #("device", json.string("ios")),
      ]),
    )
  let s =
    state.join(
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
  let s1 = state.new("node1")
  let s2 = state.new("node2")

  let s1 = state.join(s1, "pid_alice", "lobby", "alice", json.object([]))
  let s2 = state.join(s2, "pid_bob", "lobby", "bob", json.object([]))

  // Sync
  let assert Ok(s2) = state.merge(s2, s1)
  state.online_list(s2) |> list.length |> expect.to_equal(2)

  // Mark node1 as down
  let #(s2, _) = state.replica_down(s2, "node1")

  // Permanently remove node1
  let s2 = state.remove_down_replica(s2, "node1")

  // Even after replica_up and stale gossip, alice is gone permanently
  let #(s2, _) = state.replica_up(s2, "node1")
  let assert Ok(s2) = state.merge(s2, s1)
  state.online_list(s2) |> list.length |> expect.to_equal(1)
}

pub fn supersede_combines_visible_leaves_with_multiplicity_and_metadata_test() {
  let shared_meta = json.object([#("device", json.string("browser"))])
  let private_meta = json.object([#("device", json.string("phone"))])
  let old_up =
    state.new_incarnation("node")
    |> state.join("shared-pid", "lobby", "shared-key", shared_meta)
    |> state.join("shared-pid", "lobby", "shared-key", shared_meta)
    |> state.join("private-pid", "private", "private-key", private_meta)
  let old_unknown =
    state.new_incarnation("node")
    |> state.join("shared-pid", "lobby", "shared-key", shared_meta)
    |> state.join("other-pid", "lobby", "other-key", private_meta)
  let old_down =
    state.new_incarnation("node")
    |> state.join("hidden-pid", "lobby", "hidden-key", json.null())
  let current =
    state.new_incarnation("node")
    |> state.join("current-pid", "lobby", "current-key", shared_meta)
  let local =
    state.new("observer")
    |> state.join("local-pid", "lobby", "local-key", private_meta)
  let assert Ok(local) = state.merge(local, old_up)
  let assert Ok(local) = state.merge(local, old_unknown)
  let assert Ok(local) = state.merge(local, old_down)
  let assert Ok(local) = state.merge(local, current)
  let #(local, _) = state.replica_up(local, state.replica(old_up))
  let #(local, down_diff) = state.replica_down(local, state.replica(old_down))
  dict.get(down_diff.leaves, "lobby")
  |> expect.to_equal(Ok([#("hidden-key", "hidden-pid", json.null())]))

  let assert Ok(#(cleaned, diff)) =
    state.supersede(local, state.replica(current))

  diff.joins |> expect.to_equal(dict.new())
  dict.size(diff.leaves) |> expect.to_equal(2)
  let assert Ok(lobby_leaves) = dict.get(diff.leaves, "lobby")
  list.length(lobby_leaves) |> expect.to_equal(4)
  lobby_leaves
  |> list.filter(fn(entry) {
    entry == #("shared-key", "shared-pid", shared_meta)
  })
  |> list.length
  |> expect.to_equal(3)
  lobby_leaves
  |> list.filter(fn(entry) {
    entry == #("other-key", "other-pid", private_meta)
  })
  |> list.length
  |> expect.to_equal(1)
  dict.get(diff.leaves, "private")
  |> expect.to_equal(Ok([#("private-key", "private-pid", private_meta)]))
  state.internal_values(cleaned)
  |> expect.to_equal(
    dict.filter(state.internal_values(local), fn(tag, _) {
      tag.replica == "observer" || tag.replica == state.replica(current)
    }),
  )
  state.online_list(cleaned) |> list.length |> expect.to_equal(2)
  state.compacted_clocks(cleaned)
  |> expect.to_equal(state.compacted_clocks(local))
  state.replica(cleaned) |> expect.to_equal("observer")
  state.supersede(cleaned, state.replica(current))
  |> expect.to_equal(
    Ok(#(cleaned, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )
}

pub fn supersede_discovers_sparse_history_and_uncovered_value_owners_test() {
  let context_only = "lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAQ==:node"
  let cloud_only = "lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAg==:node"
  let mixed = "lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAw==:node"
  let value_only = "lattice-presence:v1:AAAAAAAAQACAAAAAAAAABA==:node"
  let current = "lattice-presence:v1:AAAAAAAAQACAAAAAAAAABQ==:node"
  let assert Ok(local) =
    state.from_json(
      "{\"replica\":\"observer\",\"context\":{
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAQ==:node\":9,
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAw==:node\":2,
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAABQ==:node\":1,
        \"unrelated\":1
      },\"clouds\":{
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAg==:node\":[3,7],
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAw==:node\":[4,8],
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAABQ==:node\":[2,5],
        \"unrelated\":[2,4]
      },\"values\":[
        {\"tag\":{\"replica\":\"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAw==:node\",\"clock\":8},\"entry\":{\"topic\":\"lobby\",\"key\":\"covered-key\",\"pid\":\"covered-pid\",\"meta\":\"covered\"}},
        {\"tag\":{\"replica\":\"lattice-presence:v1:AAAAAAAAQACAAAAAAAAABA==:node\",\"clock\":12},\"entry\":{\"topic\":\"lobby\",\"key\":\"uncovered-key\",\"pid\":\"uncovered-pid\",\"meta\":\"uncovered\"}},
        {\"tag\":{\"replica\":\"lattice-presence:v1:AAAAAAAAQACAAAAAAAAABQ==:node\",\"clock\":5},\"entry\":{\"topic\":\"lobby\",\"key\":\"current-key\",\"pid\":\"current-pid\",\"meta\":true}},
        {\"tag\":{\"replica\":\"unrelated\",\"clock\":4},\"entry\":{\"topic\":\"lobby\",\"key\":\"other-key\",\"pid\":\"other-pid\",\"meta\":false}}
      ]}",
    )
  list.each([context_only, cloud_only, mixed, value_only, current], fn(id) {
    state.base_replica(id) |> expect.to_equal("node")
  })

  let assert Ok(#(cleaned, diff)) = state.supersede(local, current)

  state.compacted_clocks(cleaned)
  |> expect.to_equal(
    dict.from_list([
      #(context_only, 9),
      #(cloud_only, 7),
      #(mixed, 8),
      #(current, 1),
      #("unrelated", 1),
    ]),
  )
  state.internal_clouds(cleaned)
  |> expect.to_equal(
    dict.filter(state.internal_clouds(local), fn(id, _) {
      id == current || id == "unrelated"
    }),
  )
  state.internal_values(cleaned)
  |> expect.to_equal(
    dict.filter(state.internal_values(local), fn(tag, _) {
      tag.replica == current || tag.replica == "unrelated"
    }),
  )
  diff.joins |> expect.to_equal(dict.new())
  dict.size(diff.leaves) |> expect.to_equal(1)
  let assert Ok(leaves) = dict.get(diff.leaves, "lobby")
  list.length(leaves) |> expect.to_equal(2)
  set.from_list(leaves)
  |> expect.to_equal(
    set.from_list([
      #("covered-key", "covered-pid", json.string("covered")),
      #("uncovered-key", "uncovered-pid", json.string("uncovered")),
    ]),
  )
  state.supersede(cleaned, current)
  |> expect.to_equal(
    Ok(#(cleaned, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )
}

pub fn supersede_prunes_status_only_candidates_test() {
  let current = state.new_incarnation("node") |> state.replica
  let old_up = state.new_incarnation("node") |> state.replica
  let old_down = state.new_incarnation("node") |> state.replica
  let local = state.new("observer")
  let #(with_status, _) = state.replica_up(local, old_up)
  let #(with_status, _) = state.replica_down(with_status, old_down)

  state.supersede(with_status, current)
  |> expect.to_equal(
    Ok(#(local, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )
}

pub fn supersede_empty_and_absent_selected_are_idempotent_test() {
  let current = state.new_incarnation("node") |> state.replica
  let local = state.new("observer")
  let empty_diff = state.Diff(joins: dict.new(), leaves: dict.new())
  state.supersede(local, current)
  |> expect.to_equal(Ok(#(local, empty_diff)))
  state.supersede(local, state.replica(local))
  |> expect.to_equal(Ok(#(local, empty_diff)))

  let old =
    state.new_incarnation("node")
    |> state.join("old-pid", "lobby", "old-key", json.null())
  let assert Ok(local) = state.merge(local, old)
  let assert Ok(#(cleaned, _)) = state.supersede(local, current)
  state.entry_count(cleaned) |> expect.to_equal(0)
  dict.has_key(state.compacted_clocks(cleaned), current)
  |> expect.to_equal(False)
  let #(expected, _) = state.replica_down(local, state.replica(old))
  let expected = state.remove_down_replica(expected, state.replica(old))
  cleaned |> expect.to_equal(expected)
  state.supersede(cleaned, current)
  |> expect.to_equal(Ok(#(cleaned, empty_diff)))
}

pub fn supersede_keeps_selected_and_unrelated_replicas_down_test() {
  let old =
    state.new_incarnation("node")
    |> state.join("old-pid", "lobby", "old-key", json.null())
  let current =
    state.new_incarnation("node")
    |> state.join("current-pid", "lobby", "current-key", json.null())
  let other =
    state.new("other")
    |> state.join("other-pid", "lobby", "other-key", json.null())
  let assert Ok(local) = state.merge(state.new("observer"), old)
  let assert Ok(local) = state.merge(local, current)
  let assert Ok(local) = state.merge(local, other)
  let #(local, _) = state.replica_down(local, state.replica(current))
  let #(local, _) = state.replica_down(local, "other")

  let assert Ok(#(cleaned, diff)) =
    state.supersede(local, state.replica(current))

  diff
  |> expect.to_equal(state.Diff(
    joins: dict.new(),
    leaves: dict.from_list([
      #("lobby", [#("old-key", "old-pid", json.null())]),
    ]),
  ))
  state.online_list(cleaned) |> expect.to_equal([])
  state.entry_count(cleaned) |> expect.to_equal(2)
  state.compacted_clocks(cleaned)
  |> expect.to_equal(state.compacted_clocks(local))
  state.supersede(cleaned, state.replica(current))
  |> expect.to_equal(
    Ok(#(cleaned, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )
  let #(restored, _) = state.replica_up(cleaned, state.replica(current))
  state.get_by_topic(restored, "lobby")
  |> expect.to_equal([#("current-pid", "current-key", json.null())])
}

pub fn supersede_uses_existing_raw_and_incarnation_base_semantics_test() {
  let raw =
    state.new("node:west")
    |> state.join("raw-pid", "lobby", "raw-key", json.null())
  let current =
    state.new_incarnation("node:west")
    |> state.join("current-pid", "lobby", "current-key", json.null())
  let malformed =
    state.new("lattice-presence:v1:not-a-uuid:node:west")
    |> state.join("malformed-pid", "lobby", "malformed-key", json.null())
  let other =
    state.new("node:west:suffix")
    |> state.join("other-pid", "lobby", "other-key", json.null())
  let assert Ok(local) = state.merge(state.new("observer"), raw)
  let assert Ok(local) = state.merge(local, current)
  let assert Ok(local) = state.merge(local, malformed)
  let assert Ok(local) = state.merge(local, other)

  list.each([#(raw, current), #(current, raw)], fn(selection) {
    let #(selected, retired) = selection
    let assert Ok(#(cleaned, diff)) =
      state.supersede(local, state.replica(selected))
    state.internal_values(cleaned)
    |> expect.to_equal(
      dict.filter(state.internal_values(local), fn(tag, _) {
        tag.replica != state.replica(retired)
      }),
    )
    let assert [#(pid, topic, key, meta)] = state.online_list(retired)
    diff
    |> expect.to_equal(state.Diff(
      joins: dict.new(),
      leaves: dict.from_list([#(topic, [#(key, pid, meta)])]),
    ))
  })
}

pub fn supersede_rejects_retiring_local_writer_in_all_liveness_states_test() {
  let empty = state.new_incarnation("node")
  let populated =
    state.join(empty, "local-pid", "lobby", "local-key", json.null())
  let local_replica = state.replica(empty)
  let #(empty_down, _) = state.replica_down(empty, local_replica)
  let #(populated_down, _) = state.replica_down(populated, local_replica)
  let empty_pruned = state.remove_down_replica(empty_down, local_replica)
  let populated_pruned =
    state.remove_down_replica(populated_down, local_replica)
  let current = state.new_incarnation("node") |> state.replica

  list.each(
    [
      empty,
      populated,
      empty_down,
      populated_down,
      empty_pruned,
      populated_pruned,
    ],
    fn(local) {
      list.each([current, "node"], fn(current_replica) {
        state.supersede(local, current_replica)
        |> expect.to_equal(
          Error(state.CannotSupersedeLocalReplica(
            local_replica: local_replica,
            current_replica: current_replica,
          )),
        )
      })
    },
  )
}

pub fn supersede_allows_selecting_local_writer_without_relabeling_test() {
  let local =
    state.new_incarnation("node")
    |> state.join("local-pid", "lobby", "local-key", json.null())
  let local_replica = state.replica(local)
  let old = state.new_incarnation("node") |> state.replica
  let #(with_old_status, _) = state.replica_up(local, old)

  state.supersede(with_old_status, local_replica)
  |> expect.to_equal(
    Ok(#(local, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )
  let #(down, _) = state.replica_down(local, local_replica)
  let pruned = state.remove_down_replica(down, local_replica)
  list.each([local, down, pruned], fn(local) {
    let assert Ok(#(cleaned, diff)) = state.supersede(local, local_replica)
    cleaned |> expect.to_equal(local)
    diff |> expect.to_equal(state.Diff(joins: dict.new(), leaves: dict.new()))
    let joined =
      state.join(cleaned, "next-pid", "lobby", "next-key", json.null())
    dict.has_key(state.internal_values(joined), state.Tag(local_replica, 2))
    |> expect.to_equal(True)
  })
}

pub fn supersede_suppresses_covered_replay_but_not_unseen_higher_tags_test() {
  let old =
    state.new_incarnation("node")
    |> state.join("old-pid", "lobby", "old-key", json.null())
  let current = state.new_incarnation("node") |> state.replica
  let assert Ok(local) = state.merge(state.new("observer"), old)
  let assert Ok(#(cleaned, _)) = state.supersede(local, current)
  state.merge_with_diff(cleaned, old)
  |> expect.to_equal(
    Ok(#(cleaned, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )

  let still_writing =
    state.join(old, "higher-pid", "lobby", "higher-key", json.null())
  let assert Ok(replayed) = state.merge(cleaned, still_writing)
  state.get_by_topic(replayed, "lobby")
  |> expect.to_equal([#("higher-pid", "higher-key", json.null())])
  let assert Ok(#(cleaned_again, diff)) = state.supersede(replayed, current)
  state.entry_count(cleaned_again) |> expect.to_equal(0)
  dict.get(state.compacted_clocks(cleaned_again), state.replica(old))
  |> expect.to_equal(Ok(2))
  dict.get(diff.leaves, "lobby")
  |> expect.to_equal(Ok([#("higher-key", "higher-pid", json.null())]))
}

pub fn remove_down_replica_does_not_remove_live_replica_test() {
  let live =
    state.new("node1")
    |> state.join("pid_alice", "lobby", "alice", json.object([]))
  let assert Ok(local) = state.merge(state.new("node2"), live)

  let unchanged = state.remove_down_replica(local, "node1")

  state.online_list(unchanged) |> list.length |> expect.to_equal(1)
  state.entry_count(unchanged) |> expect.to_equal(1)
}

pub fn remove_down_replica_retains_cloud_high_water_test() {
  let assert Ok(stale) =
    state.from_json(
      "{\"replica\":\"node1\",\"context\":{\"node1\":1},\"clouds\":{\"node1\":[3]},\"values\":[
        {\"tag\":{\"replica\":\"node1\",\"clock\":3},\"entry\":{\"topic\":\"lobby\",\"key\":\"alice\",\"pid\":\"pid_alice\",\"meta\":{}}}
      ]}",
    )
  let assert Ok(local) = state.merge(state.new("node2"), stale)
  let #(local, _) = state.replica_down(local, "node1")
  let local = state.remove_down_replica(local, "node1")

  dict.get(state.compacted_clocks(local), "node1")
  |> expect.to_equal(Ok(3))

  let assert Ok(local) = state.merge(local, stale)
  state.entry_count(local) |> expect.to_equal(0)
}

// ── edge cases ───────────────────────────────────────────────────────

pub fn clocks_returns_vector_clock_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:1", "k1", json.object([]))
  let a = state.join(a, "p2", "room:1", "k2", json.object([]))

  let clocks = state.compacted_clocks(a)
  case dict.get(clocks, "node_a") {
    Ok(2) -> Nil
    _ -> panic as "expected failure"
  }
}

pub fn compact_reduces_clouds_test() {
  // After local joins, context should be fully compacted (no clouds)
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:1", "k1", json.object([]))
  let a = state.join(a, "p2", "room:1", "k2", json.object([]))

  let compacted = state.compact(a)
  case dict.get(state.internal_clouds(compacted), "node_a") {
    Ok(cloud) -> set.size(cloud) |> expect.to_equal(0)
    Error(_) -> Nil
  }
}

pub fn compact_prunes_stale_cloud_entries_before_folding_prefix_test() {
  let assert Ok(uncompact) =
    state.from_json(
      "{\"replica\":\"node_local\",\"context\":{\"node_remote\":3},\"clouds\":{\"node_remote\":[1,3,4,5,7]},\"values\":[]}",
    )

  let compacted = state.compact(uncompact)

  dict.get(state.compacted_clocks(compacted), "node_remote")
  |> expect.to_equal(Ok(5))
  dict.get(state.internal_clouds(compacted), "node_remote")
  |> expect.to_equal(Ok(set.from_list([7])))
}

pub fn compact_preserves_membership_through_full_state_merge_test() {
  let assert Ok(uncompact) =
    state.from_json(
      "{\"replica\":\"node_remote\",\"context\":{\"node_remote\":3},\"clouds\":{\"node_remote\":[1,3,4,5,7]},\"values\":[
        {\"tag\":{\"replica\":\"node_remote\",\"clock\":2},\"entry\":{\"topic\":\"lobby\",\"key\":\"alice\",\"pid\":\"pid-alice\",\"meta\":{}}},
        {\"tag\":{\"replica\":\"node_remote\",\"clock\":5},\"entry\":{\"topic\":\"lobby\",\"key\":\"bob\",\"pid\":\"pid-bob\",\"meta\":{}}},
        {\"tag\":{\"replica\":\"node_remote\",\"clock\":7},\"entry\":{\"topic\":\"lobby\",\"key\":\"carol\",\"pid\":\"pid-carol\",\"meta\":{}}}
      ]}",
    )

  let compacted = state.compact(uncompact)
  let assert Ok(received) =
    state.merge(state.new("node_receiver"), state.extract_full_state(compacted))

  state.get_by_topic(compacted, "lobby")
  |> list.length
  |> expect.to_equal(3)
  state.get_by_topic(received, "lobby") |> list.length |> expect.to_equal(3)
  state.get_by_key(received, "lobby", "alice")
  |> expect.to_equal([#("pid-alice", json.object([]))])
  state.get_by_key(received, "lobby", "bob")
  |> expect.to_equal([#("pid-bob", json.object([]))])
  state.get_by_key(received, "lobby", "carol")
  |> expect.to_equal([#("pid-carol", json.object([]))])
}

pub fn merge_with_empty_state_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:1", "k1", json.object([]))

  let empty = state.new("node_b")

  // Merging empty into non-empty should be a no-op
  let assert Ok(#(merged, diff)) = state.merge_with_diff(a, empty)
  state.get_by_topic(merged, "room:1") |> list.length |> expect.to_equal(1)
  dict.size(diff.joins) |> expect.to_equal(0)
  dict.size(diff.leaves) |> expect.to_equal(0)
}

pub fn get_by_key_multiple_pids_test() {
  let a = state.new("node_a")
  let a =
    state.join(
      a,
      "pid1",
      "room:lobby",
      "user:alice",
      json.object([
        #("device", json.string("desktop")),
      ]),
    )
  let a =
    state.join(
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
  let a = state.new("node_a")
  let a = state.join(a, "pid1", "room:lobby", "alice", json.object([]))
  let a = state.join(a, "pid1", "room:lobby", "bob", json.object([]))
  let a = state.leave(a, "pid1", "room:lobby", "alice")

  state.get_by_topic(a, "room:lobby") |> list.length |> expect.to_equal(1)
}

pub fn joins_propagate_through_intermediate_node_test() {
  // A -> B -> C chain: A's join should reach C via B
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:lobby", "alice", json.object([]))

  let b = state.new("node_b")
  let assert Ok(b) = state.merge(b, a)

  let c = state.new("node_c")
  let assert Ok(c) = state.merge(c, b)

  // C should see alice
  state.get_by_topic(c, "room:lobby") |> list.length |> expect.to_equal(1)
}

pub fn removes_propagate_through_intermediate_node_test() {
  // All three nodes sync, then A removes, propagate via B to C
  let a = state.new("node_a")
  let a = state.join(a, "p1", "room:lobby", "alice", json.object([]))

  let b = state.new("node_b")
  let assert Ok(b) = state.merge(b, a)

  let c = state.new("node_c")
  let assert Ok(c) = state.merge(c, b)

  // A removes alice
  let a = state.leave(a, "p1", "room:lobby", "alice")

  // Propagate: A -> B -> C
  let assert Ok(b) = state.merge(b, a)
  let assert Ok(c) = state.merge(c, b)

  state.get_by_topic(c, "room:lobby") |> expect.to_equal([])
}

/// Phoenix test: clocks advance correctly through merges
pub fn phoenix_clocks_advance_through_merge_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")

  let a = state.join(a, "p1", "lobby", "alice", json.object([]))
  let b = state.join(b, "p2", "lobby", "bob", json.object([]))

  let assert Ok(b) = state.merge(b, a)

  let clocks = state.compacted_clocks(b)
  case dict.get(clocks, "node_a") {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }
  case dict.get(clocks, "node_b") {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }

  // A leaves then rejoins — clock advances to 2
  let a = state.leave(a, "p1", "lobby", "alice")
  // leave doesn't advance clock, but re-join does:
  let a = state.join(a, "p1", "lobby", "alice", json.object([]))

  let assert Ok(b) = state.merge(b, a)
  case dict.get(state.compacted_clocks(b), "node_a") {
    Ok(2) -> Nil
    _ -> panic as "expected failure"
  }
}

/// All clouds should be empty after merge (fully compacted)
pub fn phoenix_clouds_empty_after_merge_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")

  let a = state.join(a, "p1", "lobby", "alice", json.object([]))
  let b = state.join(b, "p2", "lobby", "bob", json.object([]))

  let assert Ok(b) = state.merge(b, a)

  // All clouds should be compacted away
  dict.to_list(state.internal_clouds(b))
  |> list.all(fn(kv) {
    let #(_, cloud) = kv
    set.is_empty(cloud)
  })
  |> expect.to_be_true
}

pub fn merge_accepts_identical_same_replica_state_test() {
  let local =
    state.new("node_a")
    |> state.join("p1", "lobby", "alice", json.object([]))

  let assert Ok(merged) = state.merge(local, local)

  state.get_by_topic(merged, "lobby") |> list.length |> expect.to_equal(1)
  state.merge_with_diff(local, local)
  |> expect.to_equal(
    Ok(#(local, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )
}

pub fn merge_rejects_restart_echo_test() {
  let previous_incarnation =
    state.new("node_a")
    |> state.join("old-pid", "lobby", "alice", json.object([]))
  let restarted = state.new("node_a")

  case state.merge_with_diff(restarted, previous_incarnation) {
    Error(state.SameReplica(replica)) -> replica |> expect.to_equal("node_a")
    _ -> panic as "expected same-replica conflict"
  }
}

pub fn merge_rejects_restart_echo_via_peer_test() {
  let old =
    state.new("node_a")
    |> state.join("old-pid", "lobby", "alice", json.object([]))
  let assert Ok(peer) = state.merge(state.new("node_b"), old)

  state.merge(state.new("node_a"), peer)
  |> expect.to_equal(Error(state.SameReplica("node_a")))
}

pub fn merge_with_diff_rejects_restart_echo_via_peer_test() {
  let old =
    state.new("node_a")
    |> state.join("old-pid", "lobby", "alice", json.object([]))
  let assert Ok(peer) = state.merge(state.new("node_b"), old)

  state.merge_with_diff(state.new("node_a"), peer)
  |> expect.to_equal(Error(state.SameReplica("node_a")))
}

pub fn merge_rejects_removed_local_history_via_peer_test() {
  let local =
    state.new("node_a")
    |> state.join("pid", "lobby", "alice", json.object([]))
  let old =
    local
    |> state.join("pid", "lobby", "bob", json.object([]))
    |> state.leave_by_pid("pid")
  let assert Ok(peer) = state.merge(state.new("node_b"), old)
  state.entry_count(peer) |> expect.to_equal(0)

  // Both an empty restart and a writer with some activity lack clock 2.
  list.each([state.new("node_a"), local], fn(restarted) {
    expect_local_history_conflict(restarted, peer)
  })
}

pub fn merge_rejects_unseen_local_cloud_history_test() {
  let assert Ok(local) =
    state.from_json(
      "{\"replica\":\"node_a\",\"context\":{\"node_a\":1},\"clouds\":{\"node_a\":[5]},\"values\":[]}",
    )
  let assert Ok(peer) =
    state.from_json(
      "{\"replica\":\"node_b\",\"context\":{},\"clouds\":{\"node_a\":[3]},\"values\":[]}",
    )

  // Comparing only maximum clocks would miss this unseen clock in a gap.
  expect_local_history_conflict(local, peer)
}

pub fn merge_rejects_local_prefix_with_unseen_gap_test() {
  let assert Ok(local) =
    state.from_json(
      "{\"replica\":\"node_a\",\"context\":{\"node_a\":1},\"clouds\":{\"node_a\":[3]},\"values\":[]}",
    )
  let assert Ok(peer) =
    state.from_json(
      "{\"replica\":\"node_b\",\"context\":{\"node_a\":3},\"clouds\":{},\"values\":[]}",
    )

  // The prefix endpoint is known, but clock 2 is not.
  expect_local_history_conflict(local, peer)
}

pub fn merge_rejects_unseen_local_active_tag_without_context_test() {
  let assert Ok(peer) =
    state.from_json(
      "{\"replica\":\"node_b\",\"context\":{},\"clouds\":{},\"values\":[
        {\"tag\":{\"replica\":\"node_a\",\"clock\":1},\"entry\":{\"topic\":\"lobby\",\"key\":\"alice\",\"pid\":\"old-pid\",\"meta\":{}}}
      ]}",
    )

  // The wire format can carry values independently of context/clouds.
  expect_local_history_conflict(state.new("node_a"), peer)
}

pub fn merge_accepts_known_local_tags_via_peer_test() {
  let local =
    state.new("node_a")
    |> state.join("pid", "lobby", "alice", json.object([]))
  let assert Ok(peer) = state.merge(state.new("node_b"), local)

  list.each(
    [
      local,
      state.leave_by_pid(local, "pid"),
      state.join(local, "new-pid", "lobby", "bob", json.object([])),
    ],
    fn(current) {
      // Echoes of active or since-removed local tags are harmless.
      state.merge(current, peer) |> expect.to_equal(Ok(current))
      state.merge_with_diff(current, peer)
      |> expect.to_equal(
        Ok(#(current, state.Diff(joins: dict.new(), leaves: dict.new()))),
      )
    },
  )
}

pub fn merge_accepts_local_history_covered_by_clouds_test() {
  let assert Ok(local) =
    state.from_json(
      "{\"replica\":\"node_a\",\"context\":{\"node_a\":1},\"clouds\":{\"node_a\":[2,3,5]},\"values\":[]}",
    )
  let assert Ok(peer) =
    state.from_json(
      "{\"replica\":\"node_b\",\"context\":{\"node_a\":3},\"clouds\":{\"node_a\":[1,5]},\"values\":[]}",
    )
  let expected = state.compact(local)

  state.merge(local, peer) |> expect.to_equal(Ok(expected))
  state.merge_with_diff(local, peer)
  |> expect.to_equal(
    Ok(#(expected, state.Diff(joins: dict.new(), leaves: dict.new()))),
  )
}

fn expect_local_history_conflict(local: state.State, peer: state.State) {
  state.merge(local, peer)
  |> expect.to_equal(Error(state.SameReplica("node_a")))
  state.merge_with_diff(local, peer)
  |> expect.to_equal(Error(state.SameReplica("node_a")))
}

pub fn merge_rejects_duplicate_node_name_test() {
  let first =
    state.new("duplicate")
    |> state.join("pid-1", "lobby", "alice", json.object([]))
  let second =
    state.new("duplicate")
    |> state.join("pid-2", "lobby", "bob", json.object([]))

  case state.merge(first, second) {
    Error(state.SameReplica(replica)) -> replica |> expect.to_equal("duplicate")
    _ -> panic as "expected same-replica conflict"
  }
}
