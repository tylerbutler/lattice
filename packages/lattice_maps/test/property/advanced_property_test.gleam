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

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

// ---------------------------------------------------------------------------
// TEST-05: Bottom Identity
// merge(a, new()) preserves observable value(a) for map CRDT types
// ---------------------------------------------------------------------------

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
    let m = or_map.new(rid("A"), spec) |> or_map.update("key", fn(c) { c })
    let bottom = or_map.new(rid("B"), spec)
    set.from_list(or_map.keys(or_map.merge(m, bottom)))
    |> expect.to_equal(set.from_list(or_map.keys(m)))
    Nil
  })
}

// ---------------------------------------------------------------------------
// TEST-04: Convergence (3-replica all-to-all exchange)
// After all-to-all merge, all replicas agree on the same value
// ---------------------------------------------------------------------------

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
// TEST-08: Cross-target serialization smoke tests
// ---------------------------------------------------------------------------

pub fn lww_map_target_agnostic_json_round_trip__test() {
  let m = lww_map.new() |> lww_map.set("k", "v", 100)
  let encoded = json.to_string(lww_map.to_json(m))
  let assert Ok(decoded) = lww_map.from_json(encoded)
  lww_map.get(decoded, "k") |> expect.to_equal(lww_map.get(m, "k"))
}

pub fn or_map_target_agnostic_json_round_trip__test() {
  let map =
    or_map.new(rid("A"), crdt.GCounterSpec)
    |> or_map.update("x", fn(c) {
      case c {
        crdt.CrdtGCounter(gc) -> crdt.CrdtGCounter(g_counter.increment(gc, 42))
        other -> other
      }
    })
  let encoded = json.to_string(or_map.to_json(map))
  let assert Ok(decoded) = or_map.from_json(encoded)
  set.from_list(or_map.keys(decoded))
  |> expect.to_equal(set.from_list(or_map.keys(map)))
}
