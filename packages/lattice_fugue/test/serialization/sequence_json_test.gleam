import gleam/dynamic/decode
import gleam/json
import gleam/string
import lattice_core/replica_id
import lattice_fugue/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn round_trip(seq: sequence.Sequence(String)) {
  seq
  |> sequence.to_json(json.string)
  |> json.to_string()
  |> sequence.from_json(decode.string)
}

pub fn empty_round_trips_test() {
  let seq = sequence.new(rid("A"))
  round_trip(seq)
  |> expect.to_equal(Ok(seq))
}

pub fn populated_round_trips_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(1, "c")
  round_trip(seq)
  |> expect.to_equal(Ok(seq))
}

pub fn tombstones_round_trip_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.delete(0)
  round_trip(seq)
  |> expect.to_equal(Ok(seq))
}

pub fn round_trip_preserves_values_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "x")
    |> sequence.insert(0, "y")
    |> sequence.insert(0, "z")
  let assert Ok(decoded) = round_trip(seq)
  sequence.values(decoded)
  |> expect.to_equal(sequence.values(seq))
}

pub fn wrong_type_tag_fails_test() {
  let result =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{}}"
    |> sequence.from_json(decode.string)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn wrong_version_fails_test() {
  let seq = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let bad =
    seq
    |> sequence.to_json(json.string)
    |> json.to_string()
    |> string.replace("\"v\":1", "\"v\":2")
  let _ = expect.to_be_error(sequence.from_json(bad, decode.string))
  Nil
}
