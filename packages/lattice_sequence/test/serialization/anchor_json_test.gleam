import gleam/json
import gleam/string
import lattice_core/replica_id
import lattice_sequence/sequence.{After, Before}
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn ab() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "b")
}

fn round_trip(
  anchor: sequence.Anchor,
) -> Result(sequence.Anchor, json.DecodeError) {
  json.to_string(sequence.anchor_to_json(anchor))
  |> sequence.anchor_from_json()
}

pub fn start_anchor_round_trip_test() {
  round_trip(sequence.start_anchor())
  |> expect.to_equal(Ok(sequence.start_anchor()))
}

pub fn end_anchor_round_trip_test() {
  round_trip(sequence.end_anchor())
  |> expect.to_equal(Ok(sequence.end_anchor()))
}

pub fn item_anchor_before_bias_round_trip_test() {
  let anchor = sequence.anchor_at(ab(), 1, Before)
  round_trip(anchor) |> expect.to_equal(Ok(anchor))
}

pub fn item_anchor_after_bias_round_trip_test() {
  let anchor = sequence.anchor_at(ab(), 1, After)
  round_trip(anchor) |> expect.to_equal(Ok(anchor))
}

pub fn anchor_json_uses_versioned_envelope_test() {
  let json_string =
    json.to_string(sequence.anchor_to_json(sequence.start_anchor()))

  json_string |> string.contains("\"type\":\"anchor\"") |> expect.to_be_true()
  json_string |> string.contains("\"v\":1") |> expect.to_be_true()
}

pub fn decoded_anchor_resolves_on_the_sequence_test() {
  let seq = ab()
  let assert Ok(anchor) = round_trip(sequence.anchor_at(seq, 1, Before))

  sequence.resolve(seq, anchor) |> expect.to_equal(1)
}

pub fn anchor_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"anchor\":{\"kind\":\"start\"}}"
  case sequence.anchor_from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn anchor_from_json_wrong_version_rejected_test() {
  let payload = "{\"type\":\"anchor\",\"v\":2,\"anchor\":{\"kind\":\"start\"}}"
  case sequence.anchor_from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn anchor_from_json_unknown_kind_rejected_test() {
  let payload = "{\"type\":\"anchor\",\"v\":1,\"anchor\":{\"kind\":\"middle\"}}"
  case sequence.anchor_from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn anchor_from_json_invalid_bias_rejected_test() {
  let payload =
    "{\"type\":\"anchor\",\"v\":1,\"anchor\":{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":1},\"bias\":\"sideways\"}}"
  case sequence.anchor_from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn anchor_from_json_negative_counter_rejected_test() {
  let payload =
    "{\"type\":\"anchor\",\"v\":1,\"anchor\":{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":-1},\"bias\":\"before\"}}"
  case sequence.anchor_from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn anchor_from_json_malformed_json_rejected_test() {
  case sequence.anchor_from_json("not json") {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}
