import lattice_core/replica_id
import lattice_sequence/sequence.{After, Before}
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn abc() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "b")
  |> sequence.insert(2, "c")
}

pub fn start_anchor_resolves_to_zero_test() {
  let seq = abc()
  sequence.resolve(seq, sequence.start_anchor())
  |> expect.to_equal(0)
}

pub fn start_anchor_stays_at_zero_after_insert_at_front_test() {
  let seq = abc() |> sequence.insert(0, "x")
  sequence.resolve(seq, sequence.start_anchor())
  |> expect.to_equal(0)
}

pub fn end_anchor_tracks_growth_test() {
  let anchor = sequence.end_anchor()
  let seq = abc()

  sequence.resolve(seq, anchor) |> expect.to_equal(3)
  sequence.resolve(sequence.insert(seq, 3, "d"), anchor) |> expect.to_equal(4)
  sequence.resolve(sequence.new(rid("A")), anchor) |> expect.to_equal(0)
}

pub fn try_anchor_at_negative_index_returns_error_test() {
  abc()
  |> sequence.try_anchor_at(-1, Before)
  |> expect.to_equal(
    Error(sequence.AnchorIndexOutOfBounds(index: -1, length: 3)),
  )
}

pub fn try_anchor_at_past_length_returns_error_test() {
  abc()
  |> sequence.try_anchor_at(4, After)
  |> expect.to_equal(
    Error(sequence.AnchorIndexOutOfBounds(index: 4, length: 3)),
  )
}

pub fn try_anchor_at_length_is_valid_test() {
  let seq = abc()
  let assert Ok(anchor) = sequence.try_anchor_at(seq, 3, Before)
  sequence.resolve(seq, anchor) |> expect.to_equal(3)
}

pub fn anchor_at_length_with_before_bias_degrades_to_end_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 3, Before)

  // A true End sentinel tracks growth at the tail.
  sequence.resolve(sequence.insert(seq, 3, "d"), anchor)
  |> expect.to_equal(4)
}

pub fn anchor_at_zero_with_after_bias_degrades_to_start_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 0, After)

  // A true Start sentinel stays at 0 even when content is inserted at 0.
  sequence.resolve(sequence.insert(seq, 0, "x"), anchor)
  |> expect.to_equal(0)
}

pub fn anchor_on_empty_sequence_resolves_to_zero_test() {
  let seq = sequence.new(rid("A"))

  sequence.resolve(seq, sequence.anchor_at(seq, 0, Before))
  |> expect.to_equal(0)
  sequence.resolve(seq, sequence.anchor_at(seq, 0, After))
  |> expect.to_equal(0)
}

pub fn create_then_resolve_is_identity_test() {
  let seq = abc()

  sequence.resolve(seq, sequence.anchor_at(seq, 0, Before))
  |> expect.to_equal(0)
  sequence.resolve(seq, sequence.anchor_at(seq, 1, Before))
  |> expect.to_equal(1)
  sequence.resolve(seq, sequence.anchor_at(seq, 1, After))
  |> expect.to_equal(1)
  sequence.resolve(seq, sequence.anchor_at(seq, 2, After))
  |> expect.to_equal(2)
  sequence.resolve(seq, sequence.anchor_at(seq, 3, After))
  |> expect.to_equal(3)
}

pub fn insert_before_anchor_shifts_it_right_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 2, Before)

  sequence.resolve(sequence.insert(seq, 0, "x"), anchor)
  |> expect.to_equal(3)
}

pub fn delete_before_anchor_shifts_it_left_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 2, Before)

  sequence.resolve(sequence.delete(seq, 0), anchor)
  |> expect.to_equal(1)
}

pub fn insert_after_anchor_does_not_move_it_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 1, After)

  sequence.resolve(sequence.insert(seq, 2, "x"), anchor)
  |> expect.to_equal(1)
}

pub fn bias_diverges_for_insert_exactly_at_the_gap_test() {
  let seq = abc()
  let before = sequence.anchor_at(seq, 1, Before)
  let after = sequence.anchor_at(seq, 1, After)
  let updated = sequence.insert(seq, 1, "x")

  // Before stays glued to "b", which was pushed right.
  sequence.resolve(updated, before) |> expect.to_equal(2)
  // After stays glued to "a", so the insert lands after the anchor.
  sequence.resolve(updated, after) |> expect.to_equal(1)
}

pub fn anchor_survives_deletion_of_its_item_test() {
  let seq = abc()
  let before = sequence.anchor_at(seq, 1, Before)
  let after = sequence.anchor_at(seq, 2, After)
  // Both anchors bind to "b"; delete it.
  let updated = sequence.delete(seq, 1)

  // Both biases collapse to the gap where "b" used to be.
  sequence.resolve(updated, before) |> expect.to_equal(1)
  sequence.resolve(updated, after) |> expect.to_equal(1)
}

pub fn anchor_follows_moved_item_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 0, Before)
  // Move "a" to the end: "bca".
  let updated = sequence.move(seq, 0, 2)

  sequence.resolve(updated, anchor) |> expect.to_equal(2)
}

pub fn try_resolve_unknown_target_before_merge_errors_test() {
  let alice = abc()
  let bob =
    sequence.merge(sequence.new(rid("B")), alice)
    |> sequence.insert(1, "x")
  let anchor = sequence.anchor_at(bob, 1, Before)

  // Alice has never seen Bob's item.
  sequence.try_resolve(alice, anchor)
  |> expect.to_equal(Error(sequence.UnknownAnchorTarget))

  // After merging Bob's state, the anchor resolves.
  sequence.try_resolve(sequence.merge(alice, bob), anchor)
  |> expect.to_equal(Ok(1))
}

pub fn resolution_agrees_across_replicas_after_merge_test() {
  let base = abc()
  let anchor = sequence.anchor_at(base, 2, Before)
  let alice =
    sequence.merge(sequence.new(rid("alice")), base)
    |> sequence.insert(0, "x")
  let bob =
    sequence.merge(sequence.new(rid("bob")), base)
    |> sequence.insert(3, "y")

  sequence.resolve(sequence.merge(alice, bob), anchor)
  |> expect.to_equal(sequence.resolve(sequence.merge(bob, alice), anchor))
}

pub fn anchor_creation_and_resolution_do_not_mutate_state_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 1, Before)
  let _ = sequence.resolve(seq, anchor)

  // Creating and resolving anchors must not bump the counter or add items:
  // the next insert behaves exactly as it would on an untouched sequence.
  sequence.insert(seq, 1, "x")
  |> expect.to_equal(sequence.insert(abc(), 1, "x"))
}
