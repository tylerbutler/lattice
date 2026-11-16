import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_text_fugue/text

fn rid(id: String) {
  replica_id.new(id)
}

fn round_trip(doc: text.Text) {
  doc
  |> text.to_json()
  |> json.to_string()
  |> text.from_json()
}

pub fn empty_round_trips_test() {
  let doc = text.new(rid("A"))
  round_trip(doc)
  |> fn(actual) {
    assert actual == Ok(doc)
  }
}

pub fn populated_round_trips_test() {
  let assert Ok(doc) =
    text.new(rid("A"))
    |> text.insert(0, "hello world")
  round_trip(doc)
  |> fn(actual) {
    assert actual == Ok(doc)
  }
}

pub fn value_survives_round_trip_test() {
  let assert Ok(inserted) =
    text.new(rid("A"))
    |> text.insert(0, "abc")
  let assert Ok(doc) = text.delete(inserted, 1)
  let assert Ok(decoded) = round_trip(doc)
  text.value(decoded)
  |> fn(actual) {
    assert actual == "ac"
  }
}

pub fn wrong_envelope_fails_test() {
  let decoded = text.from_json("{\"type\":\"not_fugue\",\"v\":1}")
  case decoded {
    Error(_) -> True
    Ok(_) -> False
  }
  |> fn(actual) {
    assert actual
  }
}

pub fn legacy_v1_upgrades_to_v2_test() {
  let legacy =
    "{\"type\":\"fugue\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":2,\"nodes\":[{\"id\":{\"replica_id\":\"A\",\"counter\":1},\"value\":null,\"parent\":null,\"side\":\"right\"},{\"id\":{\"replica_id\":\"A\",\"counter\":2},\"value\":\"x\",\"parent\":{\"replica_id\":\"A\",\"counter\":1},\"side\":\"right\"}]}}"
  let assert Ok(doc) = text.from_json(legacy)
  assert text.value(doc) == "x"
  let encoded = text.to_json(doc) |> json.to_string()
  let assert Ok(2) = json.parse(encoded, decode.at(["v"], decode.int))
  let assert Ok(decoded) = text.from_json(encoded)
  assert decoded == doc
  assert text.merge(doc, decoded, rid("A")) == doc
}

pub fn decoded_text_can_edit_after_counter_repair_and_identity_change_test() {
  let assert Ok(original) =
    text.new(rid("B"))
    |> text.insert(0, "old")
  let original_json =
    original
    |> text.to_json()
    |> json.to_string()
  let encoded =
    original_json
    |> string.replace("\"counter\":3,\"nodes\"", "\"counter\":0,\"nodes\"")
  assert encoded != original_json
  let assert Ok(decoded) = text.from_json(encoded)
  let rebound = text.merge_as(text.new(rid("A")), decoded, rid("B"))

  [decoded, rebound]
  |> list.each(fn(doc) {
    let assert Ok(updated) = text.insert(doc, 0, "new")
    assert text.value(updated) == "newold"
    assert text.length(updated) == 6
    assert round_trip(updated) == Ok(updated)
  })
}

pub fn text_rejects_duplicate_ids_and_parent_cycles_test() {
  let node =
    "{\"id\":{\"replica_id\":\"A\",\"counter\":1},\"value\":\"a\",\"parent\":null,\"side\":\"right\"}"
  [
    node <> "," <> node,
    string.replace(
      node,
      "\"parent\":null",
      "\"parent\":{\"replica_id\":\"A\",\"counter\":1}",
    ),
  ]
  |> list.each(fn(nodes) {
    let encoded =
      "{\"type\":\"fugue\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":0,\"nodes\":["
      <> nodes
      <> "]}}"
    let assert Error(json.UnableToDecode(_)) = text.from_json(encoded)
  })
}

pub fn decoded_text_delta_can_wait_for_missing_parent_test() {
  let local = rid("B")
  let assert Ok(base) = text.new(rid("A")) |> text.insert(0, "a")
  let assert Ok(#(_, delta)) = text.insert_with_delta(base, 1, "b")
  let assert Ok(decoded) = round_trip(delta)
  assert text.value(decoded) == ""
  let merged = text.merge(decoded, base, local)
  let assert Ok(updated) = text.append(merged, "c")
  assert text.value(updated) == "abc"
  assert round_trip(updated) == Ok(updated)
}
