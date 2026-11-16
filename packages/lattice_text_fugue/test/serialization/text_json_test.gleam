import gleam/dynamic/decode
import gleam/json
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
