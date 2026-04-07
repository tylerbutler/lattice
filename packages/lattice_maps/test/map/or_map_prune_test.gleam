import gleam/list
import gleam/set
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_maps/crdt.{CrdtGCounter, GCounterSpec}
import lattice_maps/or_map
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn inc(c: crdt.Crdt, amount: Int) -> crdt.Crdt {
  case c {
    CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, amount))
    _ -> c
  }
}

// --- Basic value compaction ---

pub fn prune_removes_value_for_removed_key_test() {
  // Add "x", then remove it, then prune with a stable vector covering the add.
  // After prune, the internal value for "x" should be garbage collected.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(stable)

  // Key should remain invisible
  or_map.get(m, "x") |> expect.to_equal(Error(Nil))
  or_map.keys(m) |> expect.to_equal([])
  or_map.values(m) |> expect.to_equal([])
}

pub fn prune_preserves_active_key_values_test() {
  // Active keys must survive pruning — only removed keys get compacted.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("active", fn(c) { inc(c, 3) })
    |> or_map.update("removed", fn(c) { inc(c, 7) })
    |> or_map.remove("removed")
    |> or_map.prune(stable)

  // Active key still accessible with correct value
  case or_map.get(m, "active") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(3)
    _ -> expect.to_be_true(False)
  }

  // Removed key is gone
  or_map.get(m, "removed") |> expect.to_equal(Error(Nil))
  or_map.keys(m) |> expect.to_equal(["active"])
}

pub fn prune_compacts_multiple_removed_keys_test() {
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
  // Before and after prune, get/keys/values should return the same results.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("keep", fn(c) { inc(c, 10) })
    |> or_map.update("drop", fn(c) { inc(c, 20) })
    |> or_map.remove("drop")

  let pruned = or_map.prune(m, stable)

  // Same keys
  or_map.keys(m)
  |> set.from_list
  |> expect.to_equal(or_map.keys(pruned) |> set.from_list)

  // Same get results
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

  // Should have a fresh default value (1), not the old one (100)
  case or_map.get(m, "x") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(1)
    _ -> expect.to_be_true(False)
  }
}

// --- Multi-replica scenario ---

pub fn prune_after_multi_replica_merge_test() {
  // A and B both add keys, B removes one, merge, then prune.
  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("shared", fn(c) { inc(c, 3) })

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("shared", fn(c) { inc(c, 7) })
    |> or_map.update("b_only", fn(c) { inc(c, 1) })

  let merged = or_map.merge(map_a, map_b)
  let merged = or_map.remove(merged, "b_only")

  // Stable vector covering all events from both replicas
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))
    |> version_vector.increment(rid("B"))

  let pruned = or_map.prune(merged, stable)

  // "shared" should survive with merged value (3 + 7 = 10)
  case or_map.get(pruned, "shared") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }

  // "b_only" should be gone
  or_map.get(pruned, "b_only") |> expect.to_equal(Error(Nil))
}

// --- Merge after prune uses remote value ---

pub fn merge_after_prune_uses_remote_value_test() {
  // A adds and removes "x", prunes it (value gone).
  // B concurrently adds "x" with a different tag.
  // After merge, "x" should be present with B's value.
  let map_a =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")
    |> or_map.prune(
      version_vector.new() |> version_vector.increment(rid("A")),
    )

  let map_b =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })

  let merged = or_map.merge(map_a, map_b)

  // B's concurrent add wins (add-wins semantics)
  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(99)
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
