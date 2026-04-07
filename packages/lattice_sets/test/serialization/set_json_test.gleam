import gleam/json
import gleam/set
import lattice_core/replica_id
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// G-Set round-trip tests

pub fn g_set_to_json_simple_test() {
  let s = g_set.new() |> g_set.add("alpha")
  let json_str = json.to_string(g_set.to_json(s))
  let decoded = g_set.from_json(json_str)
  case decoded {
    Ok(d) -> g_set.value(d) |> expect.to_equal(g_set.value(s))
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn g_set_round_trip_multi_element_test() {
  let s =
    g_set.new()
    |> g_set.add("alpha")
    |> g_set.add("beta")
    |> g_set.add("gamma")
  let json_str = json.to_string(g_set.to_json(s))
  let decoded = g_set.from_json(json_str)
  case decoded {
    Ok(d) -> g_set.value(d) |> expect.to_equal(g_set.value(s))
    Error(_) -> expect.to_be_true(False)
  }
}

// 2P-Set round-trip tests

pub fn two_p_set_to_json_simple_test() {
  let s = two_p_set.new() |> two_p_set.add("hello")
  let json_str = json.to_string(two_p_set.to_json(s))
  let decoded = two_p_set.from_json(json_str)
  case decoded {
    Ok(d) -> two_p_set.value(d) |> expect.to_equal(two_p_set.value(s))
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn two_p_set_round_trip_with_removals_test() {
  let s =
    two_p_set.new()
    |> two_p_set.add("alpha")
    |> two_p_set.add("beta")
    |> two_p_set.add("gamma")
    |> two_p_set.remove("beta")
  let json_str = json.to_string(two_p_set.to_json(s))
  let decoded = two_p_set.from_json(json_str)
  case decoded {
    Ok(d) -> {
      // value() should exclude removed elements
      two_p_set.value(d)
      |> expect.to_equal(set.from_list(["alpha", "gamma"]))
    }
    Error(_) -> expect.to_be_true(False)
  }
}

// OR-Set round-trip tests

pub fn or_set_to_json_simple_test() {
  let s = or_set.new(rid("A")) |> or_set.add("x")
  let json_str = json.to_string(or_set.to_json(s))
  let decoded = or_set.from_json(json_str)
  case decoded {
    Ok(d) -> or_set.value(d) |> expect.to_equal(or_set.value(s))
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_set_round_trip_multi_element_test() {
  let s =
    or_set.new(rid("A"))
    |> or_set.add("x")
    |> or_set.add("y")
    |> or_set.add("z")
  let json_str = json.to_string(or_set.to_json(s))
  let decoded = or_set.from_json(json_str)
  case decoded {
    Ok(d) -> or_set.value(d) |> expect.to_equal(or_set.value(s))
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_set_round_trip_preserves_removed_tombstones_test() {
  let original = or_set.new(rid("A")) |> or_set.add("x")
  let removed =
    or_set.new(rid("B"))
    |> or_set.merge(original)
    |> or_set.remove("x")
  let json_str = json.to_string(or_set.to_json(removed))

  case or_set.from_json(json_str) {
    Ok(decoded) ->
      or_set.merge(original, decoded)
      |> or_set.contains("x")
      |> expect.to_be_false
    Error(_) -> expect.to_be_true(False)
  }
}
