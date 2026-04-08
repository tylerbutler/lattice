import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_counters/pn_counter
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_registers/mv_register
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// -- Cross-package smoke tests --
// Verify that all sub-packages can be imported together and that types
// compose correctly across package boundaries.

pub fn cross_package_imports_compile_test() {
  // Create one instance of every CRDT type
  let _vv = version_vector.new()
  let _gc = g_counter.new(rid("a"))
  let _pn = pn_counter.new(rid("a"))
  let _lww = lww_register.new("hello", 1, rid("a"))
  let _mv = mv_register.new(rid("a"))
  let _gs = g_set.new()
  let _tp = two_p_set.new()
  let _os = or_set.new(rid("a"))
  let _lm = lww_map.new()
  let _om = or_map.new(rid("a"), crdt.GCounterSpec)

  // If we got here, all packages import and construct successfully
  expect.to_be_true(True)
}

pub fn or_map_with_g_counter_cross_package_test() {
  // Create an ORMap holding GCounter values across package boundaries
  let map_a =
    or_map.new(rid("node-a"), crdt.GCounterSpec)
    |> or_map.update("score", fn(c) {
      let assert crdt.CrdtGCounter(gc) = c
      crdt.CrdtGCounter(g_counter.increment(gc, 10))
    })

  let map_b =
    or_map.new(rid("node-b"), crdt.GCounterSpec)
    |> or_map.update("score", fn(c) {
      let assert crdt.CrdtGCounter(gc) = c
      crdt.CrdtGCounter(g_counter.increment(gc, 5))
    })

  let assert Ok(merged) = or_map.merge(map_a, map_b)
  let assert Ok(crdt.CrdtGCounter(gc)) = or_map.get(merged, "score")

  // Both increments should be preserved after merge
  g_counter.value(gc)
  |> expect.to_equal(15)
}

pub fn crdt_dispatch_merge_heterogeneous_test() {
  // Verify the dispatch module correctly merges same-type CRDTs
  let a = crdt.CrdtGCounter(g_counter.new(rid("a")) |> g_counter.increment(3))
  let b = crdt.CrdtGCounter(g_counter.new(rid("b")) |> g_counter.increment(7))
  let assert Ok(merged) = crdt.merge(a, b)

  let assert crdt.CrdtGCounter(gc) = merged
  g_counter.value(gc)
  |> expect.to_equal(10)
}

pub fn version_vector_used_by_mv_register_test() {
  // MVRegister depends on version_vector from lattice_core
  let reg_a =
    mv_register.new(rid("a"))
    |> mv_register.set("hello")

  let reg_b =
    mv_register.new(rid("b"))
    |> mv_register.set("world")

  let merged = mv_register.merge(reg_a, reg_b)

  // Concurrent writes should both appear
  let vals = mv_register.value(merged)
  expect.to_be_true(vals == ["hello", "world"] || vals == ["world", "hello"])
}

pub fn lww_register_replica_id_tiebreak_test() {
  // Verify commutative merge from lattice_registers works
  let a = lww_register.new("alice", 5, rid("node-a"))
  let b = lww_register.new("bob", 5, rid("node-b"))

  let merged_ab = lww_register.merge(a, b)
  let merged_ba = lww_register.merge(b, a)

  // Merge should be commutative even with equal timestamps
  expect.to_equal(lww_register.value(merged_ab), lww_register.value(merged_ba))
}

pub fn or_set_add_remove_merge_test() {
  // Verify OR-Set from lattice_sets works in integration
  let set_a =
    or_set.new(rid("a"))
    |> or_set.add("x")
    |> or_set.add("y")

  let set_b =
    or_set.new(rid("b"))
    |> or_set.add("y")
    |> or_set.add("z")

  let merged = or_set.merge(set_a, set_b)
  expect.to_be_true(or_set.contains(merged, "x"))
  expect.to_be_true(or_set.contains(merged, "y"))
  expect.to_be_true(or_set.contains(merged, "z"))
}
