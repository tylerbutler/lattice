import gleam/json
import lattice_core/replica_id
import lattice_fugue/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn abc() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "b")
  |> sequence.insert(2, "c")
}

fn round_trip(anchor: sequence.Anchor) {
  anchor
  |> sequence.anchor_to_json()
  |> json.to_string()
  |> sequence.anchor_from_json()
}

pub fn start_anchor_round_trips_test() {
  round_trip(sequence.start_anchor())
  |> expect.to_equal(Ok(sequence.start_anchor()))
}

pub fn end_anchor_round_trips_test() {
  round_trip(sequence.end_anchor())
  |> expect.to_equal(Ok(sequence.end_anchor()))
}

pub fn node_anchor_before_round_trips_test() {
  let anchor = sequence.anchor_at(abc(), 1, sequence.Before)
  round_trip(anchor)
  |> expect.to_equal(Ok(anchor))
}

pub fn node_anchor_after_round_trips_test() {
  let anchor = sequence.anchor_at(abc(), 2, sequence.After)
  round_trip(anchor)
  |> expect.to_equal(Ok(anchor))
}

pub fn round_tripped_anchor_resolves_identically_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 2, sequence.After)
  let assert Ok(decoded) = round_trip(anchor)
  expect.to_equal(sequence.resolve(seq, decoded), sequence.resolve(seq, anchor))
}

pub fn wrong_envelope_type_fails_test() {
  let decoded =
    "{\"type\":\"anchor\",\"v\":1,\"anchor\":{\"kind\":\"start\"}}"
    |> sequence.anchor_from_json()
  case decoded {
    Error(_) -> True
    Ok(_) -> False
  }
  |> expect.to_be_true()
}
