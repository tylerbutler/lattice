import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set

fn rid(id: String) {
  replica_id.new(id)
}

// G-Set round-trip tests

pub fn g_set_to_json_simple_test() {
  let s = g_set.new() |> g_set.add("alpha")
  let json_str = json.to_string(g_set.to_json(s))
  let decoded = g_set.from_json(json_str)
  case decoded {
    Ok(d) ->
      g_set.value(d)
      |> fn(actual, expected) {
        let assert True = actual == expected
        Nil
      }(g_set.value(s))
    Error(_) ->
      fn(actual) {
        let assert True = actual
        Nil
      }(False)
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
    Ok(d) ->
      g_set.value(d)
      |> fn(actual, expected) {
        let assert True = actual == expected
        Nil
      }(g_set.value(s))
    Error(_) ->
      fn(actual) {
        let assert True = actual
        Nil
      }(False)
  }
}

// 2P-Set round-trip tests

pub fn two_p_set_to_json_simple_test() {
  let s = two_p_set.new() |> two_p_set.add("hello")
  let json_str = json.to_string(two_p_set.to_json(s))
  let decoded = two_p_set.from_json(json_str)
  case decoded {
    Ok(d) ->
      two_p_set.value(d)
      |> fn(actual, expected) {
        let assert True = actual == expected
        Nil
      }(two_p_set.value(s))
    Error(_) ->
      fn(actual) {
        let assert True = actual
        Nil
      }(False)
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
      |> fn(actual, expected) {
        let assert True = actual == expected
        Nil
      }(set.from_list(["alpha", "gamma"]))
    }
    Error(_) ->
      fn(actual) {
        let assert True = actual
        Nil
      }(False)
  }
}

// OR-Set round-trip tests

pub fn or_set_to_json_simple_test() {
  let s = or_set.new(rid("A")) |> or_set.add("x")
  let json_str = json.to_string(or_set.to_json(s))
  let decoded = or_set.from_json(json_str)
  case decoded {
    Ok(d) ->
      or_set.value(d)
      |> fn(actual, expected) {
        let assert True = actual == expected
        Nil
      }(or_set.value(s))
    Error(_) ->
      fn(actual) {
        let assert True = actual
        Nil
      }(False)
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
    Ok(d) ->
      or_set.value(d)
      |> fn(actual, expected) {
        let assert True = actual == expected
        Nil
      }(or_set.value(s))
    Error(_) ->
      fn(actual) {
        let assert True = actual
        Nil
      }(False)
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
      |> fn(actual) {
        let assert False = actual
        Nil
      }
    Error(_) ->
      fn(actual) {
        let assert True = actual
        Nil
      }(False)
  }
}

type Payload {
  Payload(name: String, count: Int)
}

fn encode_payload(payload: Payload) -> json.Json {
  json.object([
    #("name", json.string(payload.name)),
    #("count", json.int(payload.count)),
  ])
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use name <- decode.field("name", decode.string)
  use count <- decode.field("count", decode.int)
  decode.success(Payload(name, count))
}

pub fn g_set_generic_int_and_record_round_trip_test() {
  let ints = g_set.new() |> g_set.add(1) |> g_set.add(2)
  g_set.to_json_with(ints, json.int)
  |> json.to_string()
  |> g_set.from_json_with(decode.int)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(ints))

  let records =
    g_set.new()
    |> g_set.add(Payload("first", 1))
    |> g_set.add(Payload("second", 2))
  g_set.to_json_with(records, encode_payload)
  |> json.to_string()
  |> g_set.from_json_with(payload_decoder())
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(records))
}

pub fn two_p_set_generic_tombstones_round_trip_test() {
  let ints = two_p_set.new() |> two_p_set.add(1) |> two_p_set.remove(1)
  let assert Ok(loaded) =
    two_p_set.to_json_with(ints, json.int)
    |> json.to_string()
    |> two_p_set.from_json_with(decode.int)
  loaded
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(ints)
  two_p_set.add(loaded, 1)
  |> two_p_set.contains(1)
  |> fn(actual) {
    let assert False = actual
    Nil
  }

  let tombstone = Payload("removed before add", 2)
  let records =
    two_p_set.new()
    |> two_p_set.add(Payload("retained", 1))
    |> two_p_set.remove(tombstone)
  let assert Ok(loaded) =
    two_p_set.to_json_with(records, encode_payload)
    |> json.to_string()
    |> two_p_set.from_json_with(payload_decoder())
  loaded
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(records)
  two_p_set.add(loaded, tombstone)
  |> two_p_set.contains(tombstone)
  |> fn(actual) {
    let assert False = actual
    Nil
  }
}

