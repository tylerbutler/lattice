import gleam/list
import gleam/set
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_maps/crdt.{type Crdt, CrdtGCounter, GCounterSpec}
import lattice_maps/or_map

fn rid(id: String) {
  replica_id.new(id)
}

fn inc(c: Crdt(String), amount: Int) -> Crdt(String) {
  case c {
    CrdtGCounter(counter) -> {
      let assert Ok(counter) = g_counter.increment(counter, amount)
      CrdtGCounter(counter)
    }
    _ -> c
  }
}

// --- Removed values stay available for future merges ---

pub fn prune_with_unstable_remove_preserves_future_merge_value_test() {
  // No A events are causally stable yet, so pruning must not change future merge results.
  let assert Ok(removed) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let removed = or_map.remove(removed, "x")

  let pruned = or_map.prune(removed, version_vector.new())

  let assert Ok(concurrent) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged_unpruned) = or_map.merge(removed, concurrent)
  let assert Ok(merged_pruned) = or_map.merge(pruned, concurrent)

  or_map.keys(merged_pruned)
  |> set.from_list
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == or_map.keys(merged_unpruned) |> set.from_list
  }

  or_map.get(merged_pruned, "x")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.get(merged_unpruned, "x")
  }

  case or_map.get(merged_pruned, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 104
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn prune_preserves_active_key_values_test() {
  // Active keys must survive pruning.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("active", fn(c) { inc(c, 3) })
  let assert Ok(m) = or_map.update(m, "removed", fn(c) { inc(c, 7) })
  let m =
    or_map.remove(m, "removed")
    |> or_map.prune(stable)

  case or_map.get(m, "active") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 3
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }

  or_map.get(m, "removed")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
  or_map.keys(m)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ["active"]
  }
}

pub fn prune_keeps_only_active_keys_observable_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("a", fn(c) { inc(c, 1) })
  let assert Ok(m) = or_map.update(m, "b", fn(c) { inc(c, 2) })
  let assert Ok(m) = or_map.update(m, "c", fn(c) { inc(c, 3) })
  let m =
    or_map.remove(m, "a")
    |> or_map.remove("c")
    |> or_map.prune(stable)

  or_map.keys(m)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ["b"]
  }
  or_map.values(m)
  |> list.length
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
}

// --- Idempotency ---

pub fn prune_is_idempotent_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 1) })
  let m = or_map.remove(m, "x")

  let pruned_once = or_map.prune(m, stable)
  let pruned_twice = or_map.prune(pruned_once, stable)

  or_map.keys(pruned_once)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.keys(pruned_twice)
  }
  or_map.values(pruned_once)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.values(pruned_twice)
  }
}

// --- Observable state unchanged ---

pub fn prune_does_not_change_observable_state_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("keep", fn(c) { inc(c, 10) })
  let assert Ok(m) = or_map.update(m, "drop", fn(c) { inc(c, 20) })
  let m = or_map.remove(m, "drop")

  let pruned = or_map.prune(m, stable)

  or_map.keys(m)
  |> set.from_list
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.keys(pruned) |> set.from_list
  }

  or_map.get(m, "keep")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.get(pruned, "keep")
  }
  or_map.get(m, "drop")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.get(pruned, "drop")
  }
}

// --- Re-add after prune ---

pub fn re_add_after_prune_creates_fresh_value_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 100) })
  let assert Ok(m) =
    or_map.remove(m, "x")
    |> or_map.prune(stable)
    |> or_map.update("x", fn(c) { inc(c, 1) })

  case or_map.get(m, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 1
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

// --- Multi-replica scenario ---

pub fn prune_after_multi_replica_merge_test() {
  let assert Ok(map_a) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("shared", fn(c) { inc(c, 3) })

  let assert Ok(map_b) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("shared", fn(c) { inc(c, 7) })
  let assert Ok(map_b) = or_map.update(map_b, "b_only", fn(c) { inc(c, 1) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)
  let merged = or_map.remove(merged, "b_only")

  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))
    |> version_vector.increment(rid("B"))

  let pruned = or_map.prune(merged, stable)

  case or_map.get(pruned, "shared") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 10
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }

  or_map.get(pruned, "b_only")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
}

