import gleam/list
import gleam/set
import gleam/string
import lattice/lww_map
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
