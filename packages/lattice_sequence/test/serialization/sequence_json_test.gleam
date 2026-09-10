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
    |> expect.to_be_ok()
    |> sequence.insert(1, "i")
    |> expect.to_be_ok()

  json.to_string(sequence.to_json(seq, json.string))
  |> sequence.from_json(decode.string)
  |> expect.to_equal(Ok(seq))
}

pub fn sequence_int_round_trip_with_tombstone_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, 1)
    |> expect.to_be_ok()
    |> sequence.insert(1, 2)
    |> expect.to_be_ok()
    |> sequence.delete(0)
    |> expect.to_be_ok()

  json.to_string(sequence.to_json(seq, json.int))
  |> sequence.from_json(decode.int)
  |> expect.to_equal(Ok(seq))
}

pub fn sequence_round_trip_compacted_state_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
    |> sequence.delete(1)
    |> expect.to_be_ok()
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
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
  let frontier = version_vector.new() |> version_vector.set_max(rid("A"), 3)
  let #(compacted, _forwardings) = sequence.compact(base, frontier)
  let seq = sequence.insert(compacted, 1, "x") |> expect.to_be_ok()

  json.to_string(sequence.to_json(seq, json.string))
  |> sequence.from_json(decode.string)
  |> expect.to_equal(Ok(seq))
}

pub fn sequence_compacted_json_contains_block_and_forwarding_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.delete(1)
    |> expect.to_be_ok()
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
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.move(0, 1)
    |> expect.to_be_ok()
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

fn id_json(counter: Int) -> json.Json {
  json.object([
    #("replica_id", json.string("B")),
    #("counter", json.int(counter)),
  ])
}

fn item_json(
  id: json.Json,
  left: json.Json,
  right: json.Json,
  deleted: json.Json,
  move: json.Json,
) -> json.Json {
  json.object([
    #("kind", json.string("item")),
    #("id", id),
    #("origin_left", left),
    #("origin_right", right),
    #("value", json.string("old")),
    #("deleted", deleted),
    #("move", move),
  ])
}

fn move_json(op: Int, left: json.Json, right: json.Json) -> json.Json {
  json.object([
    #("op_id", id_json(op)),
    #("origin_left", left),
    #("origin_right", right),
  ])
}

fn forwarding_json(id: Int, left: json.Json, right: json.Json) -> json.Json {
  json.object([
    #("id", id_json(id)),
    #("left", left),
    #("right", right),
  ])
}

fn allocation_snapshot(
  version: Int,
  segments: List(json.Json),
  forwardings: List(json.Json),
  frontier: version_vector.VersionVector,
) -> String {
  json.object([
    #("type", json.string("sequence")),
    #("v", json.int(version)),
    #(
      "state",
      json.object([
        #("self_id", json.string("A")),
        #("counter", json.int(0)),
        #("segments", json.array(segments, fn(x) { x })),
        #("forwardings", json.array(forwardings, fn(x) { x })),
        #("frontier", version_vector.to_json(frontier)),
      ]),
    ),
  ])
  |> json.to_string()
}

fn assert_safe_allocation(encoded: String, expected_counter: Int) {
  let assert Ok(loaded) = sequence.from_json(encoded, decode.string)
  sequence.to_json(loaded, json.string)
  |> json.to_string()
  |> json.parse(decode.at(["state", "counter"], decode.int))
  |> expect.to_equal(Ok(expected_counter))
  sequence.to_json(loaded, json.string)
  |> json.to_string()
  |> sequence.from_json(decode.string)
  |> expect.to_equal(Ok(loaded))

  let rebound = sequence.merge(sequence.new(rid("B")), loaded, rid("B"))
  let assert Ok(#(_, delta)) = sequence.insert_with_delta(rebound, 0, "new")
  let assert Ok(anchor) = sequence.anchor_at(delta, 0, sequence.Before)
  let id_decoder = {
    use replica <- decode.field("replica_id", decode.string)
    use counter <- decode.field("counter", decode.int)
    decode.success(#(replica, counter))
  }
  sequence.anchor_to_json(anchor)
  |> json.to_string()
  |> json.parse(decode.at(["anchor", "id"], id_decoder))
  |> expect.to_equal(Ok(#("B", expected_counter + 1)))
}

pub fn sequence_load_reconstructs_counter_from_items_operations_and_origins_test() {
  let nil = json.null()
  let cases = [
    item_json(id_json(5), nil, nil, nil, nil),
    item_json(id_json(1), nil, nil, id_json(5), nil),
    item_json(id_json(1), nil, nil, nil, move_json(5, nil, nil)),
    item_json(id_json(1), id_json(5), nil, nil, nil),
    item_json(id_json(1), nil, id_json(5), nil, nil),
    item_json(id_json(1), nil, nil, nil, move_json(2, id_json(5), nil)),
    item_json(id_json(1), nil, nil, nil, move_json(2, nil, id_json(5))),
  ]
  use version <- list.each([1, 2])
  use item <- list.each(cases)
  allocation_snapshot(version, [item], [], version_vector.new())
  |> assert_safe_allocation(5)
}

pub fn sequence_load_reconstructs_counter_from_compacted_block_range_test() {
  let block =
    json.object([
      #("kind", json.string("block")),
      #("first_id", id_json(3)),
      #("values", json.array(["a", "b", "c"], json.string)),
    ])
  use version <- list.each([1, 2])
  allocation_snapshot(version, [block], [], version_vector.new())
  |> assert_safe_allocation(5)
}

pub fn sequence_load_reconstructs_counter_from_forwarding_history_test() {
  let nil = json.null()
  use version <- list.each([1, 2])
  use forwarding <- list.each([
    forwarding_json(5, nil, nil),
    forwarding_json(1, id_json(5), nil),
    forwarding_json(1, nil, id_json(5)),
  ])
  allocation_snapshot(version, [], [forwarding], version_vector.new())
  |> assert_safe_allocation(5)
}

pub fn sequence_load_reconstructs_counter_from_frontier_without_retained_ids_test() {
  let frontier = version_vector.new() |> version_vector.set_max(rid("B"), 5)
  use version <- list.each([1, 2])
  allocation_snapshot(version, [], [], frontier)
  |> assert_safe_allocation(5)
}

pub fn sequence_load_never_reduces_a_higher_allocation_counter_test() {
  allocation_snapshot(2, [], [], version_vector.new())
  |> string.replace(
    "\"self_id\":\"A\",\"counter\":0",
    "\"self_id\":\"A\",\"counter\":100",
  )
  |> assert_safe_allocation(100)
}