// --- Merge after prune preserves retained values ---

pub fn merge_after_noop_prune_preserves_removed_value_test() {
  let assert Ok(map_a) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let map_a =
    or_map.remove(map_a, "x")
    |> or_map.prune(version_vector.new())

  let assert Ok(map_b) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 104
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

// --- Edge case: prune on empty map ---

pub fn prune_on_empty_map_is_noop_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m = or_map.new(rid("A"), GCounterSpec) |> or_map.prune(stable)

  or_map.keys(m)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  or_map.values(m)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
}

// --- Current-generation history retention (issue #17) ---

pub fn prune_retains_current_generation_history_when_removal_is_stable_test() {
  // Stable membership does not authorize deleting the leaf baseline.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let m =
    or_map.remove(m, "x")
    |> or_map.prune(stable)

  // "x" is not observable
  or_map.get(m, "x")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
  or_map.internal_value_count(m)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
}

pub fn prune_does_not_compact_when_removal_is_unstable_test() {
  // A adds "x" (tag A:1), removes "x", prunes with empty VV
  // The value must be retained for future merge
  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let m =
    or_map.remove(m, "x")
    |> or_map.prune(version_vector.new())

  // "x" is not observable but value is retained
  or_map.get(m, "x")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
  or_map.internal_value_count(m)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }

  // Merge with concurrent add should give 104
  let assert Ok(concurrent) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })
  let assert Ok(merged) = or_map.merge(m, concurrent)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 104
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn issue_17_divergence_scenario_test() {
  // Exact scenario from the issue:
  // 1. A updates "x" with value 5 then removes "x"
  // 2. A prunes with VV that doesn't cover B's events
  // 3. B concurrently updates "x" with value 99
  // 4. After merge, "x" should be present with value 104

  let assert Ok(map_a) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let map_a = or_map.remove(map_a, "x")

  // Prune with VV that only covers A:1 — doesn't say anything about B
  let stable_a_only =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let map_a = or_map.prune(map_a, stable_a_only)

  let assert Ok(map_b) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  // "x" is present (add-wins)
  or_map.keys(merged)
  |> set.from_list
  |> fn(assertion_actual) {
    let assert True = assertion_actual == set.from_list(["x"])
  }

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 104
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn issue_17_unstable_prune_preserves_merge_value_test() {
  // Same as above but prune with empty VV — nothing is stable
  // Value must be retained and merge gives 104
  let assert Ok(map_a) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let map_a =
    or_map.remove(map_a, "x")
    |> or_map.prune(version_vector.new())

  let assert Ok(map_b) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 104
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn merge_after_membership_prune_retains_both_leaf_values_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(map_a) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let map_a =
    or_map.remove(map_a, "x")
    |> or_map.prune(stable)

  let assert Ok(map_b) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 42) })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 47
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn both_sides_pruned_key_absent_test() {
  let stable_a =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let stable_b =
    version_vector.new()
    |> version_vector.increment(rid("B"))

  let assert Ok(map_a) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let map_a =
    or_map.remove(map_a, "x")
    |> or_map.prune(stable_a)

  let assert Ok(map_b) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 10) })
  let map_b =
    or_map.remove(map_b, "x")
    |> or_map.prune(stable_b)

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  or_map.keys(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  or_map.get(merged, "x")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
}

pub fn re_add_after_membership_prune_starts_fresh_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 100) })
  let assert Ok(m) =
    or_map.remove(m, "x")
    |> or_map.prune(stable)
    |> or_map.update("x", fn(c) { inc(c, 1) })

  // A new generation starts from default, not the retained old value.
  case or_map.get(m, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 1
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }

  // The superseded payload is discarded; only the winning generation remains.
  or_map.internal_value_count(m)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
}

pub fn prune_idempotent_with_retained_history_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let m =
    or_map.remove(m, "x")
    |> or_map.prune(stable)

  let pruned_again = or_map.prune(m, stable)

  or_map.keys(pruned_again)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.keys(m)
  }
  or_map.internal_value_count(pruned_again)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == or_map.internal_value_count(m)
  }
}