pub fn or_set_generic_int_preserves_tags_tombstones_and_pruned_clock_test() {
  let original =
    or_set.new(rid("A")) |> or_set.add(1) |> or_set.add(2) |> or_set.add(3)
  let concurrent = or_set.new(rid("B")) |> or_set.add(3)
  let removed =
    original
    |> or_set.remove(1)
    |> or_set.remove(2)
    |> or_set.merge(concurrent)
    |> or_set.prune(version_vector.new() |> version_vector.set_max(rid("A"), 1))
  let encoded = or_set.to_json_with(removed, json.int) |> json.to_string()
  json.parse(encoded, decode.at(["v"], decode.int))
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(3))
  let assert Ok(loaded) = or_set.from_json_with(encoded, decode.int)
  loaded
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(removed)
  or_set.pruned_vv(loaded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(or_set.pruned_vv(removed))
  let joined = or_set.merge(loaded, original)
  or_set.contains(joined, 1)
  |> fn(actual) {
    let assert False = actual
    Nil
  }
  or_set.contains(joined, 2)
  |> fn(actual) {
    let assert False = actual
    Nil
  }
  or_set.contains(joined, 3)
  |> fn(actual) {
    let assert True = actual
    Nil
  }
  or_set.add(loaded, 4)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(or_set.add(removed, 4))

  let #(updated, delta) = or_set.remove_with_delta(loaded, 3)
  let assert Ok(loaded_delta) =
    or_set.to_json_with(delta, json.int)
    |> json.to_string()
    |> or_set.from_json_with(decode.int)
  loaded_delta
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(delta)
  or_set.merge(loaded, loaded_delta)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(updated)
}

pub fn or_set_generic_record_round_trip_and_readd_test() {
  let payload = Payload("object, not a JSON key", 42)
  let original = or_set.new(rid("A")) |> or_set.add(payload)
  let removed = or_set.remove(original, payload)
  let assert Ok(loaded) =
    or_set.to_json_with(removed, encode_payload)
    |> json.to_string()
    |> or_set.from_json_with(payload_decoder())
  loaded
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(removed)
  let #(readded, delta) = or_set.add_with_delta(loaded, payload)
  let assert Ok(loaded_delta) =
    or_set.to_json_with(delta, encode_payload)
    |> json.to_string()
    |> or_set.from_json_with(payload_decoder())
  loaded_delta
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(delta)
  or_set.merge(removed, loaded_delta)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(readded)
  or_set.merge(readded, original)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(readded)
}

pub fn set_string_wire_formats_are_unchanged_test() {
  let grow = g_set.new() |> g_set.add("value")
  let grow_json = g_set.to_json(grow) |> json.to_string()
  grow_json
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }("{\"type\":\"g_set\",\"v\":1,\"state\":{\"elements\":[\"value\"]}}")
  g_set.to_json_with(grow, json.string)
  |> json.to_string()
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(grow_json)

  let two =
    two_p_set.new() |> two_p_set.add("value") |> two_p_set.remove("value")
  let two_json = two_p_set.to_json(two) |> json.to_string()
  two_json
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(
    "{\"type\":\"two_p_set\",\"v\":1,\"state\":{\"added\":[\"value\"],\"removed\":[\"value\"]}}",
  )
  two_p_set.to_json_with(two, json.string)
  |> json.to_string()
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(two_json)

  let observed = or_set.new(rid("A")) |> or_set.add("value")
  let observed_json = or_set.to_json(observed) |> json.to_string()
  observed_json
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(
    "{\"type\":\"or_set\",\"v\":2,\"state\":{\"replica_id\":\"A\",\"counter\":1,\"entries\":{\"value\":[{\"r\":\"A\",\"c\":1}]},\"tombstones\":[],\"pruned\":{\"type\":\"version_vector\",\"v\":1,\"state\":{\"clocks\":{}}}}}",
  )
  or_set.from_json(observed_json)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(observed))
  or_set.from_json(
    "{\"type\":\"or_set\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"counter\":1,\"entries\":{\"value\":[{\"r\":\"A\",\"c\":1}]}}}",
  )
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(observed))
  or_set.from_json_with(observed_json, decode.string)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  let generic = or_set.to_json_with(observed, json.string) |> json.to_string()
  or_set.from_json_with(generic, decode.string)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(observed))
  or_set.from_json(generic)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  Nil
}

pub fn generic_set_payload_decoders_are_applied_test() {
  g_set.new()
  |> g_set.add("wrong")
  |> g_set.to_json()
  |> json.to_string()
  |> g_set.from_json_with(decode.int)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  two_p_set.new()
  |> two_p_set.remove("wrong")
  |> two_p_set.to_json()
  |> json.to_string()
  |> two_p_set.from_json_with(decode.int)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  or_set.new(rid("A"))
  |> or_set.add("wrong")
  |> or_set.to_json_with(json.string)
  |> json.to_string()
  |> or_set.from_json_with(payload_decoder())
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  Nil
}

const empty_pruned = "{\"type\":\"version_vector\",\"v\":1,\"state\":{\"clocks\":{}}}"

