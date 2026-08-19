import crdt_generator
import gleam/dict
import gleam/json
import gleam/list
import gleam/set
import lattice_presence/presence_state as state
import lattice_presence/state_json
import qcheck
import startest/expect

// ═══════════════════════════════════════════════════════════════════
// CRDT Mathematical Invariants
// ═══════════════════════════════════════════════════════════════════

// ── Commutativity ───────────────────────────────────────────────────

/// merge(A, B) and merge(B, A) must produce the same online set
pub fn prop_merge_commutativity_test() {
  use #(ops_a, ops_b) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    crdt_generator.gen_ops_for("r2"),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)

  let ab = state.merge(a, b)
  let ba = state.merge(b, a)

  crdt_generator.online_ids(ab)
  |> expect.to_equal(crdt_generator.online_ids(ba))
}

// ── Associativity ───────────────────────────────────────────────────

/// merge(merge(A, B), C) == merge(A, merge(B, C))
pub fn prop_merge_associativity_test() {
  use #(ops_a, #(ops_b, ops_c)) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    qcheck.tuple2(
      crdt_generator.gen_ops_for("r2"),
      crdt_generator.gen_ops_for("r3"),
    ),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)
  let c = crdt_generator.apply_ops(state.new("r3"), ops_c)

  let ab = state.merge(a, b)
  let ab_c = state.merge(ab, c)

  let bc = state.merge(b, c)
  let a_bc = state.merge(a, bc)

  crdt_generator.online_ids(ab_c)
  |> expect.to_equal(crdt_generator.online_ids(a_bc))
}

// ── Idempotency ─────────────────────────────────────────────────────

/// merge(A, A) == A
pub fn prop_merge_idempotency_test() {
  use ops <- qcheck.given(crdt_generator.gen_ops_for("r1"))
  let s = crdt_generator.apply_ops(state.new("r1"), ops)

  let merged = state.merge(s, s)

  crdt_generator.online_ids(merged)
  |> expect.to_equal(crdt_generator.online_ids(s))
}

// ── Convergence ─────────────────────────────────────────────────────

/// All merge orderings of 3 replicas converge to the same state
pub fn prop_merge_convergence_test() {
  use #(ops_a, #(ops_b, ops_c)) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    qcheck.tuple2(
      crdt_generator.gen_ops_for("r2"),
      crdt_generator.gen_ops_for("r3"),
    ),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)
  let c = crdt_generator.apply_ops(state.new("r3"), ops_c)

  // Order 1: A merges B, then C
  let r1 = state.merge(a, b)
  let r1 = state.merge(r1, c)

  // Order 2: A merges C, then B
  let r2 = state.merge(a, c)
  let r2 = state.merge(r2, b)

  // Order 3: B merges A, then C
  let r3 = state.merge(b, a)
  let r3 = state.merge(r3, c)

  let ids1 = crdt_generator.online_ids(r1)
  let ids2 = crdt_generator.online_ids(r2)
  let ids3 = crdt_generator.online_ids(r3)

  ids1 |> expect.to_equal(ids2)
  ids2 |> expect.to_equal(ids3)
}

// ── Add-wins ────────────────────────────────────────────────────────

/// A concurrent add and remove of the same entry must resolve to present
pub fn prop_add_wins_test() {
  use #(topic, key, pid) <- qcheck.given(crdt_generator.gen_entry())

  // A adds the entry
  let a = state.new("r1") |> state.join(pid, topic, key, json.null())

  // B learns about it via merge
  let b = state.new("r2")
  let b = state.merge(b, a)

  // Concurrently: B removes it, A re-adds it (creating a new tag)
  let b = state.leave(b, pid, topic, key)
  let a = state.leave(a, pid, topic, key)
  let a = state.join(a, pid, topic, key, json.null())

  // Merge — the concurrent add should win
  let resolved = state.merge(b, a)

  state.get_by_topic(resolved, topic)
  |> list.length
  |> expect.to_equal(1)
}

// ── Monotonic clocks ────────────────────────────────────────────────

