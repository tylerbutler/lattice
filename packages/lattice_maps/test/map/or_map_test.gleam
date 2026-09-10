import gleam/list
import gleam/set
import gleam/string
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt.{
  CrdtGCounter, CrdtLwwRegister, GCounterSpec, GSetSpec, LwwRegisterSpec,
  OrSetSpec,
}
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_sets/g_set
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// --- new() tests ---

pub fn new_get_missing_key_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  or_map.get(m, "any")
  |> expect.to_equal(Error(Nil))
}

pub fn new_keys_empty_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  or_map.keys(m)
  |> expect.to_equal([])
}

pub fn new_values_empty_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  or_map.values(m)
  |> expect.to_equal([])
}

// --- update() tests ---

pub fn update_auto_creates_crdt_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) =
    or_map.update(m, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 5)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  case or_map.get(m, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(5)
    _ -> expect.to_be_true(False)
  }
}

pub fn update_modifies_existing_value_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) =
    or_map.update(m, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 3)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let assert Ok(m) =
    or_map.update(m, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 7)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  case or_map.get(m, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }
}

pub fn update_adds_key_to_keys_list_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) = or_map.update(m, "score", fn(c) { c })
  let assert Ok(m) = or_map.update(m, "name", fn(c) { c })
  or_map.keys(m)
  |> list.sort(string.compare)
  |> expect.to_equal(["name", "score"])
}

pub fn update_key_appears_in_values_test() {
  let m = or_map.new(rid("A"), GSetSpec)
  let assert Ok(m) =
    or_map.update(m, "tags", fn(c) {
      case c {
        crdt.CrdtGSet(s) -> crdt.CrdtGSet(g_set.add(s, "hello"))
        _ -> c
      }
    })
  let vals = or_map.values(m)
  list.length(vals) |> expect.to_equal(1)
}

pub fn update_with_delta_rejects_wrong_value_type_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let result =
    or_map.update_with_delta(m, "score", fn(_) { crdt.CrdtGSet(g_set.new()) })

  result
  |> expect.to_equal(Error(crdt.TypeMismatch("g_counter", "g_set")))
}

pub fn update_with_delta_delta_converges_without_callback_supplied_delta_test() {
  let local = or_map.new(rid("A"), GCounterSpec)
  let remote = or_map.new(rid("B"), GCounterSpec)
  let assert Ok(#(local, delta)) =
    or_map.update_with_delta(local, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 5)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })

  let assert Ok(via_delta) = or_map.apply_delta(remote, delta)
  let assert Ok(via_full) = or_map.merge(remote, local)

  or_map.get(via_delta, "score")
  |> expect.to_equal(or_map.get(via_full, "score"))
}

// --- get() tests ---

pub fn get_returns_ok_for_active_key_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) = or_map.update(m, "x", fn(c) { c })
  case or_map.get(m, "x") {
    Ok(_) -> expect.to_be_true(True)
    Error(_) -> expect.to_be_true(False)
  }
}

// --- remove() tests ---

pub fn remove_makes_key_invisible_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) = or_map.update(m, "score", fn(c) { c })
  let m = or_map.remove(m, "score")
  or_map.get(m, "score")
  |> expect.to_equal(Error(Nil))
}

pub fn remove_excludes_key_from_keys_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) = or_map.update(m, "a", fn(c) { c })
  let assert Ok(m) = or_map.update(m, "b", fn(c) { c })
  let m = or_map.remove(m, "a")
  or_map.keys(m)
  |> expect.to_equal(["b"])
}

pub fn remove_excludes_from_values_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) =
    or_map.update(m, "a", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 1)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let assert Ok(m) =
    or_map.update(m, "b", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 2)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let m = or_map.remove(m, "a")
  // Only "b" value should remain
  or_map.values(m)
  |> list.length
  |> expect.to_equal(1)
}

pub fn re_add_after_remove_works_test() {
  // OR-Set semantics: update after remove re-adds the key
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) = or_map.update(m, "x", fn(c) { c })
  let m = or_map.remove(m, "x")
  let assert Ok(m) = or_map.update(m, "x", fn(c) { c })
  case or_map.get(m, "x") {
    Ok(_) -> expect.to_be_true(True)
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn re_add_after_remove_resets_value_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) =
    or_map.update(m, "count", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 5)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let m = or_map.remove(m, "count")
  let assert Ok(m) =
    or_map.update(m, "count", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 1)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })

  case or_map.get(m, "count") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(1)
    _ -> expect.to_be_true(False)
  }
}

// --- keys() and values() tests ---

