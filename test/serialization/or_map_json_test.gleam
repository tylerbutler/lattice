import gleam/json
import gleam/set
import lattice/crdt.{GCounterSpec}
import lattice/g_counter
import lattice/or_map
import startest/expect

// OR-Map JSON round-trip tests

pub fn or_map_to_json_empty_test() {
  let map = or_map.new("A", GCounterSpec)
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> or_map.keys(d) |> expect.to_equal([])
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_round_trip_crdt_spec_preserved_test() {
  let map = or_map.new("A", GCounterSpec)
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      // crdt_spec should be preserved
      d.crdt_spec |> expect.to_equal(GCounterSpec)
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_round_trip_single_key_test() {
  let map = or_map.new("A", GCounterSpec)
  let map =
    or_map.update(map, "score", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) ->
          crdt.CrdtGCounter(g_counter.increment(counter, 5))
        _ -> c
      }
    })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      set.from_list(or_map.keys(d)) |> expect.to_equal(set.from_list(["score"]))
      case or_map.get(d, "score") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter) |> expect.to_equal(5)
        _ -> expect.to_be_true(False)
      }
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_round_trip_multiple_keys_test() {
  let map = or_map.new("A", GCounterSpec)
  let map =
    or_map.update(map, "alpha", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) ->
          crdt.CrdtGCounter(g_counter.increment(counter, 10))
        _ -> c
      }
    })
  let map =
    or_map.update(map, "beta", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) ->
          crdt.CrdtGCounter(g_counter.increment(counter, 20))
        _ -> c
      }
    })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      set.from_list(or_map.keys(d))
      |> expect.to_equal(set.from_list(["alpha", "beta"]))
      case or_map.get(d, "alpha") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter) |> expect.to_equal(10)
        _ -> expect.to_be_true(False)
      }
      case or_map.get(d, "beta") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter) |> expect.to_equal(20)
        _ -> expect.to_be_true(False)
      }
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_from_json_invalid_test() {
  let result = or_map.from_json("{invalid json}")
  case result {
    Ok(_) -> expect.to_be_true(False)
    Error(_) -> expect.to_be_true(True)
  }
}

pub fn or_map_from_json_rejects_values_that_do_not_match_spec_test() {
  let invalid_json =
    "{\"type\":\"or_map\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"crdt_spec\":\"g_counter\",\"key_set\":\"{\\\"type\\\":\\\"or_set\\\",\\\"v\\\":1,\\\"state\\\":{\\\"replica_id\\\":\\\"A\\\",\\\"counter\\\":1,\\\"entries\\\":{\\\"x\\\":[{\\\"r\\\":\\\"A\\\",\\\"c\\\":1}]}}}\",\"values\":[{\"key\":\"x\",\"crdt\":\"{\\\"type\\\":\\\"g_set\\\",\\\"v\\\":1,\\\"state\\\":{\\\"elements\\\":[\\\"x\\\"]}}\"}]}}"

  let _ =
    or_map.from_json(invalid_json)
    |> expect.to_be_error
  Nil
}
