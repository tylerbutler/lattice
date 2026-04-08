import gleam/list
import gleam/set
import gleam/string
import lattice_maps/lww_map
import startest/expect

// --- new() tests ---

pub fn new_get_missing_test() {
  let m = lww_map.new()
  lww_map.get(m, "any")
  |> expect.to_equal(Error(Nil))
}

pub fn new_keys_empty_test() {
  let m = lww_map.new()
  lww_map.keys(m)
  |> expect.to_equal([])
}

pub fn new_values_empty_test() {
  let m = lww_map.new()
  lww_map.values(m)
  |> expect.to_equal([])
}

// --- set() and get() tests ---

pub fn set_get_single_key_test() {
  let m = lww_map.new() |> lww_map.set("name", "Alice", 1)
  lww_map.get(m, "name")
  |> expect.to_equal(Ok("Alice"))
}

pub fn set_higher_timestamp_wins_test() {
  let m =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.set("name", "Bob", 5)
  lww_map.get(m, "name")
  |> expect.to_equal(Ok("Bob"))
}

pub fn set_lower_timestamp_rejected_test() {
  let m =
    lww_map.new()
    |> lww_map.set("name", "Bob", 5)
    |> lww_map.set("name", "Alice", 1)
  lww_map.get(m, "name")
  |> expect.to_equal(Ok("Bob"))
}

pub fn set_equal_timestamp_rejected_test() {
  // Equal timestamp: existing entry wins (not overwritten)
  let m =
    lww_map.new()
    |> lww_map.set("name", "Bob", 5)
    |> lww_map.set("name", "Alice", 5)
  lww_map.get(m, "name")
  |> expect.to_equal(Ok("Bob"))
}

// --- keys() and values() tests ---

pub fn keys_returns_all_active_test() {
  let m =
    lww_map.new()
    |> lww_map.set("a", "1", 1)
    |> lww_map.set("b", "2", 1)
    |> lww_map.set("c", "3", 1)
  lww_map.keys(m)
  |> list.sort(string.compare)
  |> expect.to_equal(["a", "b", "c"])
}

pub fn values_returns_all_active_test() {
  let m =
    lww_map.new()
    |> lww_map.set("a", "alpha", 1)
    |> lww_map.set("b", "beta", 1)
  lww_map.values(m)
  |> list.sort(string.compare)
  |> expect.to_equal(["alpha", "beta"])
}

// --- remove() tests ---

pub fn remove_makes_key_missing_test() {
  let m =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.remove("name", 10)
  lww_map.get(m, "name")
  |> expect.to_equal(Error(Nil))
}

pub fn remove_tombstone_higher_ts_wins_test() {
  // set at ts=5, remove at ts=10 — tombstone wins
  let m =
    lww_map.new()
    |> lww_map.set("name", "Alice", 5)
    |> lww_map.remove("name", 10)
  lww_map.get(m, "name")
  |> expect.to_equal(Error(Nil))
}

pub fn remove_lower_ts_rejected_test() {
  // set at ts=10, remove at ts=5 — set wins (higher ts)
  let m =
    lww_map.new()
    |> lww_map.set("name", "Alice", 10)
    |> lww_map.remove("name", 5)
  lww_map.get(m, "name")
  |> expect.to_equal(Ok("Alice"))
}

pub fn remove_excludes_from_keys_test() {
  let m =
    lww_map.new()
    |> lww_map.set("a", "1", 1)
    |> lww_map.set("b", "2", 1)
    |> lww_map.remove("a", 10)
  lww_map.keys(m)
  |> expect.to_equal(["b"])
}

pub fn remove_excludes_from_values_test() {
  let m =
    lww_map.new()
    |> lww_map.set("a", "alpha", 1)
    |> lww_map.set("b", "beta", 1)
    |> lww_map.remove("a", 10)
  lww_map.values(m)
  |> expect.to_equal(["beta"])
}

// --- merge() tests ---

pub fn merge_disjoint_keys_test() {
  let a = lww_map.new() |> lww_map.set("x", "1", 1)
  let b = lww_map.new() |> lww_map.set("y", "2", 1)
  let merged = lww_map.merge(a, b)
  lww_map.keys(merged)
  |> set.from_list
  |> expect.to_equal(set.from_list(["x", "y"]))
}

pub fn merge_overlapping_higher_ts_wins_test() {
  // a has key at ts=5, b has same key at ts=10 — b wins
  let a = lww_map.new() |> lww_map.set("key", "from_a", 5)
  let b = lww_map.new() |> lww_map.set("key", "from_b", 10)
  let merged = lww_map.merge(a, b)
  lww_map.get(merged, "key")
  |> expect.to_equal(Ok("from_b"))
}

pub fn merge_overlapping_first_wins_on_higher_ts_test() {
  // a has key at ts=10, b has same key at ts=5 — a wins
  let a = lww_map.new() |> lww_map.set("key", "from_a", 10)
  let b = lww_map.new() |> lww_map.set("key", "from_b", 5)
  let merged = lww_map.merge(a, b)
  lww_map.get(merged, "key")
  |> expect.to_equal(Ok("from_a"))
}