fn generic_or_set_json(entries: String, tombstones: String) -> String {
  "{\"type\":\"or_set\",\"v\":3,\"state\":{\"replica_id\":\"A\",\"counter\":1,\"entries\":"
  <> entries
  <> ",\"tombstones\":"
  <> tombstones
  <> ",\"pruned\":"
  <> empty_pruned
  <> "}}"
}

pub fn or_set_generic_invalid_metadata_rejected_test() {
  use entries <- list.each([
    "[{\"value\":1,\"tags\":[]}]",
    "[{\"value\":1,\"tags\":[{\"r\":\"A\",\"c\":0}]}]",
    "[{\"value\":1,\"tags\":[{\"r\":\"A\",\"c\":-1}]}]",
    "[{\"value\":1,\"tags\":[{\"r\":\"A\",\"c\":1},{\"r\":\"A\",\"c\":1}]}]",
    "[{\"value\":1,\"tags\":[{\"r\":\"A\",\"c\":1}]},{\"value\":2,\"tags\":[{\"r\":\"A\",\"c\":1}]}]",
    "[{\"value\":1,\"tags\":[{\"r\":\"A\",\"c\":1}]},{\"value\":1,\"tags\":[{\"r\":\"B\",\"c\":1}]}]",
  ])
  generic_or_set_json(entries, "[]")
  |> or_set.from_json_with(decode.int)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
}

pub fn or_set_generic_live_tombstone_overlap_and_negative_clocks_rejected_test() {
  generic_or_set_json(
    "[{\"value\":1,\"tags\":[{\"r\":\"A\",\"c\":1}]}]",
    "[{\"r\":\"A\",\"c\":1}]",
  )
  |> or_set.from_json_with(decode.int)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  generic_or_set_json("[]", "[]")
  |> string.replace("\"counter\":1", "\"counter\":-1")
  |> or_set.from_json_with(decode.int)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  generic_or_set_json("[]", "[]")
  |> string.replace("\"clocks\":{}", "\"clocks\":{\"A\":-1}")
  |> or_set.from_json_with(decode.int)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
  Nil
}

pub fn or_set_generic_invalid_pruning_envelope_rejected_test() {
  let encoded =
    generic_or_set_json("[]", "[]")
    |> string.replace("\"clocks\":{}", "\"clocks\":{\"A\":1}")
  or_set.from_json_with(encoded, decode.int)
  |> fn(actual) {
    let assert Ok(_) = actual
    Nil
  }

  use invalid <- list.each([
    string.replace(
      encoded,
      "\"type\":\"version_vector\"",
      "\"type\":\"g_counter\"",
    ),
    string.replace(encoded, "\"v\":1", "\"v\":999"),
  ])
  or_set.from_json_with(invalid, decode.int)
  |> fn(actual) {
    let assert Error(_) = actual
    Nil
  }
}

pub fn or_set_generic_reconstructs_allocation_counter_test() {
  use encoded <- list.each([
    generic_or_set_json(
      "[{\"value\":1,\"tags\":[{\"r\":\"B\",\"c\":5}]}]",
      "[]",
    ),
    generic_or_set_json("[]", "[{\"r\":\"B\",\"c\":5}]"),
    generic_or_set_json("[]", "[]")
      |> string.replace("\"clocks\":{}", "\"clocks\":{\"B\":5}"),
  ])
  let assert Ok(loaded) = or_set.from_json_with(encoded, decode.int)
  let rebound = or_set.merge(or_set.new(rid("B")), loaded)
  let #(updated, delta) = or_set.add_with_delta(rebound, 2)
  or_set.to_json_with(delta, json.int)
  |> json.to_string()
  |> json.parse(decode.at(["state", "counter"], decode.int))
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(6))
  or_set.to_json_with(updated, json.int)
  |> json.to_string()
  |> or_set.from_json_with(decode.int)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(updated))
  or_set.merge(updated, loaded)
  |> or_set.contains(2)
  |> fn(actual) {
    let assert True = actual
    Nil
  }
}

pub fn or_set_pruning_canonicalizes_allocation_before_serialization_test() {
  let stable =
    version_vector.new()
    |> version_vector.set_max(rid("A"), 1)
    |> version_vector.set_max(rid("B"), 7)
  let pruned =
    or_set.new(rid("A"))
    |> or_set.add("old")
    |> or_set.prune(stable)
  or_set.to_json_with(pruned, json.string)
  |> json.to_string()
  |> or_set.from_json_with(decode.string)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(pruned))

  let assert Ok(legacy) =
    or_set.to_json(pruned)
    |> json.to_string()
    |> string.replace("\"counter\":7", "\"counter\":1")
    |> or_set.from_json()
  let rebound = or_set.merge(or_set.new(rid("B")), legacy)
  let #(_, delta) = or_set.add_with_delta(rebound, "new")
  or_set.to_json(delta)
  |> json.to_string()
  |> json.parse(decode.at(["state", "counter"], decode.int))
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(8))
  or_set.merge(pruned, delta)
  |> or_set.contains("new")
  |> fn(actual) {
    let assert True = actual
    Nil
  }
}