/// After merge, the vector clock is >= both inputs (clocks never go backwards)
pub fn prop_monotonic_clocks_test() {
  use #(ops_a, ops_b) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    crdt_generator.gen_ops_for("r2"),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)

  let a_clocks = state.compacted_clocks(a)
  let b_clocks = state.compacted_clocks(b)
  let merged = state.merge(a, b)
  let merged_clocks = state.compacted_clocks(merged)

  // Every clock in A should be <= the corresponding clock in merged
  let _ =
    dict.each(a_clocks, fn(replica, clock) {
      case dict.get(merged_clocks, replica) {
        Ok(merged_clock) -> expect.to_be_true(merged_clock >= clock)
        Error(_) -> panic as "expected failure"
      }
    })

  // Every clock in B should be <= the corresponding clock in merged
  dict.each(b_clocks, fn(replica, clock) {
    case dict.get(merged_clocks, replica) {
      Ok(merged_clock) -> expect.to_be_true(merged_clock >= clock)
      Error(_) -> panic as "expected failure"
    }
  })
}

// ── Compaction invariant ────────────────────────────────────────────

/// After merge, compact is a no-op (merge already compacts)
pub fn prop_compaction_invariant_test() {
  use #(ops_a, ops_b) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    crdt_generator.gen_ops_for("r2"),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)

  let merged = state.merge(a, b)
  let double_compacted = state.compact(merged)

  // Context should be identical
  state.compacted_clocks(merged)
  |> expect.to_equal(state.compacted_clocks(double_compacted))

  // Clouds should be identical
  state.internal_clouds(merged)
  |> expect.to_equal(state.internal_clouds(double_compacted))

  // Online set should be identical
  crdt_generator.online_ids(merged)
  |> expect.to_equal(crdt_generator.online_ids(double_compacted))
}

// ── Merge diff accuracy ─────────────────────────────────────────────

/// The diff returned by merge accurately reflects the actual state change
pub fn prop_merge_diff_accuracy_test() {
  use #(ops_a, ops_b) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    crdt_generator.gen_ops_for("r2"),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)

  let #(merged, diff) = state.merge_with_diff(a, b)
  let after_ids = crdt_generator.online_ids(merged)

  // All entries reported as joins must be present in the merged state
  let join_ids = crdt_generator.diff_entry_ids(diff.joins)
  let _ =
    set.each(join_ids, fn(id) { expect.to_be_true(set.contains(after_ids, id)) })

  // Entries reported as leaves (and not also as joins) must be absent
  let leave_ids = crdt_generator.diff_entry_ids(diff.leaves)
  let leave_only = set.difference(leave_ids, join_ids)
  set.each(leave_only, fn(id) {
    expect.to_be_false(set.contains(after_ids, id))
  })
}

// ═══════════════════════════════════════════════════════════════════
// Serialization Properties
// ═══════════════════════════════════════════════════════════════════

// ── Serialization roundtrip ─────────────────────────────────────────

/// decode(encode(S)) should merge identically with a third state as S does
pub fn prop_serialization_roundtrip_test() {
  use ops <- qcheck.given(crdt_generator.gen_ops_for("r1"))
  let s = crdt_generator.apply_ops(state.new("r1"), ops)

  let json_str = state_json.to_json_string(s)
  let assert Ok(decoded) = state_json.from_json(json_str)

  // Both original and decoded should merge identically with a third state
  let other = state.new("r2") |> state.join("p_x", "t_x", "k_x", json.null())

  let m1 = state.merge(s, other)
  let m2 = state.merge(decoded, other)

  crdt_generator.online_ids(m1)
  |> expect.to_equal(crdt_generator.online_ids(m2))
}

// ── Double roundtrip stability ──────────────────────────────────────

/// encode(decode(encode(S))) == encode(S) — serialization is stable
pub fn prop_double_roundtrip_stability_test() {
  use ops <- qcheck.given(crdt_generator.gen_ops_for("r1"))
  let s = crdt_generator.apply_ops(state.new("r1"), ops)

  let encoded1 = state_json.to_json_string(s)
  let assert Ok(decoded) = state_json.from_json(encoded1)
  let encoded2 = state_json.to_json_string(decoded)
  let assert Ok(decoded2) = state_json.from_json(encoded2)
  let encoded3 = state_json.to_json_string(decoded2)

  // Second and third encodings should be identical
  encoded2 |> expect.to_equal(encoded3)
}

