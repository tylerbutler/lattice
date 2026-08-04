import gleam/json
import gleam/set
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import qcheck
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

/// The workspace default. These ran at 10 cases, which is not enough sweep to
/// exercise the convergence laws they assert.
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 1000, max_retries: 3, seed: qcheck.seed(42))
}

// ---------------------------------------------------------------------------
// LWW-Map property tests
// ---------------------------------------------------------------------------

pub fn lww_map_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(1, 50),
      qcheck.bounded_int(51, 100),
      fn(ts_a, ts_b) { #(ts_a, ts_b) },
    ),
    fn(pair) {
      let #(ts_a, ts_b) = pair
      let map_a = lww_map.new() |> lww_map.set("key", "val_a", ts_a)
      let map_b = lww_map.new() |> lww_map.set("key", "val_b", ts_b)
      lww_map.get(lww_map.merge(map_a, map_b), "key")
      |> expect.to_equal(lww_map.get(lww_map.merge(map_b, map_a), "key"))
      Nil
    },
  )
}

pub fn lww_map_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 100), fn(ts) {
    let map = lww_map.new() |> lww_map.set("key", "val", ts)
    lww_map.get(lww_map.merge(map, map), "key")
    |> expect.to_equal(lww_map.get(map, "key"))
    Nil
  })
}

pub fn lww_map_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(1, 30),
      qcheck.bounded_int(31, 60),
      qcheck.bounded_int(61, 90),
      fn(ts_a, ts_b, ts_c) { #(ts_a, ts_b, ts_c) },
    ),
    fn(triple) {
      let #(ts_a, ts_b, ts_c) = triple
      let map_a = lww_map.new() |> lww_map.set("key", "val_a", ts_a)
      let map_b = lww_map.new() |> lww_map.set("key", "val_b", ts_b)
      let map_c = lww_map.new() |> lww_map.set("key", "val_c", ts_c)
      let merged1 = lww_map.merge(lww_map.merge(map_a, map_b), map_c)
      let merged2 = lww_map.merge(map_a, lww_map.merge(map_b, map_c))
      lww_map.get(merged1, "key")
      |> expect.to_equal(lww_map.get(merged2, "key"))
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// OR-Map property tests
// ---------------------------------------------------------------------------

fn increment_g_counter(crdt_val: crdt.Crdt, delta: Int) -> crdt.Crdt {
  case crdt_val {
    crdt.CrdtGCounter(gc) -> crdt.CrdtGCounter(g_counter.increment(gc, delta))
    other -> other
  }
}

pub fn or_map_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 10), qcheck.bounded_int(0, 10), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let map_a =
        or_map.new(rid("A"), crdt.GCounterSpec)
        |> or_map.update("x", increment_g_counter(_, a))
      let map_b =
        or_map.new(rid("B"), crdt.GCounterSpec)
        |> or_map.update("x", increment_g_counter(_, b))
      let assert Ok(merged_ab) = or_map.merge(map_a, map_b)
      let assert Ok(merged_ba) = or_map.merge(map_b, map_a)
      set.from_list(or_map.keys(merged_ab))
      |> expect.to_equal(set.from_list(or_map.keys(merged_ba)))
      Nil
    },
  )
}

pub fn or_map_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 10), fn(a) {
    let map =
      or_map.new(rid("A"), crdt.GCounterSpec)
      |> or_map.update("x", increment_g_counter(_, a))
    let assert Ok(merged) = or_map.merge(map, map)
    set.from_list(or_map.keys(merged))
    |> expect.to_equal(set.from_list(or_map.keys(map)))

    or_map.get(merged, "x")
    |> expect.to_equal(or_map.get(map, "x"))
    Nil
  })
}

