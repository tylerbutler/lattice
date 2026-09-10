import gleam/dynamic/decode
import gleam/json
import gleam/list
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

pub fn unicode_order_concurrent_first_insert_snapshots_test() {
  let bmp =
    sequence.new(rid("\u{e000}"))
    |> sequence.insert(0, "b")
  let supplementary =
    sequence.new(rid("\u{10000}"))
    |> sequence.insert(0, "s")
  let anchor = sequence.anchor_at(bmp, 0, sequence.Before)
  let decoded_bmp =
    sequence.to_json(bmp, json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)
    |> expect.to_be_ok()
  let decoded_supplementary =
    sequence.to_json(supplementary, json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)
    |> expect.to_be_ok()

  use pair <- list.each([
    #(decoded_bmp, decoded_supplementary),
    #(decoded_supplementary, decoded_bmp),
  ])
  let merged = sequence.merge(pair.0, pair.1)
  let decoded =
    sequence.to_json(merged, json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)
    |> expect.to_be_ok()
  use state <- list.each([merged, decoded])
  sequence.values(state) |> expect.to_equal(["b", "s"])
  sequence.resolve(state, anchor) |> expect.to_equal(0)
}

pub fn unicode_order_concurrent_deletes_retain_minimum_op_id_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "x")
  let #(bmp, bmp_delta) =
    sequence.merge(sequence.new(rid("\u{e000}")), base)
    |> sequence.delete_with_delta(0)
  let #(supplementary, supplementary_delta) =
    sequence.merge(sequence.new(rid("\u{10000}")), base)
    |> sequence.delete_with_delta(0)
  let op_id_decoder = {
    use replica <- decode.field("replica_id", decode.string)
    use counter <- decode.field("counter", decode.int)
    decode.success(#(replica, counter))
  }
  let deleted_ops =
    decode.at(
      ["state", "segments"],
      decode.list(decode.at(["deleted"], op_id_decoder)),
    )
  list.each(
    [#(bmp_delta, "\u{e000}"), #(supplementary_delta, "\u{10000}")],
    fn(pair) {
      sequence.to_json(pair.0, json.string)
      |> json.to_string()
      |> json.parse(deleted_ops)
      |> expect.to_equal(Ok([#(pair.1, 2)]))
    },
  )

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
  ])
  let merged = sequence.merge(pair.0, pair.1)
  let decoded =
    sequence.to_json(merged, json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)
    |> expect.to_be_ok()
  use state <- list.each([merged, decoded])
  sequence.values(state) |> expect.to_equal([])
  sequence.to_json(state, json.string)
  |> json.to_string()
  |> json.parse(deleted_ops)
  |> expect.to_equal(Ok([#("\u{e000}", 2)]))
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
    "{\"type\":\"sequence\",\"v\":2,\"state\":{\"self_id\":\"A\",\"counter\":0,\"frontier\":"
    <> empty_frontier
    <> ",\"forwardings\":[],\"segments\":[]}}"

  case sequence.from_json(payload, decode.string) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}