// ═══════════════════════════════════════════════════════════════════
// Phoenix-Inspired Scenarios
// ═══════════════════════════════════════════════════════════════════

// ── Netsplit + heal ─────────────────────────────────────────────────

/// After netsplit and heal, merging should converge
pub fn prop_netsplit_heal_convergence_test() {
  use #(ops_a, ops_b) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    crdt_generator.gen_ops_for("r2"),
  ))

  // Initial sync
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)
  let a = state.merge(a, b)
  let b = state.merge(b, a)

  // Netsplit: both sides mark each other as down
  let #(a, _) = state.replica_down(a, "r2")
  let #(b, _) = state.replica_down(b, "r1")

  // Mutations during split
  let a = state.join(a, "pid_split_a", "lobby", "split_a", json.null())
  let b = state.join(b, "pid_split_b", "lobby", "split_b", json.null())

  // Heal: mark replicas back up and merge
  let #(a, _) = state.replica_up(a, "r2")
  let #(b, _) = state.replica_up(b, "r1")
  let a_final = state.merge(a, b)
  let b_final = state.merge(b, a)

  // Both sides should converge
  crdt_generator.online_ids(a_final)
  |> expect.to_equal(crdt_generator.online_ids(b_final))
}

// ── Rapid join/leave cycles ─────────────────────────────────────────

/// Rapid join/leave cycles on the same key should converge after merge
pub fn prop_rapid_join_leave_cycles_test() {
  use #(topic, key, pid) <- qcheck.given(crdt_generator.gen_entry())

  // A does rapid join/leave/join/leave/join cycles
  let a = state.new("r1")
  let a = state.join(a, pid, topic, key, json.null())
  let a = state.leave(a, pid, topic, key)
  let a = state.join(a, pid, topic, key, json.null())
  let a = state.leave(a, pid, topic, key)
  let a = state.join(a, pid, topic, key, json.null())

  // B does the same but ends with a leave
  let b = state.new("r2")
  let b = state.join(b, pid, topic, key, json.null())
  let b = state.leave(b, pid, topic, key)
  let b = state.join(b, pid, topic, key, json.null())
  let b = state.leave(b, pid, topic, key)

  // Merge both directions should converge
  let ab = state.merge(a, b)
  let ba = state.merge(b, a)

  crdt_generator.online_ids(ab)
  |> expect.to_equal(crdt_generator.online_ids(ba))

  // A's entry should survive (add-wins for concurrent add from A)
  state.get_by_topic(ab, topic) |> list.length |> expect.to_equal(1)
}

// ── Multi-round gossip convergence ──────────────────────────────────

/// After full gossip rounds, all 3 replicas converge
pub fn prop_gossip_convergence_test() {
  use #(ops_a, #(ops_b, ops_c)) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    qcheck.tuple2(
      crdt_generator.gen_ops_for("r2"),
      crdt_generator.gen_ops_for("r3"),
    ),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)
  let c = crdt_generator.apply_ops(state.new("r3"), ops_c)

  // Round 1: each replica merges one other
  let a = state.merge(a, b)
  let b = state.merge(b, c)
  let c = state.merge(c, a)

  // Round 2: complete the gossip
  let a = state.merge(a, c)
  let b = state.merge(b, a)
  let c = state.merge(c, b)

  // All three should have identical online sets
  let ids_a = crdt_generator.online_ids(a)
  let ids_b = crdt_generator.online_ids(b)
  let ids_c = crdt_generator.online_ids(c)

  ids_a |> expect.to_equal(ids_b)
  ids_b |> expect.to_equal(ids_c)
}

// ═══════════════════════════════════════════════════════════════════
// Lifecycle Operations
// ═══════════════════════════════════════════════════════════════════

