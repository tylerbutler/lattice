import gleam/list
import gleam/set
import gleam/string
import lattice/crdt.{CrdtGCounter, GCounterSpec, GSetSpec, OrSetSpec}
import lattice/g_counter
import lattice/g_set
import lattice/or_map
import lattice/or_set
import startest/expect

// --- new() tests ---

pub fn new_get_missing_key_test() {
  let m = or_map.new("A", GCounterSpec)
  or_map.get(m, "any")
  |> expect.to_equal(Error(Nil))
}

pub fn new_keys_empty_test() {
  let m = or_map.new("A", GCounterSpec)
  or_map.keys(m)
  |> expect.to_equal([])
}

pub fn new_values_empty_test() {
  let m = or_map.new("A", GCounterSpec)
  or_map.values(m)
  |> expect.to_equal([])
}

// --- update() tests ---

pub fn update_auto_creates_crdt_test() {
  let m = or_map.new("A", GCounterSpec)
  let m =
    or_map.update(m, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 5))
        _ -> c
      }
    })
  case or_map.get(m, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(5)
    _ -> expect.to_be_true(False)
  }
}

pub fn update_modifies_existing_value_test() {
  let m = or_map.new("A", GCounterSpec)
  let m =
    or_map.update(m, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 3))
        _ -> c
      }
    })
  let m =
    or_map.update(m, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 7))
        _ -> c
      }
    })
  case or_map.get(m, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }
}

pub fn update_adds_key_to_keys_list_test() {
  let m = or_map.new("A", GCounterSpec)
  let m =
    or_map.update(m, "score", fn(c) { c })
    |> or_map.update("name", fn(c) { c })
  or_map.keys(m)
  |> list.sort(string.compare)
  |> expect.to_equal(["name", "score"])
}

pub fn update_key_appears_in_values_test() {
  let m = or_map.new("A", GSetSpec)
  let m =
    or_map.update(m, "tags", fn(c) {
      case c {
        crdt.CrdtGSet(s) -> crdt.CrdtGSet(g_set.add(s, "hello"))
        _ -> c
      }
    })
  let vals = or_map.values(m)
  list.length(vals) |> expect.to_equal(1)
}

// --- get() tests ---

pub fn get_returns_ok_for_active_key_test() {
  let m = or_map.new("A", GCounterSpec)
  let m = or_map.update(m, "x", fn(c) { c })
  case or_map.get(m, "x") {
    Ok(_) -> expect.to_be_true(True)
    Error(_) -> expect.to_be_true(False)
  }
}

// --- remove() tests ---

pub fn remove_makes_key_invisible_test() {
  let m = or_map.new("A", GCounterSpec)
  let m = or_map.update(m, "score", fn(c) { c })
  let m = or_map.remove(m, "score")
  or_map.get(m, "score")
  |> expect.to_equal(Error(Nil))
}

pub fn remove_excludes_key_from_keys_test() {
  let m = or_map.new("A", GCounterSpec)
  let m =
    or_map.update(m, "a", fn(c) { c })
    |> or_map.update("b", fn(c) { c })
    |> or_map.remove("a")
  or_map.keys(m)
  |> expect.to_equal(["b"])
}

pub fn remove_excludes_from_values_test() {
  let m = or_map.new("A", GCounterSpec)
  let m =
    or_map.update(m, "a", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 1))
        _ -> c
      }
    })
    |> or_map.update("b", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 2))
        _ -> c
      }
    })
    |> or_map.remove("a")
  // Only "b" value should remain
  or_map.values(m)
  |> list.length
  |> expect.to_equal(1)
}

pub fn re_add_after_remove_works_test() {
  // OR-Set semantics: update after remove re-adds the key
  let m = or_map.new("A", GCounterSpec)
  let m = or_map.update(m, "x", fn(c) { c })
  let m = or_map.remove(m, "x")
  let m = or_map.update(m, "x", fn(c) { c })
  case or_map.get(m, "x") {
    Ok(_) -> expect.to_be_true(True)
    Error(_) -> expect.to_be_true(False)
  }
}

// --- keys() and values() tests ---

