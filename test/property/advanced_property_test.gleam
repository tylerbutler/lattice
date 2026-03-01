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
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(-50, 50),
    fn(n) {
      let counter = case n >= 0 {
        True -> pn_counter.new("A") |> pn_counter.increment(n)
        False -> pn_counter.new("A") |> pn_counter.decrement(-n)
      }
      let bottom = pn_counter.new("B")
      pn_counter.value(pn_counter.merge(counter, bottom))
      |> expect.to_equal(pn_counter.value(counter))
      Nil
    },
  )
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
  qcheck.run(
    small_test_config(),
    qcheck.small_non_negative_int(),
    fn(_n) {
      let spec = crdt.GCounterSpec
      let m = or_map.new("A", spec) |> or_map.update("key", fn(c) { c })
      let bottom = or_map.new("B", spec)
      set.from_list(or_map.keys(or_map.merge(m, bottom)))
      |> expect.to_equal(set.from_list(or_map.keys(m)))
      Nil
    },
  )
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
    qcheck.map2(
      qcheck.bounded_int(0, 50),
      qcheck.bounded_int(0, 50),
      fn(a, b) { #(a, b) },
    ),
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
    qcheck.map2(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b) { #(a, b) },
    ),
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
    qcheck.map2(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b) { #(a, b) },
    ),
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
