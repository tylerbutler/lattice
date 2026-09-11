import gleam/json
import gleam/string
import lattice_core/replica_id
import lattice_sequence/sequence.{After, Before}

fn rid(id: String) {
  replica_id.new(id)
}

fn ab() {
  {
    let assert Ok(asserted_5) =
      {
        let assert Ok(asserted_6) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_6
      }
      |> sequence.insert(1, "b")
    asserted_5
  }
}

fn round_trip(
  anchor: sequence.Anchor,
) -> Result(sequence.Anchor, json.DecodeError) {
  json.to_string(sequence.anchor_to_json(anchor))
  |> sequence.anchor_from_json()
}

pub fn start_anchor_round_trip_test() {
  round_trip(sequence.start_anchor())
  |> fn(actual) {
    assert actual == { Ok(sequence.start_anchor()) }
  }
}

pub fn end_anchor_round_trip_test() {
  round_trip(sequence.end_anchor())
  |> fn(actual) {
    assert actual == { Ok(sequence.end_anchor()) }
  }
}

pub fn item_anchor_before_bias_round_trip_test() {
  let anchor = {
    let assert Ok(asserted_4) = sequence.anchor_at(ab(), 1, Before)
    asserted_4
  }
  round_trip(anchor)
  |> fn(actual) {
    assert actual == { Ok(anchor) }
  }
}

pub fn item_anchor_after_bias_round_trip_test() {
  let anchor = {
    let assert Ok(asserted_3) = sequence.anchor_at(ab(), 1, After)
    asserted_3
  }
  round_trip(anchor)
  |> fn(actual) {
    assert actual == { Ok(anchor) }
  }
}

pub fn anchor_json_uses_versioned_envelope_test() {
  let json_string =
    json.to_string(sequence.anchor_to_json(sequence.start_anchor()))

  json_string
  |> string.contains("\"type\":\"anchor\"")
  |> fn(value) {
    assert value
  }
  json_string
  |> string.contains("\"v\":1")
  |> fn(value) {
    assert value
  }
}

pub fn decoded_anchor_resolves_on_the_sequence_test() {
  let seq = ab()
  let assert Ok(anchor) =
    round_trip({
      let assert Ok(asserted_2) = sequence.anchor_at(seq, 1, Before)
      asserted_2
    })

  {
    let assert Ok(asserted_1) = sequence.resolve(seq, anchor)
    asserted_1
  }
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn anchor_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"anchor\":{\"kind\":\"start\"}}"
  let assert Error(_) = sequence.anchor_from_json(payload)
}

pub fn anchor_from_json_wrong_version_rejected_test() {
  let payload = "{\"type\":\"anchor\",\"v\":2,\"anchor\":{\"kind\":\"start\"}}"
  let assert Error(_) = sequence.anchor_from_json(payload)
}

pub fn anchor_from_json_unknown_kind_rejected_test() {
  let payload = "{\"type\":\"anchor\",\"v\":1,\"anchor\":{\"kind\":\"middle\"}}"
  let assert Error(_) = sequence.anchor_from_json(payload)
}

pub fn anchor_from_json_invalid_bias_rejected_test() {
  let payload =
    "{\"type\":\"anchor\",\"v\":1,\"anchor\":{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":1},\"bias\":\"sideways\"}}"
  let assert Error(_) = sequence.anchor_from_json(payload)
}

pub fn anchor_from_json_negative_counter_rejected_test() {
  let payload =
    "{\"type\":\"anchor\",\"v\":1,\"anchor\":{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":-1},\"bias\":\"before\"}}"
  let assert Error(_) = sequence.anchor_from_json(payload)
}

pub fn anchor_from_json_malformed_json_rejected_test() {
  let assert Error(_) = sequence.anchor_from_json("not json")
}
