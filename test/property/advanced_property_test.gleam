import gleam/int
import gleam/json
import gleam/list
import gleam/set
import lattice/crdt
import lattice/g_counter
import lattice/g_set
import lattice/lww_map
import lattice/lww_register
import lattice/mv_register
import lattice/or_map
import lattice/or_set
import lattice/pn_counter
import lattice/two_p_set
import qcheck
import startest/expect

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

// ---------------------------------------------------------------------------
// TEST-05: Bottom Identity
// merge(a, new()) preserves observable value(a) for all CRDT types
// ---------------------------------------------------------------------------

pub fn g_counter_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.small_non_negative_int(), fn(n) {
    let counter = g_counter.new("A") |> g_counter.increment(n)
    let bottom = g_counter.new("B")
    g_counter.value(g_counter.merge(counter, bottom))
    |> expect.to_equal(g_counter.value(counter))
    Nil
  })
}

pub fn pn_counter_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(-50, 50), fn(n) {
    let counter = case n >= 0 {
      True -> pn_counter.new("A") |> pn_counter.increment(n)
      False -> pn_counter.new("A") |> pn_counter.decrement(-n)
    }
    let bottom = pn_counter.new("B")
    pn_counter.value(pn_counter.merge(counter, bottom))
    |> expect.to_equal(pn_counter.value(counter))
    Nil
  })
}

pub fn lww_register_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(ts) {
    // Use ts+1 to ensure the register is always above bottom (ts=0)
    let reg = lww_register.new("value", ts + 1)
    let bottom = lww_register.new("", 0)
    lww_register.value(lww_register.merge(reg, bottom))
    |> expect.to_equal(lww_register.value(reg))
    Nil
  })
}

pub fn mv_register_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let reg = mv_register.new("A") |> mv_register.set(n)
    let bottom = mv_register.new("B")
    let merged_values =
      list.sort(mv_register.value(mv_register.merge(reg, bottom)), int.compare)
    let original_values = list.sort(mv_register.value(reg), int.compare)
    merged_values |> expect.to_equal(original_values)
    Nil
  })
}

pub fn g_set_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 20), fn(n) {
    let s = g_set.new() |> g_set.add(n)
    let bottom = g_set.new()
    g_set.value(g_set.merge(s, bottom))
    |> expect.to_equal(g_set.value(s))
    Nil
  })
}

pub fn two_p_set_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 20), fn(n) {
    let s = two_p_set.new() |> two_p_set.add(n)
    let bottom = two_p_set.new()
    two_p_set.value(two_p_set.merge(s, bottom))
    |> expect.to_equal(two_p_set.value(s))
    Nil
  })
}

pub fn or_set_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 20), fn(n) {
    let s = or_set.new("A") |> or_set.add(n)
    let bottom = or_set.new("B")
    or_set.value(or_set.merge(s, bottom))
    |> expect.to_equal(or_set.value(s))
    Nil
  })
}

pub fn lww_map_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 100), fn(ts) {
    let m = lww_map.new() |> lww_map.set("key", "value", ts)
    let bottom = lww_map.new()
    lww_map.get(lww_map.merge(m, bottom), "key")
    |> expect.to_equal(lww_map.get(m, "key"))
    Nil
  })
}

pub fn or_map_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.small_non_negative_int(), fn(_n) {
    let spec = crdt.GCounterSpec
    let m = or_map.new("A", spec) |> or_map.update("key", fn(c) { c })
    let bottom = or_map.new("B", spec)
    set.from_list(or_map.keys(or_map.merge(m, bottom)))
    |> expect.to_equal(set.from_list(or_map.keys(m)))
    Nil
  })
}

// ---------------------------------------------------------------------------
// TEST-06: Monotonicity / Inflation
// Values only increase (or stay the same) after merges
// ---------------------------------------------------------------------------

pub fn g_counter_monotonicity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let counter_a = g_counter.new("A") |> g_counter.increment(a)
      let counter_b = g_counter.new("B") |> g_counter.increment(b)
      let merged = g_counter.merge(counter_a, counter_b)
      let merged_val = g_counter.value(merged)
      { merged_val >= g_counter.value(counter_a) }
      |> expect.to_be_true()
      { merged_val >= g_counter.value(counter_b) }
      |> expect.to_be_true()
      Nil
    },
  )
}

pub fn pn_counter_monotonicity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 50), qcheck.bounded_int(0, 50), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let counter_a = pn_counter.new("A") |> pn_counter.increment(a)
      let counter_b = pn_counter.new("B") |> pn_counter.increment(b)
      let merged = pn_counter.merge(counter_a, counter_b)
      let merged_val = pn_counter.value(merged)
      { merged_val >= pn_counter.value(counter_a) }
      |> expect.to_be_true()
      { merged_val >= pn_counter.value(counter_b) }
      |> expect.to_be_true()
      Nil
    },
  )
}

