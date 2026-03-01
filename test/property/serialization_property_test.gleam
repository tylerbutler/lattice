import gleam/int
import gleam/json
import lattice/g_counter
import lattice/g_set
import lattice/lww_map
import lattice/lww_register
import lattice/or_set
import lattice/pn_counter
import lattice/two_p_set
import qcheck
import startest/expect

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

// ---------------------------------------------------------------------------
// G-Counter round-trip property
// ---------------------------------------------------------------------------

pub fn g_counter_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a_delta, b_delta) = pair
      let counter = g_counter.new("A") |> g_counter.increment(a_delta)
      let counter2 = g_counter.new("B") |> g_counter.increment(b_delta)
      let merged = g_counter.merge(counter, counter2)
      let json_str = json.to_string(g_counter.to_json(merged))
      let decoded = g_counter.from_json(json_str)
      case decoded {
        Ok(d) -> g_counter.value(d) |> expect.to_equal(g_counter.value(merged))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// PN-Counter round-trip property
// ---------------------------------------------------------------------------

pub fn pn_counter_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 50),
      qcheck.bounded_int(0, 50),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(inc, dec) = pair
      let counter =
        pn_counter.new("A")
        |> pn_counter.increment(inc)
        |> pn_counter.decrement(dec)
      let json_str = json.to_string(pn_counter.to_json(counter))
      let decoded = pn_counter.from_json(json_str)
      case decoded {
        Ok(d) ->
          pn_counter.value(d) |> expect.to_equal(pn_counter.value(counter))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// LWW-Register round-trip property
// ---------------------------------------------------------------------------

pub fn lww_register_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 100),
    fn(ts) {
      let reg = lww_register.new("value_" <> int.to_string(ts), ts)
      let json_str = json.to_string(lww_register.to_json(reg))
      let decoded = lww_register.from_json(json_str)
      case decoded {
        Ok(d) -> {
          lww_register.value(d) |> expect.to_equal(lww_register.value(reg))
        }
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// G-Set round-trip property
// ---------------------------------------------------------------------------

pub fn g_set_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let s =
        g_set.new()
        |> g_set.add(int.to_string(a))
        |> g_set.add(int.to_string(b))
      let json_str = json.to_string(g_set.to_json(s))
      let decoded = g_set.from_json(json_str)
      case decoded {
        Ok(d) -> g_set.value(d) |> expect.to_equal(g_set.value(s))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// 2P-Set round-trip property
// ---------------------------------------------------------------------------

pub fn two_p_set_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 10),
    fn(n) {
      let s =
        two_p_set.new()
        |> two_p_set.add(int.to_string(n))
        |> two_p_set.add(int.to_string(n + 1))
        |> two_p_set.remove(int.to_string(n))
      let json_str = json.to_string(two_p_set.to_json(s))
      let decoded = two_p_set.from_json(json_str)
      case decoded {
        Ok(d) -> two_p_set.value(d) |> expect.to_equal(two_p_set.value(s))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// OR-Set round-trip property
// ---------------------------------------------------------------------------

pub fn or_set_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 10),
    fn(n) {
      let s =
        or_set.new("A")
        |> or_set.add(int.to_string(n))
        |> or_set.add(int.to_string(n + 1))
      let json_str = json.to_string(or_set.to_json(s))
      let decoded = or_set.from_json(json_str)
      case decoded {
        Ok(d) -> or_set.value(d) |> expect.to_equal(or_set.value(s))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// LWW-Map round-trip property
// ---------------------------------------------------------------------------

pub fn lww_map_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(1, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(val, ts) = pair
      let map =
        lww_map.new()
        |> lww_map.set("key1", int.to_string(val), ts)
        |> lww_map.set("key2", "fixed", ts + 1)
      let json_str = json.to_string(lww_map.to_json(map))
      let decoded = lww_map.from_json(json_str)
      case decoded {
        Ok(d) -> {
          lww_map.get(d, "key1") |> expect.to_equal(lww_map.get(map, "key1"))
          lww_map.get(d, "key2") |> expect.to_equal(lww_map.get(map, "key2"))
        }
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}

// ---------------------------------------------------------------------------
// Merge-preserving serialization property (G-Counter)
// ---------------------------------------------------------------------------

pub fn g_counter_merge_after_serialize__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a_delta, b_delta) = pair
      let ca = g_counter.new("A") |> g_counter.increment(a_delta)
      let cb = g_counter.new("B") |> g_counter.increment(b_delta)
      // Serialize both, deserialize, merge deserialized
      let ca_json = json.to_string(g_counter.to_json(ca))
      let cb_json = json.to_string(g_counter.to_json(cb))
      case g_counter.from_json(ca_json), g_counter.from_json(cb_json) {
        Ok(da), Ok(db) -> {
          let merged_original = g_counter.merge(ca, cb)
          let merged_deserialized = g_counter.merge(da, db)
          g_counter.value(merged_deserialized)
          |> expect.to_equal(g_counter.value(merged_original))
        }
        _, _ -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
