import gleam/json
import lattice_core/replica_id
import lattice_text_fugue/text
import startest/expect

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
  |> expect.to_equal(Ok(doc))
}

pub fn populated_round_trips_test() {
  let doc =
    text.new(rid("A"))
    |> text.insert(0, "hello world")
  round_trip(doc)
  |> expect.to_equal(Ok(doc))
}

pub fn value_survives_round_trip_test() {
  let doc =
    text.new(rid("A"))
    |> text.insert(0, "abc")
    |> text.delete(1)
  let assert Ok(decoded) = round_trip(doc)
  text.value(decoded)
  |> expect.to_equal("ac")
}

pub fn wrong_envelope_fails_test() {
  let decoded = text.from_json("{\"type\":\"not_fugue\",\"v\":1}")
  case decoded {
    Error(_) -> True
    Ok(_) -> False
  }
  |> expect.to_be_true()
}
