import gleam/set
import lattice/crdt
import lattice/g_counter
import lattice/lww_map
import lattice/or_map
import lattice/or_set
import qcheck
import startest/expect

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
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
        or_map.new("A", crdt.GCounterSpec)
        |> or_map.update("x", increment_g_counter(_, a))
      let map_b =
        or_map.new("B", crdt.GCounterSpec)
        |> or_map.update("x", increment_g_counter(_, b))
      set.from_list(or_map.keys(or_map.merge(map_a, map_b)))
      |> expect.to_equal(set.from_list(or_map.keys(or_map.merge(map_b, map_a))))
      Nil
    },
  )
}

pub fn or_map_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 10), fn(a) {
    let map =
      or_map.new("A", crdt.GCounterSpec)
      |> or_map.update("x", increment_g_counter(_, a))
    set.from_list(or_map.keys(or_map.merge(map, map)))
    |> expect.to_equal(set.from_list(or_map.keys(map)))
    Nil
  })
}

// OR-Map associativity: Associativity skipped — constructing valid OR-Map triples
// for property testing is infeasible; see Phase 2 plan 04 decision on MV-Register.

// ---------------------------------------------------------------------------
// OR-Set associativity property test
// ---------------------------------------------------------------------------

pub fn or_set_associativity__test() {
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
      let set_a = or_set.new("A") |> or_set.add(a)
      let set_b = or_set.new("B") |> or_set.add(b)
      let set_c = or_set.new("C") |> or_set.add(c)
      let merged1 = or_set.merge(or_set.merge(set_a, set_b), set_c)
      let merged2 = or_set.merge(set_a, or_set.merge(set_b, set_c))
      or_set.value(merged1) |> expect.to_equal(or_set.value(merged2))
      Nil
    },
  )
}