pub fn merge_tombstone_higher_ts_removes_test() {
  // a has set at ts=5; b has tombstone at ts=10 — tombstone wins in merged
  let a = lww_map.new() |> lww_map.set("key", "alive", 5)
  let b = lww_map.new() |> lww_map.remove("key", 10)
  let merged = lww_map.merge(a, b)
  lww_map.get(merged, "key")
  |> expect.to_equal(Error(Nil))
}

pub fn merge_tombstone_lower_ts_key_survives_test() {
  // a has set at ts=10; b has tombstone at ts=5 — set wins in merged
  let a = lww_map.new() |> lww_map.set("key", "alive", 10)
  let b = lww_map.new() |> lww_map.remove("key", 5)
  let merged = lww_map.merge(a, b)
  lww_map.get(merged, "key")
  |> expect.to_equal(Ok("alive"))
}

pub fn merge_equal_timestamp_uses_lexicographically_greater_value_test() {
  let a = lww_map.new() |> lww_map.set("key", "aaa", 10)
  let b = lww_map.new() |> lww_map.set("key", "bbb", 10)

  lww_map.get(lww_map.merge(a, b), "key")
  |> expect.to_equal(Ok("bbb"))
}

pub fn merge_equal_timestamp_is_commutative_test() {
  let a = lww_map.new() |> lww_map.set("key", "aaa", 10)
  let b = lww_map.new() |> lww_map.set("key", "bbb", 10)

  let merged_ab = lww_map.merge(a, b)
  let merged_ba = lww_map.merge(b, a)

  lww_map.get(merged_ab, "key")
  |> expect.to_equal(Ok("bbb"))
  lww_map.get(merged_ab, "key")
  |> expect.to_equal(lww_map.get(merged_ba, "key"))
}

pub fn merge_equal_timestamp_tombstone_wins_test() {
  let a = lww_map.new() |> lww_map.set("key", "alive", 10)
  let b = lww_map.new() |> lww_map.remove("key", 10)

  let merged_ab = lww_map.merge(a, b)
  let merged_ba = lww_map.merge(b, a)

  lww_map.get(merged_ab, "key")
  |> expect.to_equal(Error(Nil))
  lww_map.get(merged_ab, "key")
  |> expect.to_equal(lww_map.get(merged_ba, "key"))
}

pub fn merge_commutativity_test() {
  // merge(a, b) and merge(b, a) produce same value for active keys
  let a =
    lww_map.new()
    |> lww_map.set("x", "from_a", 10)
    |> lww_map.set("y", "shared", 5)
  let b =
    lww_map.new()
    |> lww_map.set("y", "shared", 5)
    |> lww_map.set("z", "from_b", 7)

  let merged_ab = lww_map.merge(a, b)
  let merged_ba = lww_map.merge(b, a)

  // Both should have same keys
  lww_map.keys(merged_ab)
  |> set.from_list
  |> expect.to_equal(set.from_list(lww_map.keys(merged_ba)))

  // Same values for each key
  lww_map.get(merged_ab, "x") |> expect.to_equal(lww_map.get(merged_ba, "x"))
  lww_map.get(merged_ab, "y") |> expect.to_equal(lww_map.get(merged_ba, "y"))
  lww_map.get(merged_ab, "z") |> expect.to_equal(lww_map.get(merged_ba, "z"))
}

pub fn tombstone_count_empty_test() {
  lww_map.new()
  |> lww_map.tombstone_count
  |> expect.to_equal(0)
}

pub fn tombstone_count_no_tombstones_test() {
  lww_map.new()
  |> lww_map.set("a", "1", 1)
  |> lww_map.set("b", "2", 2)
  |> lww_map.tombstone_count
  |> expect.to_equal(0)
}

pub fn tombstone_count_with_removals_test() {
  lww_map.new()
  |> lww_map.set("a", "1", 1)
  |> lww_map.set("b", "2", 2)
  |> lww_map.remove("a", 10)
  |> lww_map.tombstone_count
  |> expect.to_equal(1)
}

pub fn tombstone_count_remove_without_set_test() {
  // Removing a key that was never set still creates a tombstone
  lww_map.new()
  |> lww_map.remove("ghost", 5)
  |> lww_map.tombstone_count
  |> expect.to_equal(1)
}

// --- prune() tests ---

pub fn prune_removes_tombstones_at_or_below_threshold_test() {
  let m =
    lww_map.new()
    |> lww_map.remove("a", 5)
    |> lww_map.remove("b", 10)
    |> lww_map.remove("c", 15)
  let pruned = lww_map.prune(m, 10)
  // "a" (ts=5) and "b" (ts=10) pruned; "c" (ts=15) remains
  lww_map.tombstone_count(pruned)
  |> expect.to_equal(1)
}

