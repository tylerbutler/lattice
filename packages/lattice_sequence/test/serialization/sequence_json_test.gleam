import gleam/dynamic/decode
import gleam/json
import gleam/string
import lattice_core/replica_id
import lattice_sequence/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn sequence_string_round_trip_simple_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "h")
    |> sequence.insert(1, "i")

  json.to_string(sequence.to_json(seq, json.string))
  |> sequence.from_json(decode.string)
  |> expect.to_equal(Ok(seq))
}

pub fn sequence_int_round_trip_with_tombstone_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, 1)
    |> sequence.insert(1, 2)
    |> sequence.delete(0)

  json.to_string(sequence.to_json(seq, json.int))
  |> sequence.from_json(decode.int)
  |> expect.to_equal(Ok(seq))
}

pub fn sequence_from_json_wrong_type_rejected_test() {
  let payload = "{\"type\":\"text\",\"v\":1,\"state\":{}}"
  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_negative_counter_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":-1,\"items\":[]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_negative_item_id_counter_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":1,\"items\":[{\"id\":{\"replica_id\":\"A\",\"counter\":-1},\"origin_left\":null,\"origin_right\":null,\"value\":\"x\",\"deleted\":false}]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_move_json_round_trip_keeps_v1_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.move(0, 1)
  let json_string = json.to_string(sequence.to_json(seq, json.string))

  json_string |> string.contains("\"v\":1") |> expect.to_be_true()
  json_string |> string.contains("\"move\":") |> expect.to_be_true()
  json_string
  |> sequence.from_json(decode.string)
  |> expect.to_equal(Ok(seq))
}

pub fn sequence_from_json_missing_move_decodes_as_no_move_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":1,\"items\":[{\"id\":{\"replica_id\":\"A\",\"counter\":1},\"origin_left\":null,\"origin_right\":null,\"value\":\"x\",\"deleted\":false}]}}"

  case sequence.from_json(payload, decode.string) {
    Ok(seq) -> sequence.values(seq) |> expect.to_equal(["x"])
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_unknown_version_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":2,\"state\":{\"self_id\":\"A\",\"counter\":0,\"items\":[]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}
