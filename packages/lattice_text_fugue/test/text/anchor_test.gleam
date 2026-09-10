import gleam/json
import lattice_core/replica_id
import lattice_fugue/sequence
import lattice_text_fugue/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn hello() {
  text.new(rid("A"))
  |> text.insert(0, "hello")
}

pub fn start_anchor_resolves_to_zero_test() {
  let assert Ok(doc) = hello()
  text.resolve_anchor(doc, text.start_anchor())
  |> expect.to_equal(Ok(0))
}

pub fn end_anchor_tracks_length_test() {
  let assert Ok(doc) = hello()
  let anchor = text.end_anchor()
  let assert Ok(grown) = text.append(doc, "!")
  text.resolve_anchor(grown, anchor)
  |> expect.to_equal(Ok(6))
}

pub fn after_anchor_follows_earlier_inserts_test() {
  let assert Ok(doc) = hello()
  // Cursor after "hello" (index 5), After bias.
  let assert Ok(cursor) = text.anchor_at(doc, 5, sequence.After)
  let assert Ok(updated) = text.insert(doc, 0, "say ")
  text.resolve_anchor(updated, cursor)
  |> expect.to_equal(Ok(9))
}

pub fn anchor_on_deleted_grapheme_collapses_test() {
  let assert Ok(doc) = text.new(rid("A")) |> text.insert(0, "abc")
  let assert Ok(anchor) = text.anchor_at(doc, 1, sequence.Before)
  let assert Ok(deleted) = text.delete(doc, 1)
  text.resolve_anchor(deleted, anchor)
  |> expect.to_equal(Ok(1))
}

pub fn anchor_at_out_of_bounds_test() {
  let assert Ok(doc) = hello()
  text.anchor_at(doc, 99, sequence.Before)
  |> expect.to_equal(Error(sequence.AnchorIndexOutOfBounds(99, 5)))
  text.anchor_at(doc, -1, sequence.After)
  |> expect.to_equal(Error(sequence.AnchorIndexOutOfBounds(-1, 5)))
}

pub fn anchor_survives_merge_test() {
  let assert Ok(doc) = text.new(rid("A")) |> text.insert(0, "abc")
  let assert Ok(anchor) = text.anchor_at(doc, 2, sequence.After)

  let assert Ok(other) = text.new(rid("B")) |> text.insert(0, "Z")
  let merged = text.merge(doc, other, rid("A"))

  let assert Ok(index) = text.resolve_anchor(merged, anchor)
  expect.to_be_true(index >= 0 && index <= text.length(merged))
}

pub fn anchor_json_round_trips_test() {
  let assert Ok(doc) = hello()
  let assert Ok(anchor) = text.anchor_at(doc, 3, sequence.After)
  let assert Ok(decoded) =
    anchor
    |> text.anchor_to_json()
    |> json.to_string()
    |> text.anchor_from_json()
  let assert Ok(index) = text.resolve_anchor(doc, anchor)
  text.resolve_anchor(doc, decoded) |> expect.to_equal(Ok(index))
}

pub fn resolve_unknown_target_test() {
  let assert Ok(doc) = hello()
  let assert Ok(anchor) = text.anchor_at(doc, 1, sequence.After)
  text.resolve_anchor(text.new(rid("B")), anchor)
  |> expect.to_equal(Error(sequence.UnknownAnchorTarget))
}
