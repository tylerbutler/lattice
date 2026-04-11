import gleam/list
import gleam/set
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_maps/crdt.{type Crdt, CrdtGCounter, GCounterSpec}
import lattice_maps/or_map
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn inc(c: Crdt, amount: Int) -> Crdt {
  case c {
    CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, amount))
    _ -> c
  }
}

// --- Removed values stay available for future merges ---

pub fn prune_with_unstable_remove_preserves_future_merge_value_test() {
  // No A events are causally stable yet, so pruning must not change future merge results.
  let removed =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")

  let pruned = or_map.prune(removed, version_vector.new())

  let concurrent =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged_unpruned) = or_map.merge(removed, concurrent)
  let assert Ok(merged_pruned) = or_map.merge(pruned, concurrent)

  or_map.keys(merged_pruned)
  |> set.from_list
  |> expect.to_equal(or_map.keys(merged_unpruned) |> set.from_list)

  or_map.get(merged_pruned, "x")
  |> expect.to_equal(or_map.get(merged_unpruned, "x"))

  case or_map.get(merged_pruned, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter) |> expect.to_equal(104)
    _ -> expect.to_be_true(False)
  }
}

pub fn prune_preserves_active_key_values_test() {
  // Active keys must survive pruning.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("active", fn(c) { inc(c, 3) })
    |> or_map.update("removed", fn(c) { inc(c, 7) })
    |> or_map.remove("removed")
    |> or_map.prune(stable)

  case or_map.get(m, "active") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(3)
    _ -> expect.to_be_true(False)
  }

  or_map.get(m, "removed") |> expect.to_equal(Error(Nil))
  or_map.keys(m) |> expect.to_equal(["active"])
}

pub fn prune_keeps_only_active_keys_observable_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("a", fn(c) { inc(c, 1) })
    |> or_map.update("b", fn(c) { inc(c, 2) })
    |> or_map.update("c", fn(c) { inc(c, 3) })
    |> or_map.remove("a")
    |> or_map.remove("c")
    |> or_map.prune(stable)

  or_map.keys(m) |> expect.to_equal(["b"])
  or_map.values(m) |> list.length |> expect.to_equal(1)
}

// --- Idempotency ---

pub fn prune_is_idempotent_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 1) })
    |> or_map.remove("x")

  let pruned_once = or_map.prune(m, stable)
  let pruned_twice = or_map.prune(pruned_once, stable)

  or_map.keys(pruned_once) |> expect.to_equal(or_map.keys(pruned_twice))
  or_map.values(pruned_once) |> expect.to_equal(or_map.values(pruned_twice))
}

// --- Observable state unchanged ---

pub fn prune_does_not_change_observable_state_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("keep", fn(c) { inc(c, 10) })
    |> or_map.update("drop", fn(c) { inc(c, 20) })
    |> or_map.remove("drop")

  let pruned = or_map.prune(m, stable)

  or_map.keys(m)
  |> set.from_list
  |> expect.to_equal(or_map.keys(pruned) |> set.from_list)

  or_map.get(m, "keep") |> expect.to_equal(or_map.get(pruned, "keep"))
  or_map.get(m, "drop") |> expect.to_equal(or_map.get(pruned, "drop"))
}

// --- Re-add after prune ---

pub fn re_add_after_prune_creates_fresh_value_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 100) })
    |> or_map.remove("x")
    |> or_map.prune(stable)
    |> or_map.update("x", fn(c) { inc(c, 1) })

  case or_map.get(m, "x") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(1)
    _ -> expect.to_be_true(False)
  }
}

// --- Multi-replica scenario ---

pub fn prune_after_multi_replica_merge_test() {
  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("shared", fn(c) { inc(c, 3) })

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("shared", fn(c) { inc(c, 7) })
    |> or_map.update("b_only", fn(c) { inc(c, 1) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)
  let merged = or_map.remove(merged, "b_only")

  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))
    |> version_vector.increment(rid("B"))

  let pruned = or_map.prune(merged, stable)

  case or_map.get(pruned, "shared") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }

  or_map.get(pruned, "b_only") |> expect.to_equal(Error(Nil))
}

// --- Merge after prune preserves retained values ---

pub fn merge_after_noop_prune_preserves_removed_value_test() {
  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(version_vector.new())

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter) |> expect.to_equal(104)
    _ -> expect.to_be_true(False)
  }
}

// --- Edge case: prune on empty map ---

