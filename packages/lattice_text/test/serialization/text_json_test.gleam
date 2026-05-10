import gleam/json
import lattice_core/replica_id
import lattice_text/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn text_round_trip_simple_test() {
  let doc =
    text.new(rid("A"))
    |> text.insert(0, "h")
    |> text.insert(1, "i")

  json.to_string(text.to_json(doc))
  |> text.from_json()
  |> expect.to_equal(Ok(doc))
}

pub fn text_round_trip_with_tombstone_test() {
  let doc =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> text.insert(1, "b")
    |> text.delete(0)

  json.to_string(text.to_json(doc))
  |> text.from_json()
  |> expect.to_equal(Ok(doc))
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