pub fn keys_returns_only_active_keys_test() {
  let m = or_map.new("A", GCounterSpec)
  let m =
    or_map.update(m, "a", fn(c) { c })
    |> or_map.update("b", fn(c) { c })
    |> or_map.update("c", fn(c) { c })
    |> or_map.remove("b")
  or_map.keys(m)
  |> set.from_list
  |> expect.to_equal(set.from_list(["a", "c"]))
}

pub fn values_returns_only_active_values_test() {
  let m = or_map.new("A", GCounterSpec)
  let m =
    or_map.update(m, "a", fn(c) { c })
    |> or_map.update("b", fn(c) { c })
    |> or_map.remove("b")
  or_map.values(m)
  |> list.length
  |> expect.to_equal(1)
}

// --- merge() tests ---

pub fn merge_disjoint_keys_test() {
  let map_a = or_map.new("A", GCounterSpec)
  let map_a = or_map.update(map_a, "x", fn(c) { c })
  let map_b = or_map.new("B", GCounterSpec)
  let map_b = or_map.update(map_b, "y", fn(c) { c })
  let merged = or_map.merge(map_a, map_b)
  or_map.keys(merged)
  |> set.from_list
  |> expect.to_equal(set.from_list(["x", "y"]))
}

pub fn merge_nested_values_combined_test() {
  let map_a = or_map.new("A", GCounterSpec)
  let map_a =
    or_map.update(map_a, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 3))
        _ -> c
      }
    })
  let map_b = or_map.new("B", GCounterSpec)
  let map_b =
    or_map.update(map_b, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 7))
        _ -> c
      }
    })
  let merged = or_map.merge(map_a, map_b)
  case or_map.get(merged, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_preserves_active_keys_from_both_sides_test() {
  let map_a = or_map.new("A", GCounterSpec)
  let map_a =
    or_map.update(map_a, "alpha", fn(c) { c })
    |> or_map.update("beta", fn(c) { c })
  let map_b = or_map.new("B", GCounterSpec)
  let map_b =
    or_map.update(map_b, "beta", fn(c) { c })
    |> or_map.update("gamma", fn(c) { c })
  let merged = or_map.merge(map_a, map_b)
  or_map.keys(merged)
  |> set.from_list
  |> expect.to_equal(set.from_list(["alpha", "beta", "gamma"]))
}

// --- concurrent update-wins scenario (add-wins semantics) ---

pub fn concurrent_update_wins_over_remove_test() {
  // Scenario:
  // 1. A adds key "x" with increment
  let map_a = or_map.new("A", GCounterSpec)
  let map_a =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 1))
        _ -> c
      }
    })

  // 2. B syncs with A then removes "x"
  let map_b = or_map.merge(or_map.new("B", GCounterSpec), map_a)
  let map_b = or_map.remove(map_b, "x")

  // 3. A concurrently updates "x" again (new tag not seen by B's remove)
  let map_a =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 1))
        _ -> c
      }
    })

  // 4. Merge: A's concurrent update should win (add-wins from OR-Set)
  let merged = or_map.merge(map_a, map_b)

  // "x" should still be present
  case or_map.get(merged, "x") {
    Ok(_) -> expect.to_be_true(True)
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn merge_add_wins_keys_in_or_set_test() {
  // Direct test: after concurrent update vs remove, key is in keys()
  let map_a = or_map.new("A", GCounterSpec)
  let map_a =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 1))
        _ -> c
      }
    })

  let map_b = or_map.merge(or_map.new("B", GCounterSpec), map_a)
  let map_b = or_map.remove(map_b, "x")

  let map_a =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 1))
        _ -> c
      }
    })

  let merged = or_map.merge(map_a, map_b)

  // Use keys() to check "x" is present (active in OR-Set)
  or_map.keys(merged)
  |> list.any(fn(k) { k == "x" })
  |> expect.to_be_true
}

// --- OR-Set key access via or_set ---

pub fn key_set_can_be_accessed_directly_test() {
  // OR-Map exposes key_set field (non-opaque type)
  let m = or_map.new("A", OrSetSpec)
  let m2 = or_map.update(m, "key1", fn(c) { c })
  or_set.contains(m2.key_set, "key1")
  |> expect.to_be_true
}