// ── Replica down/up roundtrip ───────────────────────────────────────

/// down hides entries, up reveals them, values dict is unchanged
pub fn prop_replica_down_up_roundtrip_test() {
  use ops <- qcheck.given(crdt_generator.gen_ops_for("r1"))
  let a = crdt_generator.apply_ops(state.new("r1"), ops)
  let b = state.new("r2") |> state.join("p1", "t1", "k1", json.null())

  let a = state.merge(a, b)
  let values_before = state.internal_values(a)

  // Down hides r2's entries
  let #(a_down, _) = state.replica_down(a, "r2")
  let down_ids = crdt_generator.online_ids(a_down)
  expect.to_be_false(set.contains(down_ids, #("p1", "t1", "k1")))

  // Values dict is unchanged (entries still stored, just hidden)
  state.internal_values(a_down) |> expect.to_equal(values_before)

  // Up restores visibility
  let #(a_up, _) = state.replica_up(a_down, "r2")
  crdt_generator.online_ids(a_up)
  |> expect.to_equal(crdt_generator.online_ids(a))
}

// ── Remove-down-replicas permanence ─────────────────────────────────

/// After remove_down_replicas, re-merging can't bring entries back
pub fn prop_remove_down_replicas_permanent_test() {
  use ops <- qcheck.given(crdt_generator.gen_ops_for("r1"))
  let a = crdt_generator.apply_ops(state.new("r1"), ops)
  let b = state.new("r2") |> state.join("p1", "t1", "k1", json.null())

  // Sync, then down + remove
  let a = state.merge(a, b)
  let #(a, _) = state.replica_down(a, "r2")
  let a = state.remove_down_replica(a, "r2")

  // The retained high-water mark prevents lagging b from resurrecting r2.
  let r2_context = dict.get(state.compacted_clocks(a), "r2")
  r2_context |> expect.to_equal(Ok(1))
  let a = state.merge(a, b)

  // r2's entries are gone from values
  let r2_entries =
    dict.to_list(state.internal_values(a))
    |> list.filter(fn(kv) { { kv.0 }.replica == "r2" })
  list.length(r2_entries) |> expect.to_equal(0)
}

// ── Leave-by-pid completeness ───────────────────────────────────────

/// leave_by_pid removes all and only entries matching the pid
pub fn prop_leave_by_pid_completeness_test() {
  use #(ops, pid) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    crdt_generator.gen_pid(),
  ))
  let s = crdt_generator.apply_ops(state.new("r1"), ops)

  // Record entries NOT matching pid
  let non_pid_entries =
    state.online_list(s)
    |> list.filter(fn(entry) { { entry }.0 != pid })
    |> list.map(fn(e) { #({ e }.0, { e }.1, { e }.2) })
    |> set.from_list

  let after = state.leave_by_pid(s, pid)

  // No entries with the target pid should remain
  state.online_list(after)
  |> list.each(fn(entry) { expect.to_not_equal({ entry }.0, pid) })

  // All non-pid entries should still be present
  let remaining_ids =
    state.online_list(after)
    |> list.map(fn(e) { #({ e }.0, { e }.1, { e }.2) })
    |> set.from_list
  remaining_ids |> expect.to_equal(non_pid_entries)
}

// ── Extract-then-merge equivalence ──────────────────────────────────

/// merge(A, extract(B, ...)) produces the same online set as merge(A, B)
pub fn prop_extract_merge_equivalence_test() {
  use #(ops_a, ops_b) <- qcheck.given(qcheck.tuple2(
    crdt_generator.gen_ops_for("r1"),
    crdt_generator.gen_ops_for("r2"),
  ))
  let a = crdt_generator.apply_ops(state.new("r1"), ops_a)
  let b = crdt_generator.apply_ops(state.new("r2"), ops_b)

  let direct = state.merge(a, b)
  let extracted = state.extract_full_state(b)
  let via_extract = state.merge(a, extracted)

  crdt_generator.online_ids(direct)
  |> expect.to_equal(crdt_generator.online_ids(via_extract))
}