pub fn keys_returns_only_active_keys_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) = or_map.update(m, "a", fn(c) { c })
  let assert Ok(m) = or_map.update(m, "b", fn(c) { c })
  let assert Ok(m) = or_map.update(m, "c", fn(c) { c })
  let m = or_map.remove(m, "b")
  or_map.keys(m)
  |> set.from_list
  |> expect.to_equal(set.from_list(["a", "c"]))
}

pub fn values_returns_only_active_values_test() {
  let m = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(m) = or_map.update(m, "a", fn(c) { c })
  let assert Ok(m) = or_map.update(m, "b", fn(c) { c })
  let m = or_map.remove(m, "b")
  or_map.values(m)
  |> list.length
  |> expect.to_equal(1)
}

// --- merge() tests ---

pub fn merge_disjoint_keys_test() {
  let map_a = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(map_a) = or_map.update(map_a, "x", fn(c) { c })
  let map_b = or_map.new(rid("B"), GCounterSpec)
  let assert Ok(map_b) = or_map.update(map_b, "y", fn(c) { c })
  let assert Ok(merged) = or_map.merge(map_a, map_b)
  or_map.keys(merged)
  |> set.from_list
  |> expect.to_equal(set.from_list(["x", "y"]))
}

pub fn merge_nested_values_combined_test() {
  let map_a = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(map_a) =
    or_map.update(map_a, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 3)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let map_b = or_map.new(rid("B"), GCounterSpec)
  let assert Ok(map_b) =
    or_map.update(map_b, "score", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 7)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let assert Ok(merged) = or_map.merge(map_a, map_b)
  case or_map.get(merged, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_lww_register_unicode_order_test() {
  let assert Ok(bmp) =
    or_map.new(rid("\u{e000}"), LwwRegisterSpec)
    |> or_map.update("name", fn(value) {
      let assert CrdtLwwRegister(register) = value
      CrdtLwwRegister(lww_register.set(register, "bmp value", 5))
    })
  let assert Ok(supplementary) =
    or_map.new(rid("\u{10000}"), LwwRegisterSpec)
    |> or_map.update("name", fn(value) {
      let assert CrdtLwwRegister(register) = value
      CrdtLwwRegister(lww_register.set(register, "supplementary value", 5))
    })

  list.each(
    [or_map.merge(bmp, supplementary), or_map.merge(supplementary, bmp)],
    fn(result) {
      let assert Ok(merged) = result
      or_map.keys(merged) |> expect.to_equal(["name"])
      let assert Ok(CrdtLwwRegister(register)) = or_map.get(merged, "name")
      lww_register.value(register) |> expect.to_equal("supplementary value")
      lww_register.replica_id(register) |> expect.to_equal(rid("\u{10000}"))
      lww_register.timestamp(register) |> expect.to_equal(5)
    },
  )
}

pub fn merge_preserves_active_keys_from_both_sides_test() {
  let map_a = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(map_a) = or_map.update(map_a, "alpha", fn(c) { c })
  let assert Ok(map_a) = or_map.update(map_a, "beta", fn(c) { c })
  let map_b = or_map.new(rid("B"), GCounterSpec)
  let assert Ok(map_b) = or_map.update(map_b, "beta", fn(c) { c })
  let assert Ok(map_b) = or_map.update(map_b, "gamma", fn(c) { c })
  let assert Ok(merged) = or_map.merge(map_a, map_b)
  or_map.keys(merged)
  |> set.from_list
  |> expect.to_equal(set.from_list(["alpha", "beta", "gamma"]))
}

// --- concurrent update-wins scenario (add-wins semantics) ---

pub fn concurrent_update_wins_over_remove_test() {
  // Scenario:
  // 1. A adds key "x" with increment
  let map_a = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(map_a) =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 1)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })

  // 2. B syncs with A then removes "x"
  let assert Ok(map_b) = or_map.merge(or_map.new(rid("B"), GCounterSpec), map_a)
  let map_b = or_map.remove(map_b, "x")

  // 3. A concurrently updates "x" again (new tag not seen by B's remove)
  let assert Ok(map_a) =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 1)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })

  // 4. Merge: A's concurrent update should win (add-wins from OR-Set)
  let assert Ok(merged) = or_map.merge(map_a, map_b)

  // "x" should still be present
  case or_map.get(merged, "x") {
    Ok(_) -> expect.to_be_true(True)
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn merge_add_wins_keys_in_or_set_test() {
  // Direct test: after concurrent update vs remove, key is in keys()
  let map_a = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(map_a) =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 1)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })

  let assert Ok(map_b) = or_map.merge(or_map.new(rid("B"), GCounterSpec), map_a)
  let map_b = or_map.remove(map_b, "x")

  let assert Ok(map_a) =
    or_map.update(map_a, "x", fn(c) {
      case c {
        CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 1)
          CrdtGCounter(counter)
        }
        _ -> c
      }
    })

  let assert Ok(merged) = or_map.merge(map_a, map_b)

  // Use keys() to check "x" is present (active in OR-Set)
  or_map.keys(merged)
  |> list.any(fn(k) { k == "x" })
  |> expect.to_be_true
}

