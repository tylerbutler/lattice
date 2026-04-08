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