pub fn or_map_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 10),
      qcheck.bounded_int(0, 10),
      qcheck.bounded_int(0, 10),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let map_a =
        or_map.new(rid("A"), crdt.GCounterSpec)
        |> or_map.update("x", increment_g_counter(_, a))
      let map_b =
        or_map.new(rid("B"), crdt.GCounterSpec)
        |> or_map.update("x", increment_g_counter(_, b))
      let map_c =
        or_map.new(rid("C"), crdt.GCounterSpec)
        |> or_map.update("x", increment_g_counter(_, c))

      let assert Ok(ab) = or_map.merge(map_a, map_b)
      let assert Ok(merged1) = or_map.merge(ab, map_c)
      let assert Ok(bc) = or_map.merge(map_b, map_c)
      let assert Ok(merged2) = or_map.merge(map_a, bc)

      set.from_list(or_map.keys(merged1))
      |> expect.to_equal(set.from_list(or_map.keys(merged2)))

      or_map.get(merged1, "x")
      |> expect.to_equal(or_map.get(merged2, "x"))
      Nil
    },
  )
}

// ----------------------------------------------------------------------------
// OR-Map delta property tests.
// Verify the δ-CRDT laws lift through ORMap composition.
// ----------------------------------------------------------------------------

fn inc_with_delta(n: Int) -> fn(crdt.Crdt) -> crdt.Crdt {
  fn(c) {
    let assert crdt.CrdtGCounter(gc) = c
    crdt.CrdtGCounter(g_counter.increment(gc, n))
  }
}

fn gc_value_for(map: or_map.ORMap, key: String) -> Int {
  case or_map.get(map, key) {
    Ok(crdt.CrdtGCounter(gc)) -> g_counter.value(gc)
    _ -> 0
  }
}

pub fn or_map_update_delta_correctness__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(1, 20), qcheck.bounded_int(1, 20), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(initial, n) = pair
      let map = or_map.new(rid("A"), crdt.GCounterSpec)
      let assert Ok(#(map_after_init, _)) =
        or_map.update_with_delta(map, "k", inc_with_delta(initial))
      let direct = or_map.update(map_after_init, "k", inc_with_delta(n))
      let assert Ok(#(_, delta)) =
        or_map.update_with_delta(map_after_init, "k", inc_with_delta(n))
      let assert Ok(via_delta) = or_map.apply_delta(map_after_init, delta)
      gc_value_for(via_delta, "k")
      |> expect.to_equal(gc_value_for(direct, "k"))
      Nil
    },
  )
}

pub fn or_map_delta_sufficiency_on_remote__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(1, 20),
      qcheck.bounded_int(1, 20),
      qcheck.bounded_int(1, 20),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(local_n, delta_n, remote_n) = triple
      // Local replica A: increment "k" by local_n, then emit a delta for
      // an additional increment of delta_n.
      let local0 = or_map.new(rid("A"), crdt.GCounterSpec)
      let assert Ok(#(local1, _)) =
        or_map.update_with_delta(local0, "k", inc_with_delta(local_n))
      let local_full = or_map.update(local1, "k", inc_with_delta(delta_n))
      let assert Ok(#(_, delta)) =
        or_map.update_with_delta(local1, "k", inc_with_delta(delta_n))
      // Remote replica B: independent increment of remote_n.
      let remote0 = or_map.new(rid("B"), crdt.GCounterSpec)
      let assert Ok(#(remote, _)) =
        or_map.update_with_delta(remote0, "k", inc_with_delta(remote_n))
      // Apply delta vs full state — should converge to same value.
      let assert Ok(via_delta) = or_map.apply_delta(remote, delta)
      let assert Ok(via_full) = or_map.merge(remote, local_full)
      gc_value_for(via_delta, "k")
      |> expect.to_equal(gc_value_for(via_full, "k"))
      Nil
    },
  )
}

pub fn or_map_remove_delta_on_remote__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 20), fn(n) {
    // Local: add "k", then remove "k", emit remove delta.
    let local0 = or_map.new(rid("A"), crdt.GCounterSpec)
    let assert Ok(#(local1, _)) =
      or_map.update_with_delta(local0, "k", inc_with_delta(n))
    let #(_, remove_delta) = or_map.remove_with_delta(local1, "k")
    // Remote: independently has the same key with its own value.
    let remote0 = or_map.new(rid("B"), crdt.GCounterSpec)
    let assert Ok(#(remote, _)) =
      or_map.update_with_delta(remote0, "k", inc_with_delta(5))
    // Concurrent add wins (add-wins): "k" must remain after applying
    // the remove delta because remote's add was concurrent.
    let assert Ok(merged) = or_map.apply_delta(remote, remove_delta)
    set.contains(set.from_list(or_map.keys(merged)), "k")
    |> expect.to_equal(True)
    Nil
  })
}

