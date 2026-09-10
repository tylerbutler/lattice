import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import lattice_text/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn text_round_trip_simple_test() {
  let doc =
    text.new(rid("A"))
    |> text.insert(0, "h")
    |> expect.to_be_ok()
    |> text.insert(1, "i")
    |> expect.to_be_ok()

  json.to_string(text.to_json(doc))
  |> text.from_json()
  |> expect.to_equal(Ok(doc))
}

pub fn text_round_trip_with_tombstone_test() {
  let doc =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> expect.to_be_ok()
    |> text.insert(1, "b")
    |> expect.to_be_ok()
    |> text.delete(0)
    |> expect.to_be_ok()

  json.to_string(text.to_json(doc))
  |> text.from_json()
  |> expect.to_equal(Ok(doc))
}

pub fn text_round_trip_after_replace_range_test() {
  let doc =
    text.new(rid("A"))
    |> text.insert(0, "abcd")
    |> expect.to_be_ok()
    |> text.replace_range(1, 3, "XY")
    |> expect.to_be_ok()

  json.to_string(text.to_json(doc))
  |> text.from_json()
  |> expect.to_equal(Ok(doc))
}

pub fn text_to_json_uses_sequence_envelope_test() {
  let doc = text.new(rid("A")) |> text.insert(0, "x") |> expect.to_be_ok()

  text.to_json(doc)
  |> json.to_string()
  |> string.contains("\"type\":\"sequence\"")
  |> expect.to_be_true()
}

pub fn text_from_json_wrong_type_rejected_test() {
  let payload = "{\"type\":\"g_counter\",\"v\":1,\"state\":{}}"
  case text.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn text_from_json_negative_counter_rejected_test() {
  let payload =
    "{\"type\":\"text\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":-1,\"items\":[]}}"

  case text.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn text_from_json_negative_item_id_counter_rejected_test() {
  let payload =
    "{\"type\":\"text\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":1,\"items\":[{\"id\":{\"replica_id\":\"A\",\"counter\":-1},\"origin_left\":null,\"origin_right\":null,\"value\":\"x\",\"deleted\":false}]}}"

  case text.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn text_load_reconstructs_counter_and_keeps_sequence_envelope_test() {
  let assert Ok(base) = text.insert(text.new(rid("A")), 0, "abcd")
  let assert Ok(deleted) = text.delete(base, 1)
  let assert Ok(moved) = text.move(deleted, 0, 2)
  let frontier = version_vector.new() |> version_vector.set_max(rid("A"), 6)
  let #(compacted, forwardings) = text.compact(moved, frontier)
  let expired = text.remove_forwardings(compacted, forwardings)

  use original <- list.each([moved, compacted, expired])
  let encoded = text.to_json(original) |> json.to_string()
  let envelope_decoder = {
    use tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(tag, version))
  }
  json.parse(encoded, envelope_decoder)
  |> expect.to_equal(Ok(#("sequence", 2)))
  let assert Ok(loaded) =
    encoded
    |> string.replace(
      "\"self_id\":\"A\",\"counter\":6",
      "\"self_id\":\"A\",\"counter\":0",
    )
    |> text.from_json()
  loaded |> expect.to_equal(original)

  let rebound = text.merge(text.new(rid("B")), loaded, rid("B"))
  let assert Ok(#(updated, delta)) = text.append_with_delta(rebound, "x")
  let assert Ok(anchor) = text.anchor_at(delta, 0, sequence.Before)
  let id_decoder = {
    use replica <- decode.field("replica_id", decode.string)
    use counter <- decode.field("counter", decode.int)
    decode.success(#(replica, counter))
  }
  text.anchor_to_json(anchor)
  |> json.to_string()
  |> json.parse(decode.at(["anchor", "id"], id_decoder))
  |> expect.to_equal(Ok(#("B", 7)))
  text.merge(rebound, delta, rid("B")) |> expect.to_equal(updated)
  text.to_json(updated)
  |> json.to_string()
  |> text.from_json()
  |> expect.to_equal(Ok(updated))
}
