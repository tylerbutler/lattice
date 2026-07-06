import gleam/json
import lattice_core/replica_id
import lattice_fugue/sequence
import lattice_fugue_text/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn hello() {
  text.new(rid("A"))
  |> text.insert(0, "hello")
}

pub fn start_anchor_resolves_to_zero_test() {
  text.resolve_anchor(hello(), text.start_anchor())
  |> expect.to_equal(0)
}

pub fn end_anchor_tracks_length_test() {
  let doc = hello()
  let anchor = text.end_anchor()
  let grown = text.append(doc, "!")
  text.resolve_anchor(grown, anchor)
  |> expect.to_equal(6)
}

pub fn after_anchor_follows_earlier_inserts_test() {
  let doc = hello()
  // Cursor after "hello" (index 5), After bias.
  let cursor = text.anchor_at(doc, 5, sequence.After)
  let updated = text.insert(doc, 0, "say ")
  text.resolve_anchor(updated, cursor)
  |> expect.to_equal(9)
}

pub fn anchor_on_deleted_grapheme_collapses_test() {
  let doc = text.new(rid("A")) |> text.insert(0, "abc")
  let anchor = text.anchor_at(doc, 1, sequence.Before)
  let deleted = text.delete(doc, 1)
  text.resolve_anchor(deleted, anchor)
  |> expect.to_equal(1)
}

pub fn try_anchor_at_out_of_bounds_test() {
  hello()
  |> text.try_anchor_at(99, sequence.Before)
  |> is_err()
  |> expect.to_be_true()
}

pub fn anchor_survives_merge_test() {
  let doc = text.new(rid("A")) |> text.insert(0, "abc")
  let anchor = text.anchor_at(doc, 2, sequence.After)

  let other = text.new(rid("B")) |> text.insert(0, "Z")
  let merged = text.merge(doc, other)

  let index = text.resolve_anchor(merged, anchor)
  expect.to_be_true(index >= 0 && index <= text.length(merged))
}

pub fn anchor_json_round_trips_test() {
  let doc = hello()
  let anchor = text.anchor_at(doc, 3, sequence.After)
  let assert Ok(decoded) =
    anchor
    |> text.anchor_to_json()
    |> json.to_string()
    |> text.anchor_from_json()
  expect.to_equal(
    text.resolve_anchor(doc, decoded),
    text.resolve_anchor(doc, anchor),
  )
}

fn is_err(result: Result(a, b)) -> Bool {
  case result {
    Error(_) -> True
    Ok(_) -> False
  }
}
