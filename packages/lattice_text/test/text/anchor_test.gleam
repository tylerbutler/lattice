import gleam/json
import lattice_core/replica_id
import lattice_sequence/sequence.{After, Before}
import lattice_text/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn doc(value: String) {
  text.new(rid("A"))
  |> text.insert(0, value)
  |> expect.to_be_ok()
}

pub fn start_and_end_anchors_resolve_test() {
  let d = doc("abc")

  text.resolve_anchor(d, text.start_anchor())
  |> expect.to_be_ok()
  |> expect.to_equal(0)
  text.resolve_anchor(d, text.end_anchor())
  |> expect.to_be_ok()
  |> expect.to_equal(3)
  text.resolve_anchor(
    text.append(d, "de") |> expect.to_be_ok(),
    text.end_anchor(),
  )
  |> expect.to_be_ok()
  |> expect.to_equal(5)
}

pub fn anchor_shifts_with_insert_before_it_test() {
  let d = doc("hello")
  let anchor = text.anchor_at(d, 5, After) |> expect.to_be_ok()

  text.resolve_anchor(text.insert(d, 0, "say ") |> expect.to_be_ok(), anchor)
  |> expect.to_be_ok()
  |> expect.to_equal(9)
}

pub fn try_anchor_at_out_of_bounds_returns_error_test() {
  doc("abc")
  |> text.anchor_at(4, Before)
  |> expect.to_equal(
    Error(sequence.AnchorIndexOutOfBounds(index: 4, length: 3)),
  )
}

pub fn try_resolve_anchor_unknown_target_returns_error_test() {
  let alice = doc("abc")
  let bob =
    text.merge(text.new(rid("B")), alice, rid("B"))
    |> text.insert(1, "x")
    |> expect.to_be_ok()
  let anchor = text.anchor_at(bob, 1, Before) |> expect.to_be_ok()

  text.resolve_anchor(alice, anchor)
  |> expect.to_equal(Error(sequence.UnknownAnchorTarget))
  text.resolve_anchor(text.merge(alice, bob, rid("A")), anchor)
  |> expect.to_equal(Ok(1))
}

pub fn anchor_counts_graphemes_not_codepoints_test() {
  // "👍" and "é" are single graphemes.
  let d = doc("a👍é")
  let anchor = text.anchor_at(d, 3, Before) |> expect.to_be_ok()

  text.resolve_anchor(d, anchor) |> expect.to_be_ok() |> expect.to_equal(3)
  text.resolve_anchor(text.insert(d, 0, "🎉🎉") |> expect.to_be_ok(), anchor)
  |> expect.to_be_ok()
  |> expect.to_equal(5)
}

pub fn multi_grapheme_insert_at_gap_respects_bias_test() {
  let d = doc("ab")
  let before = text.anchor_at(d, 1, Before) |> expect.to_be_ok()
  let after = text.anchor_at(d, 1, After) |> expect.to_be_ok()
  let updated = text.insert(d, 1, "👍👍👍") |> expect.to_be_ok()

  text.resolve_anchor(updated, before)
  |> expect.to_be_ok()
  |> expect.to_equal(4)
  text.resolve_anchor(updated, after) |> expect.to_be_ok() |> expect.to_equal(1)
}

pub fn delete_range_spanning_anchor_collapses_it_test() {
  let d = doc("abcdef")
  let anchor = text.anchor_at(d, 3, Before) |> expect.to_be_ok()
  let updated = text.delete_range(d, 1, 5) |> expect.to_be_ok()

  // "d" was deleted; the anchor collapses to the gap left behind.
  text.resolve_anchor(updated, anchor)
  |> expect.to_be_ok()
  |> expect.to_equal(1)
}

pub fn replace_range_spanning_anchor_test() {
  let d = doc("abcdef")
  let anchor = text.anchor_at(d, 3, Before) |> expect.to_be_ok()
  let updated = text.replace_range(d, 1, 5, "XY") |> expect.to_be_ok()

  // The anchored grapheme "d" is gone; the anchor lands inside the
  // replacement region, still within bounds.
  let resolved = text.resolve_anchor(updated, anchor) |> expect.to_be_ok()
  expect.to_be_true(resolved >= 0 && resolved <= text.length(updated))
}

pub fn delete_range_before_anchor_shifts_it_left_test() {
  let d = doc("abcdef")
  let anchor = text.anchor_at(d, 4, Before) |> expect.to_be_ok()

  text.resolve_anchor(text.delete_range(d, 0, 3) |> expect.to_be_ok(), anchor)
  |> expect.to_be_ok()
  |> expect.to_equal(1)
}

pub fn anchor_survives_merge_of_concurrent_edits_test() {
  let base = doc("abc")
  let anchor = text.anchor_at(base, 2, Before) |> expect.to_be_ok()
  let alice =
    text.merge(text.new(rid("alice")), base, rid("alice"))
    |> text.insert(0, "x")
    |> expect.to_be_ok()
  let bob =
    text.merge(text.new(rid("bob")), base, rid("bob"))
    |> text.delete(0)
    |> expect.to_be_ok()
  let merged = text.merge(alice, bob, rid("A"))

  // Wherever "c" ends up after the merge, the anchor still points at it.
  let resolved = text.resolve_anchor(merged, anchor) |> expect.to_be_ok()
  text.substring(merged, resolved, resolved + 1) |> expect.to_equal("c")
}

pub fn anchor_json_round_trip_test() {
  let d = doc("abc")
  let anchor = text.anchor_at(d, 2, After) |> expect.to_be_ok()
  let assert Ok(decoded) =
    text.anchor_from_json(json.to_string(text.anchor_to_json(anchor)))

  text.resolve_anchor(d, decoded) |> expect.to_be_ok() |> expect.to_equal(2)
  decoded |> expect.to_equal(anchor)
}
