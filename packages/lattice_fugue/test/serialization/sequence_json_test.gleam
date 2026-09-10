import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
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
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
    |> result.try(sequence.insert(_, 1, "c"))
  round_trip(seq)
  |> expect.to_equal(Ok(seq))
}

pub fn tombstones_round_trip_test() {
  let assert Ok(inserted) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
  let assert Ok(seq) = sequence.delete(inserted, 0)
  round_trip(seq)
  |> expect.to_equal(Ok(seq))
}

pub fn round_trip_preserves_values_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "x")
    |> result.try(sequence.insert(_, 0, "y"))
    |> result.try(sequence.insert(_, 0, "z"))
  let assert Ok(decoded) = round_trip(seq)
  sequence.values(decoded)
  |> expect.to_equal(sequence.values(seq))
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
    sequence.values(merged) |> expect.to_equal(["b", "s"])
    sequence.resolve(merged, anchor) |> expect.to_equal(Ok(0))
    sequence.values(decoded) |> expect.to_equal(["b", "s"])
    sequence.resolve(decoded, anchor) |> expect.to_equal(Ok(0))
  })
}

pub fn wrong_type_tag_fails_test() {
  let result =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{}}"
    |> sequence.from_json(decode.string)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn wrong_version_fails_test() {
  let assert Ok(seq) = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let bad =
    seq
    |> sequence.to_json(json.string)
    |> json.to_string()
    |> string.replace("\"v\":1", "\"v\":2")
  let _ = expect.to_be_error(sequence.from_json(bad, decode.string))
  Nil
}