pub fn prune_on_empty_map_is_noop_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m = or_map.new(rid("A"), GCounterSpec) |> or_map.prune(stable)

  or_map.keys(m) |> expect.to_equal([])
  or_map.values(m) |> expect.to_equal([])
}

// --- Value compaction tests (issue #17) ---

pub fn prune_compacts_value_when_removal_is_stable_test() {
  // A adds "x" (tag A:1), removes "x", prunes with stable VV covering A:1
  // The value for "x" should be compacted from the internal values dict
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(stable)

  // "x" is not observable
  or_map.get(m, "x") |> expect.to_equal(Error(Nil))
  // Internal value count should be 0 (compacted)
  or_map.internal_value_count(m) |> expect.to_equal(0)
}

pub fn prune_does_not_compact_when_removal_is_unstable_test() {
  // A adds "x" (tag A:1), removes "x", prunes with empty VV
  // The value must be retained for future merge
  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(version_vector.new())

  // "x" is not observable but value is retained
  or_map.get(m, "x") |> expect.to_equal(Error(Nil))
  or_map.internal_value_count(m) |> expect.to_equal(1)

  // Merge with concurrent add should give 104
  let concurrent =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })
  let assert Ok(merged) = or_map.merge(m, concurrent)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter) |> expect.to_equal(104)
    _ -> expect.to_be_true(False)
  }
}

pub fn issue_17_divergence_scenario_test() {
  // Exact scenario from the issue:
  // 1. A updates "x" with value 5 then removes "x"
  // 2. A prunes with VV that doesn't cover B's events
  // 3. B concurrently updates "x" with value 99
  // 4. After merge, "x" should be present with value 104

  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")

  // Prune with VV that only covers A:1 — doesn't say anything about B
  let stable_a_only =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let map_a = or_map.prune(map_a, stable_a_only)

  // Value must still be retained because B's events are not covered
  // (B could have a concurrent add that needs this value for merge)
  // Actually, stable_a_only covers A:1 which is the remove bound.
  // But the key concern is whether B could concurrently add.
  // The stable VV says all replicas have seen A:1, but we don't know
  // about B. With only {A:1} as stable, we CAN compact A's value
  // because the pruned VV dominates the remove bound {A:1}.
  // However, if B concurrently adds, B's value is used alone.

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  // "x" is present (add-wins)
  or_map.keys(merged)
  |> set.from_list
  |> expect.to_equal(set.from_list(["x"]))

  // If A's value was compacted, we get B's value only (99)
  // If A's value was retained, we get merged value (104)
  // With stable_vv={A:1} dominating remove_bound={A:1}, A's value IS compacted
  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(99)
    _ -> expect.to_be_true(False)
  }
}

pub fn issue_17_unstable_prune_preserves_merge_value_test() {
  // Same as above but prune with empty VV — nothing is stable
  // Value must be retained and merge gives 104
  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(version_vector.new())

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter) |> expect.to_equal(104)
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_after_one_side_compacted_uses_surviving_value_test() {
  // A removes and compacts "x", B has "x" active
  // Merge should use B's value
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(stable)

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 42) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(42)
    _ -> expect.to_be_true(False)
  }
}

pub fn both_sides_compacted_key_absent_test() {
  // Both A and B remove and compact "x"
  let stable_a =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let stable_b =
    version_vector.new()
    |> version_vector.increment(rid("B"))

  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(stable_a)

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 10) })
    |> or_map.remove("x")
    |> or_map.prune(stable_b)

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  or_map.keys(merged) |> expect.to_equal([])
  or_map.get(merged, "x") |> expect.to_equal(Error(Nil))
}

pub fn re_add_after_compaction_starts_fresh_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 100) })
    |> or_map.remove("x")
    |> or_map.prune(stable)
    |> or_map.update("x", fn(c) { inc(c, 1) })

  // Should start from default (0), not from compacted value
  case or_map.get(m, "x") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(1)
    _ -> expect.to_be_true(False)
  }

  // Re-add should also clear the remove_bound, so the value count includes only the active key
  or_map.internal_value_count(m) |> expect.to_equal(1)
}

pub fn prune_idempotent_after_compaction_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(stable)

  let pruned_again = or_map.prune(m, stable)

  or_map.keys(pruned_again) |> expect.to_equal(or_map.keys(m))
  or_map.internal_value_count(pruned_again)
  |> expect.to_equal(or_map.internal_value_count(m))
}