pub fn or_map_delta_idempotent_commutative__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 20), fn(n) {
    let s0 = or_map.new(rid("A"), crdt.GCounterSpec)
    let assert Ok(#(s1, d1)) =
      or_map.update_with_delta(s0, "x", inc_with_delta(n))
    let assert Ok(#(s2, d2)) =
      or_map.update_with_delta(s1, "y", inc_with_delta(n + 1))
    let assert Ok(#(s3, d3)) =
      or_map.update_with_delta(s2, "x", inc_with_delta(n + 2))
    let #(_s4, d4) = or_map.remove_with_delta(s3, "y")
    let fresh = or_map.new(rid("B"), crdt.GCounterSpec)
    // Apply scrambled and duplicated.
    let assert Ok(m1) = or_map.apply_delta(fresh, d3)
    let assert Ok(m2) = or_map.apply_delta(m1, d1)
    let assert Ok(m3) = or_map.apply_delta(m2, d4)
    let assert Ok(m4) = or_map.apply_delta(m3, d2)
    let assert Ok(m5) = or_map.apply_delta(m4, d1)
    let assert Ok(via_deltas) = or_map.apply_delta(m5, d3)
    // Same outcome must be reachable via merge of full state.
    let assert Ok(via_full) = or_map.merge(fresh, s3)
    let local_after_remove =
      or_map.update(s3, "y", fn(c) { c }) |> or_map.remove("y")
    let assert Ok(via_full_after_remove) =
      or_map.merge(fresh, local_after_remove)
    // x present in both; y removed in both
    set.contains(set.from_list(or_map.keys(via_deltas)), "x")
    |> expect.to_equal(True)
    set.contains(set.from_list(or_map.keys(via_deltas)), "y")
    |> expect.to_equal(False)
    gc_value_for(via_deltas, "x")
    |> expect.to_equal(gc_value_for(via_full_after_remove, "x"))
    // Silence unused warnings when the property holds via the asserts above.
    let _ = via_full
    Nil
  })
}

pub fn or_map_merge_deltas_equivalent__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 20), fn(n) {
    let s0 = or_map.new(rid("A"), crdt.GCounterSpec)
    let assert Ok(#(s1, d1)) =
      or_map.update_with_delta(s0, "x", inc_with_delta(n))
    let assert Ok(#(_s2, d2)) =
      or_map.update_with_delta(s1, "y", inc_with_delta(n + 1))
    let assert Ok(combined) = or_map.merge_deltas(d1, d2)
    let fresh = or_map.new(rid("B"), crdt.GCounterSpec)
    let assert Ok(via_combined) = or_map.apply_delta(fresh, combined)
    let assert Ok(step1) = or_map.apply_delta(fresh, d1)
    let assert Ok(via_individual) = or_map.apply_delta(step1, d2)
    gc_value_for(via_combined, "x")
    |> expect.to_equal(gc_value_for(via_individual, "x"))
    gc_value_for(via_combined, "y")
    |> expect.to_equal(gc_value_for(via_individual, "y"))
    Nil
  })
}

pub fn or_map_delta_json_round_trip__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 20), fn(n) {
    let s0 = or_map.new(rid("A"), crdt.GCounterSpec)
    let assert Ok(#(_, delta)) =
      or_map.update_with_delta(s0, "k", inc_with_delta(n))
    let encoded = or_map.delta_to_json(delta) |> json.to_string
    let assert Ok(decoded) = or_map.delta_from_json(encoded)
    let fresh = or_map.new(rid("B"), crdt.GCounterSpec)
    let assert Ok(applied_orig) = or_map.apply_delta(fresh, delta)
    let assert Ok(applied_decoded) = or_map.apply_delta(fresh, decoded)
    gc_value_for(applied_orig, "k")
    |> expect.to_equal(gc_value_for(applied_decoded, "k"))
    Nil
  })
}
