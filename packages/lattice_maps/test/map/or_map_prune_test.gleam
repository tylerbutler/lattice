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

  let merged_unpruned = or_map.merge(removed, concurrent)
  let merged_pruned = or_map.merge(pruned, concurrent)

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

  let merged = or_map.merge(map_a, map_b)
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

  let merged = or_map.merge(map_a, map_b)

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