pub fn update_rejects_mismatch_for_absent_key_test() {
  let map = or_map.new(rid("A"), GCounterSpec)

  or_map.update(map, "x", fn(_) { crdt.CrdtGSet(g_set.new()) })
  |> expect.to_equal(Error(crdt.TypeMismatch("g_counter", "g_set")))
  map |> expect.to_equal(or_map.new(rid("A"), GCounterSpec))
  or_map.keys(map) |> expect.to_equal([])
  or_map.get(map, "x") |> expect.to_equal(Error(Nil))
}

pub fn update_rejects_mismatch_for_existing_key_test() {
  let assert Ok(counter) = g_counter.increment(g_counter.new(rid("A")), 7)
  let assert Ok(map) =
    or_map.update(or_map.new(rid("A"), GCounterSpec), "x", fn(_) {
      CrdtGCounter(counter)
    })
  let original = map
  let wrong_type = fn(_) { crdt.CrdtGSet(g_set.new()) }

  or_map.update(map, "x", wrong_type)
  |> expect.to_equal(Error(crdt.TypeMismatch("g_counter", "g_set")))
  or_map.update_with_delta(map, "x", wrong_type)
  |> expect.to_equal(Error(crdt.TypeMismatch("g_counter", "g_set")))
  map |> expect.to_equal(original)
  or_map.get(map, "x") |> expect.to_equal(Ok(CrdtGCounter(counter)))
}

pub fn update_rejects_mismatch_for_removed_key_test() {
  let assert Ok(map) =
    or_map.update(or_map.new(rid("A"), GCounterSpec), "x", fn(c) { c })
  let map = or_map.remove(map, "x")
  let original = map
  let wrong_type = fn(_) { crdt.CrdtGSet(g_set.new()) }

  or_map.update(map, "x", wrong_type)
  |> expect.to_equal(Error(crdt.TypeMismatch("g_counter", "g_set")))
  or_map.update_with_delta(map, "x", wrong_type)
  |> expect.to_equal(Error(crdt.TypeMismatch("g_counter", "g_set")))
  map |> expect.to_equal(original)
  or_map.keys(map) |> expect.to_equal([])
  or_map.get(map, "x") |> expect.to_equal(Error(Nil))
  or_map.internal_value_count(map) |> expect.to_equal(1)
}

pub fn update_state_and_delta_agree_for_all_key_states_test() {
  let absent = or_map.new(rid("A"), GCounterSpec)
  let increment = fn(c) {
    let assert CrdtGCounter(counter) = c
    let assert Ok(counter) = g_counter.increment(counter, 3)
    CrdtGCounter(counter)
  }
  let assert Ok(existing) = or_map.update(absent, "x", increment)
  let removed = or_map.remove(existing, "x")

  list.each([#(absent, 3), #(existing, 6), #(removed, 3)], fn(pair) {
    let #(map, expected) = pair
    let assert Ok(updated) = or_map.update(map, "x", increment)
    let assert Ok(#(with_delta, delta)) =
      or_map.update_with_delta(map, "x", increment)
    updated |> expect.to_equal(with_delta)
    let assert Ok(CrdtGCounter(counter)) = or_map.get(updated, "x")
    g_counter.value(counter) |> expect.to_equal(expected)
    let remote = or_map.new(rid("B"), GCounterSpec)
    let assert Ok(via_delta) = or_map.apply_delta(remote, delta)
    let assert Ok(via_full) = or_map.merge(remote, updated)
    or_map.keys(via_delta) |> expect.to_equal(or_map.keys(via_full))
    or_map.get(via_delta, "x") |> expect.to_equal(or_map.get(via_full, "x"))
  })
}

pub fn merge_rejects_maps_with_different_specs_test() {
  let counters = or_map.new(rid("A"), GCounterSpec)
  let sets = or_map.new(rid("B"), GSetSpec)

  case or_map.merge(counters, sets) {
    Error(crdt.TypeMismatch(expected: "g_counter", found: "g_set")) ->
      expect.to_be_true(True)
    _ -> expect.to_be_true(False)
  }
}

// --- keys() via public API ---

pub fn keys_contains_added_key_test() {
  // Verify keys are accessible via the public keys() API
  let m = or_map.new(rid("A"), OrSetSpec)
  let assert Ok(m2) = or_map.update(m, "key1", fn(c) { c })
  or_map.keys(m2)
  |> list.any(fn(k) { k == "key1" })
  |> expect.to_be_true
}
