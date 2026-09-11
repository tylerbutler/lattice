import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_counters/pn_counter
import lattice_crdt
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_registers/mv_register
import lattice_sequence/sequence
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import lattice_text/text

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
  let _lm = lww_map.new(rid("a"), crdt.LwwRegisterSpec(""))
  let _om = or_map.new(rid("a"), crdt.GCounterSpec)

  // If we got here, all packages import and construct successfully
  Nil
}

pub fn or_map_with_g_counter_cross_package_test() {
  // Create an ORMap holding GCounter values across package boundaries
  let assert Ok(map_a) =
    or_map.new(rid("node-a"), crdt.GCounterSpec)
    |> or_map.update("score", fn(c) {
      let assert crdt.CrdtGCounter(gc) = c
      let assert Ok(gc) = g_counter.increment(gc, 10)
      crdt.CrdtGCounter(gc)
    })

  let assert Ok(map_b) =
    or_map.new(rid("node-b"), crdt.GCounterSpec)
    |> or_map.update("score", fn(c) {
      let assert crdt.CrdtGCounter(gc) = c
      let assert Ok(gc) = g_counter.increment(gc, 5)
      crdt.CrdtGCounter(gc)
    })

  let assert Ok(merged) = or_map.merge_as(map_a, map_b, rid("node-a"))
  let assert Ok(crdt.CrdtGCounter(gc)) = or_map.get(merged, "score")

  // Both increments should be preserved after merge
  g_counter.value(gc)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 15
  }
}

pub fn crdt_dispatch_merge_heterogeneous_test() {
  // Verify the dispatch module correctly merges same-type CRDTs
  let assert Ok(a) = g_counter.new(rid("a")) |> g_counter.increment(3)
  let assert Ok(b) = g_counter.new(rid("b")) |> g_counter.increment(7)
  let assert Ok(merged) =
    crdt.merge(crdt.CrdtGCounter(a), crdt.CrdtGCounter(b), rid("a"))

  let assert crdt.CrdtGCounter(gc) = merged
  g_counter.value(gc)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 10
  }
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
  let assert True = vals == ["hello", "world"] || vals == ["world", "hello"]
}

pub fn lww_register_replica_id_tiebreak_test() {
  // Verify commutative merge from lattice_registers works
  let a = lww_register.new("alice", 5, rid("node-a"))
  let b = lww_register.new("bob", 5, rid("node-b"))

  let merged_ab = lww_register.merge(a, b)
  let merged_ba = lww_register.merge(b, a)

  // Merge should be commutative even with equal timestamps
  let assert True =
    lww_register.value(merged_ab) == lww_register.value(merged_ba)
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
  let assert True = or_set.contains(merged, "x")
  let assert True = or_set.contains(merged, "y")
  let assert True = or_set.contains(merged, "z")
}

pub fn recursive_umbrella_types_compile_test() {
  let schema: lattice_crdt.CrdtSpec(Int) =
    crdt.OrMapSpec(crdt.LwwMapSpec(crdt.LwwRegisterSpec(0)))
  let value: lattice_crdt.Crdt(Int) = crdt.default_crdt(schema, rid("a"))
  let assert crdt.CrdtOrMap(map) = value
  let map: lattice_crdt.ORMap(Int) = map
  or_map.keys(map)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }

  let delta: lattice_crdt.CrdtDelta(Int) = crdt.NoChange(schema)
  crdt.is_empty_delta(delta)
  |> fn(value) {
    let assert True = value
  }
}

pub fn sequence_and_text_dispatch_cross_package_test() {
  let assert Ok(items) = sequence.new(rid("a")) |> sequence.insert(0, 42)
  let assert Ok(document) = text.new(rid("b")) |> text.insert(0, "hello")

  let items: lattice_crdt.Crdt(Int) = crdt.CrdtSequence(items)
  let document: lattice_crdt.Crdt(Int) = crdt.CrdtText(document)

  crdt.matches_spec(items, crdt.SequenceSpec)
  |> fn(value) {
    let assert True = value
  }
  crdt.matches_spec(document, crdt.TextSpec)
  |> fn(value) {
    let assert True = value
  }
}