pub fn prune_keeps_active_entries_test() {
  let m =
    lww_map.new()
    |> lww_map.set("alive", "yes", 3)
    |> lww_map.remove("dead", 5)
  let pruned = lww_map.prune(m, 10)
  lww_map.get(pruned, "alive")
  |> expect.to_equal(Ok("yes"))
  lww_map.tombstone_count(pruned)
  |> expect.to_equal(0)
}

pub fn prune_empty_map_test() {
  let pruned = lww_map.prune(lww_map.new(), 100)
  lww_map.keys(pruned)
  |> expect.to_equal([])
}

pub fn prune_with_zero_threshold_removes_nothing_test() {
  let m =
    lww_map.new()
    |> lww_map.remove("a", 1)
    |> lww_map.remove("b", 5)
  let pruned = lww_map.prune(m, 0)
  lww_map.tombstone_count(pruned)
  |> expect.to_equal(2)
}

pub fn prune_then_merge_no_zombie_when_synced_test() {
  // Both replicas have seen the remove — pruning is safe
  let a =
    lww_map.new()
    |> lww_map.set("key", "val", 5)
    |> lww_map.remove("key", 10)
  let b =
    lww_map.new()
    |> lww_map.set("key", "val", 5)
    |> lww_map.remove("key", 10)
  // Both synced, safe to prune
  let a_pruned = lww_map.prune(a, 10)
  let merged = lww_map.merge(a_pruned, b)
  lww_map.get(merged, "key")
  |> expect.to_equal(Error(Nil))
}

pub fn prune_preserves_merge_semantics_test() {
  // Pruning tombstones below threshold doesn't affect active entries in merge
  let a =
    lww_map.new()
    |> lww_map.set("x", "from_a", 10)
    |> lww_map.remove("old", 3)
  let b =
    lww_map.new()
    |> lww_map.set("y", "from_b", 7)
    |> lww_map.remove("old", 3)
  let a_pruned = lww_map.prune(a, 5)
  let merged = lww_map.merge(a_pruned, b)
  lww_map.get(merged, "x")
  |> expect.to_equal(Ok("from_a"))
  lww_map.get(merged, "y")
  |> expect.to_equal(Ok("from_b"))
}

pub fn prune_prevents_zombie_on_merge_test() {
  // Previously this was the zombie problem — now pruned_timestamp prevents it.
  let a =
    lww_map.new()
    |> lww_map.set("key", "val", 5)
    |> lww_map.remove("key", 10)

  // Replica b has NOT seen the remove — only the old set
  let b = lww_map.new() |> lww_map.set("key", "val", 5)

  // Prune: a prunes the tombstone, recording pruned_timestamp=10
  let a_pruned = lww_map.prune(a, 10)

  // Merge: b's old set at ts=5 ≤ pruned_timestamp=10 is a zombie — rejected
  let merged = lww_map.merge(a_pruned, b)
  lww_map.get(merged, "key")
  |> expect.to_equal(Error(Nil))
}

pub fn prune_allows_newer_entry_past_threshold_test() {
  // A pruned at ts=10, but B has a NEW set at ts=15 — this is legitimate
  let a =
    lww_map.new()
    |> lww_map.set("key", "val", 5)
    |> lww_map.remove("key", 10)
  let a_pruned = lww_map.prune(a, 10)

  let b = lww_map.new() |> lww_map.set("key", "updated", 15)

  let merged = lww_map.merge(a_pruned, b)
  lww_map.get(merged, "key")
  |> expect.to_equal(Ok("updated"))
}

pub fn pruned_timestamp_propagates_through_merge_test() {
  // After merge, pruned_timestamp should be max of both sides
  let a =
    lww_map.new()
    |> lww_map.remove("x", 10)
    |> lww_map.prune(10)
  let b =
    lww_map.new()
    |> lww_map.remove("y", 20)
    |> lww_map.prune(20)

  let merged = lww_map.merge(a, b)
  lww_map.pruned_timestamp(merged)
  |> expect.to_equal(20)
}

pub fn pruned_timestamp_default_is_zero_test() {
  lww_map.new()
  |> lww_map.pruned_timestamp
  |> expect.to_equal(0)
}

pub fn prune_is_monotonic_test() {
  // Pruning with a smaller threshold doesn't regress the pruned_timestamp
  let m =
    lww_map.new()
    |> lww_map.remove("a", 5)
    |> lww_map.prune(10)
    |> lww_map.prune(3)
  lww_map.pruned_timestamp(m)
  |> expect.to_equal(10)
}

pub fn prune_zombie_rejected_symmetrically_test() {
  // Zombie detection works regardless of merge argument order
  let a =
    lww_map.new()
    |> lww_map.set("key", "val", 5)
    |> lww_map.remove("key", 10)
    |> lww_map.prune(10)

  let b = lww_map.new() |> lww_map.set("key", "val", 5)

  // Both merge orders should reject the zombie
  lww_map.merge(a, b) |> lww_map.get("key") |> expect.to_equal(Error(Nil))
  lww_map.merge(b, a) |> lww_map.get("key") |> expect.to_equal(Error(Nil))
}
