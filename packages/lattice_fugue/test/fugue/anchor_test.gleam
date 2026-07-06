import lattice_core/replica_id
import lattice_fugue/sequence
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

pub fn end_anchor_resolves_to_length_test() {
  let seq = abc()
  sequence.resolve(seq, sequence.end_anchor())
  |> expect.to_equal(3)
}

pub fn anchor_before_binds_to_following_item_test() {
  let seq = abc()
  // Gap before index 1 (between "a" and "b"), bound to "b".
  let anchor = sequence.anchor_at(seq, 1, sequence.Before)
  // Insert at the front pushes the anchor right with its item.
  let shifted = sequence.insert(seq, 0, "x")
  sequence.resolve(shifted, anchor)
  |> expect.to_equal(2)
}

pub fn anchor_after_binds_to_preceding_item_test() {
  let seq = abc()
  // Gap before index 1, After bias binds to "a" (item at index 0).
  let anchor = sequence.anchor_at(seq, 1, sequence.After)
  // Insert at the front shifts everything, anchor still sits after "a".
  let shifted = sequence.insert(seq, 0, "x")
  sequence.resolve(shifted, anchor)
  |> expect.to_equal(2)
}

pub fn anchor_after_stays_put_on_insert_at_gap_test() {
  let seq = abc()
  // After bias binds to "a"; inserting at the gap lands after the anchor.
  let anchor = sequence.anchor_at(seq, 1, sequence.After)
  let updated = sequence.insert(seq, 1, "z")
  sequence.resolve(updated, anchor)
  |> expect.to_equal(1)
}

pub fn anchor_before_pushes_right_on_insert_at_gap_test() {
  let seq = abc()
  // Before bias binds to "b"; inserting at the gap pushes the anchor right.
  let anchor = sequence.anchor_at(seq, 1, sequence.Before)
  let updated = sequence.insert(seq, 1, "z")
  sequence.resolve(updated, anchor)
  |> expect.to_equal(2)
}

pub fn anchor_at_left_boundary_after_degrades_to_start_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 0, sequence.After)
  sequence.resolve(seq, anchor)
  |> expect.to_equal(0)
}

pub fn anchor_at_right_boundary_before_degrades_to_end_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 3, sequence.Before)
  sequence.resolve(seq, anchor)
  |> expect.to_equal(3)
}

pub fn anchor_on_deleted_item_collapses_to_gap_test() {
  let seq = abc()
  // Bind Before to "b" at index 1.
  let anchor = sequence.anchor_at(seq, 1, sequence.Before)
  // Delete "b"; the anchor collapses to the gap "b" occupied.
  let deleted = sequence.delete(seq, 1)
  sequence.resolve(deleted, anchor)
  |> expect.to_equal(1)
}

pub fn try_anchor_at_out_of_bounds_test() {
  let seq = abc()
  sequence.try_anchor_at(seq, 4, sequence.Before)
  |> expect.to_equal(
    Error(sequence.AnchorIndexOutOfBounds(index: 4, length: 3)),
  )
}

pub fn try_anchor_at_negative_out_of_bounds_test() {
  let seq = abc()
  sequence.try_anchor_at(seq, -1, sequence.After)
  |> expect.to_equal(
    Error(sequence.AnchorIndexOutOfBounds(index: -1, length: 3)),
  )
}

pub fn try_resolve_unknown_target_test() {
  // Anchor created on replica B, resolved on a replica that never merged B.
  let seq_b =
    sequence.new(rid("B"))
    |> sequence.insert(0, "q")
  let anchor = sequence.anchor_at(seq_b, 1, sequence.After)

  let seq_a =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
  sequence.try_resolve(seq_a, anchor)
  |> expect.to_equal(Error(sequence.UnknownAnchorTarget))
}

pub fn anchor_survives_merge_test() {
  let seq_a = abc()
  let anchor = sequence.anchor_at(seq_a, 2, sequence.After)

  // Concurrent insert on another replica, then merge.
  let seq_b =
    sequence.new(rid("B"))
    |> sequence.insert(0, "z")
  let merged = sequence.merge(seq_a, seq_b)

  // The anchor still resolves to a valid index bound to "b".
  let index = sequence.resolve(merged, anchor)
  expect.to_be_true(index >= 0 && index <= sequence.length(merged))
}
