import gleam/int
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
// LWW-Map round-trip property
// ---------------------------------------------------------------------------

pub fn lww_map_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 20), qcheck.bounded_int(1, 100), fn(a, b) {
      #(a, b)
    }),
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
// OR-Map round-trip property
// ---------------------------------------------------------------------------

pub fn or_map_json_round_trip__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 10), fn(inc) {
    let map =
      or_map.new(rid("A"), crdt.GCounterSpec)
      |> or_map.update("x", fn(c) {
        case c {
          crdt.CrdtGCounter(gc) ->
            crdt.CrdtGCounter(g_counter.increment(gc, inc))
          other -> other
        }
      })
    let json_str = json.to_string(or_map.to_json(map))
    let decoded = or_map.from_json(json_str)
    case decoded {
      Ok(d) -> {
        set.from_list(or_map.keys(d))
        |> expect.to_equal(set.from_list(or_map.keys(map)))
      }
      Error(_) -> expect.to_be_true(False)
    }
    Nil
  })
}