pub fn g_set_monotonicity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 20), qcheck.bounded_int(0, 20), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let set_a = g_set.new() |> g_set.add(a)
      let set_b = g_set.new() |> g_set.add(b)
      let merged = g_set.merge(set_a, set_b)
      set.is_subset(g_set.value(set_a), g_set.value(merged))
      |> expect.to_be_true()
      set.is_subset(g_set.value(set_b), g_set.value(merged))
      |> expect.to_be_true()
      Nil
    },
  )
}

pub fn or_set_monotonicity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 20), qcheck.bounded_int(0, 20), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      // Add-only scenario: both inputs only add, no removes
      let set_a = or_set.new("A") |> or_set.add(a)
      let set_b = or_set.new("B") |> or_set.add(b)
      let merged = or_set.merge(set_a, set_b)
      set.is_subset(or_set.value(set_a), or_set.value(merged))
      |> expect.to_be_true()
      set.is_subset(or_set.value(set_b), or_set.value(merged))
      |> expect.to_be_true()
      Nil
    },
  )
}

pub fn lww_register_monotonicity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(ts_a, ts_b) = pair
      let reg_a = lww_register.new("val_a", ts_a)
      let reg_b = lww_register.new("val_b", ts_b)
      let merged = lww_register.merge(reg_a, reg_b)
      let merged_ts = merged.timestamp
      { merged_ts >= ts_a } |> expect.to_be_true()
      { merged_ts >= ts_b } |> expect.to_be_true()
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// TEST-04: Convergence (3-replica all-to-all exchange)
// After all-to-all merge, all replicas agree on the same value
// ---------------------------------------------------------------------------

pub fn g_counter_convergence__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      // 3 replicas with independent operations
      let ra = g_counter.new("A") |> g_counter.increment(a)
      let rb = g_counter.new("B") |> g_counter.increment(b)
      let rc = g_counter.new("C") |> g_counter.increment(c)
      // All-to-all merge: each replica merges with both others
      let ra_final = g_counter.merge(g_counter.merge(ra, rb), rc)
      let rb_final = g_counter.merge(g_counter.merge(rb, ra), rc)
      let rc_final = g_counter.merge(g_counter.merge(rc, ra), rb)
      g_counter.value(ra_final) |> expect.to_equal(g_counter.value(rb_final))
      g_counter.value(rb_final) |> expect.to_equal(g_counter.value(rc_final))
      Nil
    },
  )
}

pub fn pn_counter_convergence__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 30),
      qcheck.bounded_int(0, 30),
      qcheck.bounded_int(0, 30),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let ra = pn_counter.new("A") |> pn_counter.increment(a)
      let rb = pn_counter.new("B") |> pn_counter.increment(b)
      let rc = pn_counter.new("C") |> pn_counter.increment(c)
      let ra_final = pn_counter.merge(pn_counter.merge(ra, rb), rc)
      let rb_final = pn_counter.merge(pn_counter.merge(rb, ra), rc)
      let rc_final = pn_counter.merge(pn_counter.merge(rc, ra), rb)
      pn_counter.value(ra_final) |> expect.to_equal(pn_counter.value(rb_final))
      pn_counter.value(rb_final) |> expect.to_equal(pn_counter.value(rc_final))
      Nil
    },
  )
}

pub fn g_set_convergence__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let sa = g_set.new() |> g_set.add(a)
      let sb = g_set.new() |> g_set.add(b)
      let sc = g_set.new() |> g_set.add(c)
      let sa_final = g_set.merge(g_set.merge(sa, sb), sc)
      let sb_final = g_set.merge(g_set.merge(sb, sa), sc)
      let sc_final = g_set.merge(g_set.merge(sc, sa), sb)
      g_set.value(sa_final) |> expect.to_equal(g_set.value(sb_final))
      g_set.value(sb_final) |> expect.to_equal(g_set.value(sc_final))
      Nil
    },
  )
}

pub fn lww_register_convergence__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      // Use distinct timestamp ranges per replica to avoid tie-break issues
      qcheck.bounded_int(1, 30),
      qcheck.bounded_int(31, 60),
      qcheck.bounded_int(61, 90),
      fn(ts_a, ts_b, ts_c) { #(ts_a, ts_b, ts_c) },
    ),
    fn(triple) {
      let #(ts_a, ts_b, ts_c) = triple
      let ra = lww_register.new("val_a", ts_a)
      let rb = lww_register.new("val_b", ts_b)
      let rc = lww_register.new("val_c", ts_c)
      let ra_final = lww_register.merge(lww_register.merge(ra, rb), rc)
      let rb_final = lww_register.merge(lww_register.merge(rb, ra), rc)
      let rc_final = lww_register.merge(lww_register.merge(rc, ra), rb)
      lww_register.value(ra_final)
      |> expect.to_equal(lww_register.value(rb_final))
      lww_register.value(rb_final)
      |> expect.to_equal(lww_register.value(rc_final))
      Nil
    },
  )
}

