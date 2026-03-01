import gleam/json
import lattice/lww_map
import startest/expect

// LWW-Map JSON round-trip tests

pub fn lww_map_to_json_empty_test() {
  let map = lww_map.new()
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> lww_map.keys(d) |> expect.to_equal([])
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn lww_map_round_trip_active_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.set("age", "30", 2)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      lww_map.get(d, "name") |> expect.to_equal(Ok("Alice"))
      lww_map.get(d, "age") |> expect.to_equal(Ok("30"))
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn lww_map_round_trip_tombstone_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.remove("name", 5)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> lww_map.get(d, "name") |> expect.to_equal(Error(Nil))
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn lww_map_round_trip_mixed_active_and_tombstoned_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.set("age", "30", 2)
    |> lww_map.remove("age", 10)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      lww_map.get(d, "name") |> expect.to_equal(Ok("Alice"))
      lww_map.get(d, "age") |> expect.to_equal(Error(Nil))
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn lww_map_from_json_invalid_test() {
  let result = lww_map.from_json("{invalid json}")
  case result {
    Ok(_) -> expect.to_be_true(False)
    Error(_) -> expect.to_be_true(True)
  }
}
