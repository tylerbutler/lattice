import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_fugue/sequence

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
  |> fn(actual) {
    assert actual == Ok(seq)
  }
}

pub fn populated_round_trips_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
    |> result.try(sequence.insert(_, 1, "c"))
  round_trip(seq)
  |> fn(actual) {
    assert actual == Ok(seq)
  }
}

pub fn tombstones_round_trip_test() {
  let assert Ok(inserted) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
  let assert Ok(seq) = sequence.delete(inserted, 0)
  round_trip(seq)
  |> fn(actual) {
    assert actual == Ok(seq)
  }
}

pub fn round_trip_preserves_values_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "x")
    |> result.try(sequence.insert(_, 0, "y"))
    |> result.try(sequence.insert(_, 0, "z"))
  let assert Ok(decoded) = round_trip(seq)
  sequence.values(decoded)
  |> fn(actual) {
    assert actual == sequence.values(seq)
  }
}

pub fn decoded_snapshots_unicode_order_and_anchor_test() {
  let assert Ok(bmp) = sequence.new(rid("\u{e000}")) |> sequence.insert(0, "b")
  let assert Ok(supplementary) =
    sequence.new(rid("\u{10000}")) |> sequence.insert(0, "s")
  let assert Ok(anchor) = sequence.anchor_at(bmp, 0, sequence.Before)
  let assert Ok(decoded_bmp) = round_trip(bmp)
  let assert Ok(decoded_supplementary) = round_trip(supplementary)
  let local = rid("local")

  [
    sequence.merge(decoded_bmp, decoded_supplementary, local),
    sequence.merge(decoded_supplementary, decoded_bmp, local),
  ]
  |> list.each(fn(merged) {
    let assert Ok(decoded) = round_trip(merged)
    sequence.values(merged)
    |> fn(actual) {
      assert actual == ["b", "s"]
    }
    sequence.resolve(merged, anchor)
    |> fn(actual) {
      assert actual == Ok(0)
    }
    sequence.values(decoded)
    |> fn(actual) {
      assert actual == ["b", "s"]
    }
    sequence.resolve(decoded, anchor)
    |> fn(actual) {
      assert actual == Ok(0)
    }
  })
}

pub fn wrong_type_tag_fails_test() {
  let result =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{}}"
    |> sequence.from_json(decode.string)
  let _ = {
    let assert Error(error) = result
    error
  }
  Nil
}

pub fn wrong_version_fails_test() {
  let assert Ok(seq) = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let bad =
    seq
    |> sequence.to_json(json.string)
    |> json.to_string()
    |> string.replace("\"v\":2", "\"v\":99")
  let _ = {
    let assert Error(error) = sequence.from_json(bad, decode.string)
    error
  }
  Nil
}

pub fn live_null_round_trips_test() {
  let assert Ok(original) = sequence.insert(sequence.new(rid("A")), 0, Nil)
  let encoded =
    sequence.to_json(original, fn(_) { json.null() })
    |> json.to_string()
  let assert Ok(decoded) = sequence.from_json(encoded, decode.success(Nil))

  assert decoded == original
  assert sequence.values(decoded) == [Nil]
  assert sequence.length(decoded) == 1
  assert sequence.merge(original, decoded, rid("A")) == original
  assert sequence.merge(decoded, original, rid("A")) == original
  let assert Ok(#(2, [False])) =
    json.parse(encoded, {
      use version <- decode.field("v", decode.int)
      use deleted <- decode.field(
        "state",
        decode.at(["nodes"], decode.list(decode.at(["deleted"], decode.bool))),
      )
      decode.success(#(version, deleted))
    })
}

pub fn optional_payload_snapshots_and_deltas_round_trip_test() {
  let empty = sequence.new(rid("A"))
  let assert Ok(#(null_state, null_delta)) =
    sequence.insert_with_delta(empty, 0, None)
  let assert Ok(#(populated, nonnull_delta)) =
    sequence.insert_with_delta(null_state, 1, Some("kept"))
  let assert Ok(#(deleted, delete_delta)) =
    sequence.delete_with_delta(populated, 0)
  let decoder = decode.optional(decode.string)
  let encode = fn(value) { json.nullable(value, json.string) }

  [
    #(null_state, null_delta, empty),
    #(populated, nonnull_delta, null_state),
    #(deleted, delete_delta, populated),
  ]
  |> list.each(fn(pair) {
    let #(state, delta, previous) = pair
    let assert Ok(snapshot) =
      sequence.to_json(state, encode)
      |> json.to_string()
      |> sequence.from_json(decoder)
    let assert Ok(decoded_delta) =
      sequence.to_json(delta, encode)
      |> json.to_string()
      |> sequence.from_json(decoder)

    assert snapshot == state
    assert decoded_delta == delta
    assert sequence.merge(state, snapshot, rid("A")) == state
    assert sequence.merge(snapshot, state, rid("A")) == state
    assert sequence.merge(previous, decoded_delta, rid("A")) == state
    assert sequence.merge(decoded_delta, previous, rid("A")) == state
  })
  assert sequence.values(populated) == [None, Some("kept")]
  assert sequence.values(deleted) == [Some("kept")]
}

pub fn legacy_v1_retains_null_as_tombstone_test() {
  let legacy =
    "{\"type\":\"fugue\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":2,\"nodes\":[{\"id\":{\"replica_id\":\"A\",\"counter\":1},\"value\":null,\"parent\":null,\"side\":\"right\"},{\"id\":{\"replica_id\":\"A\",\"counter\":2},\"value\":\"kept\",\"parent\":{\"replica_id\":\"A\",\"counter\":1},\"side\":\"right\"}]}}"
  let assert Ok(decoded) =
    sequence.from_json(legacy, decode.optional(decode.string))
  assert sequence.values(decoded) == [Some("kept")]
  assert sequence.length(decoded) == 1
  let assert Ok(upgraded) =
    sequence.to_json(decoded, json.nullable(_, json.string))
    |> json.to_string()
    |> sequence.from_json(decode.optional(decode.string))
  assert upgraded == decoded

  let assert Ok(null_payloads) = sequence.from_json(legacy, decode.success(Nil))
  assert sequence.values(null_payloads) == [Nil]
}

pub fn v2_requires_explicit_deletion_and_valid_payload_test() {
  let live =
    "{\"type\":\"fugue\",\"v\":2,\"state\":{\"self_id\":\"A\",\"counter\":1,\"nodes\":[{\"id\":{\"replica_id\":\"A\",\"counter\":1},\"deleted\":false,\"value\":\"kept\",\"parent\":null,\"side\":\"right\"}]}}"
  [
    string.replace(live, "\"deleted\":false,", ""),
    string.replace(live, "\"deleted\":false", "\"deleted\":null"),
    string.replace(live, "\"deleted\":false", "\"deleted\":\"false\""),
    string.replace(live, "\"deleted\":false", "\"deleted\":true"),
    string.replace(live, "\"value\":\"kept\"", "\"value\":null"),
  ]
  |> list.each(fn(invalid) {
    let assert Error(_) = sequence.from_json(invalid, decode.string)
  })
}
