import gleam/dynamic/decode
import gleam/json
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

const empty_frontier = "{\"type\":\"version_vector\",\"v\":1,\"state\":{\"clocks\":{}}}"

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

pub fn sequence_round_trip_compacted_state_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
    |> sequence.delete(1)
  let frontier = version_vector.new() |> version_vector.set_max(rid("A"), 4)
  let #(compacted, _forwardings) = sequence.compact(seq, frontier)

  json.to_string(sequence.to_json(compacted, json.string))
  |> sequence.from_json(decode.string)
  |> expect.to_equal(Ok(compacted))
}

pub fn sequence_round_trip_mixed_blocks_and_items_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  let frontier = version_vector.new() |> version_vector.set_max(rid("A"), 3)
  let #(compacted, _forwardings) = sequence.compact(base, frontier)
  let seq = sequence.insert(compacted, 1, "x")

  json.to_string(sequence.to_json(seq, json.string))
  |> sequence.from_json(decode.string)
  |> expect.to_equal(Ok(seq))
}

pub fn sequence_compacted_json_contains_block_and_forwarding_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.delete(1)
  let frontier = version_vector.new() |> version_vector.set_max(rid("A"), 3)
  let #(compacted, _forwardings) = sequence.compact(seq, frontier)
  let json_string = json.to_string(sequence.to_json(compacted, json.string))

  json_string |> string.contains("\"kind\":\"block\"") |> expect.to_be_true()
  json_string |> string.contains("\"forwardings\":[{") |> expect.to_be_true()
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
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":-1,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":[]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_negative_item_id_counter_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":1,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":[{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":-1},\"origin_left\":null,\"origin_right\":null,\"value\":\"x\",\"deleted\":null}]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_unknown_segment_kind_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":1,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":[{\"kind\":\"mystery\"}]}}"

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
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":1,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":[{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":1},\"origin_left\":null,\"origin_right\":null,\"value\":\"x\",\"deleted\":null}]}}"

  case sequence.from_json(payload, decode.string) {
    Ok(seq) -> sequence.values(seq) |> expect.to_equal(["x"])
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_unknown_version_rejected_test() {
  let payload =
    "{\"type\":\"sequence\",\"v\":3,\"state\":{\"self_id\":\"A\",\"counter\":0,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":[]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_v1_without_moves_accepted_test() {
  // v1 stored the move-applied order, but with no move record there was no
  // overlay, so the payload's order is already the canonical base.
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":2,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":["
    <> "{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":1},\"origin_left\":null,"
    <> "\"origin_right\":null,\"value\":\"a\",\"deleted\":null,\"move\":null},"
    <> "{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":2},\"origin_left\":"
    <> "{\"replica_id\":\"A\",\"counter\":1},\"origin_right\":null,\"value\":\"b\","
    <> "\"deleted\":null,\"move\":null}]}}"

  case sequence.from_json(payload, decode.string) {
    Ok(decoded) -> sequence.values(decoded) |> expect.to_equal(["a", "b"])
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn sequence_from_json_v1_with_compacted_move_rejected_test() {
  // A v1 payload holding both a move record and a compacted block cannot be
  // brought into base order: the block has no origins to re-integrate the
  // mover against. The holder must resync rather than decode a state whose
  // mover would be pinned at its post-move slot.
  let payload =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":3,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":["
    <> "{\"kind\":\"block\",\"first_id\":{\"replica_id\":\"A\",\"counter\":1},\"values\":[\"a\"]},"
    <> "{\"kind\":\"item\",\"id\":{\"replica_id\":\"A\",\"counter\":2},\"origin_left\":"
    <> "{\"replica_id\":\"A\",\"counter\":1},\"origin_right\":null,\"value\":\"b\","
    <> "\"deleted\":null,\"move\":{\"op_id\":{\"replica_id\":\"A\",\"counter\":3},"
    <> "\"origin_left\":null,\"origin_right\":{\"replica_id\":\"A\",\"counter\":1}}}]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}