pub fn lww_map_convergence__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      // Use distinct timestamp ranges per replica to avoid tie-break issues
      qcheck.bounded_int(1, 30),
      qcheck.bounded_int(31, 60),
      qcheck.bounded_int(61, 90),
      fn(ts_a, ts_b, ts_c) { #(ts_a, ts_b, ts_c) },
    ),
    fn(triple) {
      let #(ts_a, ts_b, ts_c) = triple
      let ma = lww_map.new() |> lww_map.set("key", "val_a", ts_a)
      let mb = lww_map.new() |> lww_map.set("key", "val_b", ts_b)
      let mc = lww_map.new() |> lww_map.set("key", "val_c", ts_c)
      let ma_final = lww_map.merge(lww_map.merge(ma, mb), mc)
      let mb_final = lww_map.merge(lww_map.merge(mb, ma), mc)
      let mc_final = lww_map.merge(lww_map.merge(mc, ma), mb)
      lww_map.get(ma_final, "key")
      |> expect.to_equal(lww_map.get(mb_final, "key"))
      lww_map.get(mb_final, "key")
      |> expect.to_equal(lww_map.get(mc_final, "key"))
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// TEST-09: OR-Set concurrent add-wins property
// Concurrent add always wins over remove in an OR-Set
// ---------------------------------------------------------------------------

pub fn or_set_concurrent_add_wins__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 20), fn(elem) {
    let elem_str = int.to_string(elem)
    // Step 1: replica_a adds element
    let replica_a = or_set.new("A") |> or_set.add(elem_str)
    // Step 2: replica_b syncs with a, then removes element
    let replica_b = or_set.merge(or_set.new("B"), replica_a)
    let replica_b = or_set.remove(replica_b, elem_str)
    // Step 3: replica_a concurrently re-adds element (new tag, after b's remove)
    let replica_a = or_set.add(replica_a, elem_str)
    // Step 4: merge — the concurrent add must win
    let merged = or_set.merge(replica_a, replica_b)
    or_set.contains(merged, elem_str) |> expect.to_be_true()
    Nil
  })
}

// ---------------------------------------------------------------------------
// TEST-10: 2P-Set tombstone permanence property
// Once removed, an element stays absent under any merge order
// ---------------------------------------------------------------------------

pub fn two_p_set_tombstone_permanence__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 20), fn(elem) {
    let elem_str = int.to_string(elem)
    // set_a: adds then removes element (tombstoned)
    let set_a =
      two_p_set.new()
      |> two_p_set.add(elem_str)
      |> two_p_set.remove(elem_str)
    // set_b: only adds element (concurrent with set_a's remove)
    let set_b = two_p_set.new() |> two_p_set.add(elem_str)
    // Merge in both orders — element must be absent in both
    let merged_ab = two_p_set.merge(set_a, set_b)
    let merged_ba = two_p_set.merge(set_b, set_a)
    two_p_set.contains(merged_ab, elem_str) |> expect.to_be_false()
    two_p_set.contains(merged_ba, elem_str) |> expect.to_be_false()
    Nil
  })
}

// ---------------------------------------------------------------------------
// TEST-08: Cross-target serialization smoke tests
// JSON round-trip works for representative CRDT types
// (Proves JSON uses no BEAM-specific types; necessary for cross-target compat)
// ---------------------------------------------------------------------------

pub fn g_counter_target_agnostic_json_round_trip__test() {
  let counter = g_counter.new("A") |> g_counter.increment(42)
  let encoded = json.to_string(g_counter.to_json(counter))
  let assert Ok(decoded) = g_counter.from_json(encoded)
  g_counter.value(decoded) |> expect.to_equal(g_counter.value(counter))
}

pub fn or_set_target_agnostic_json_round_trip__test() {
  let s =
    or_set.new("A")
    |> or_set.add("hello")
    |> or_set.add("world")
  let encoded = json.to_string(or_set.to_json(s))
  let assert Ok(decoded) = or_set.from_json(encoded)
  or_set.value(decoded) |> expect.to_equal(or_set.value(s))
}

pub fn lww_map_target_agnostic_json_round_trip__test() {
  let m = lww_map.new() |> lww_map.set("k", "v", 100)
  let encoded = json.to_string(lww_map.to_json(m))
  let assert Ok(decoded) = lww_map.from_json(encoded)
  lww_map.get(decoded, "k") |> expect.to_equal(lww_map.get(m, "k"))
}
