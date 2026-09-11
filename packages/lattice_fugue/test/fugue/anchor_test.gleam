import gleam/result
import lattice_core/replica_id
import lattice_fugue/sequence

fn rid(id: String) {
  replica_id.new(id)
}

fn abc() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> result.try(sequence.insert(_, 1, "b"))
  |> result.try(sequence.insert(_, 2, "c"))
}

pub fn start_anchor_resolves_to_zero_test() {
  let assert Ok(seq) = abc()
  sequence.resolve(seq, sequence.start_anchor())
  |> fn(actual) {
    assert actual == Ok(0)
  }
}

pub fn end_anchor_resolves_to_length_test() {
  let assert Ok(seq) = abc()
  sequence.resolve(seq, sequence.end_anchor())
  |> fn(actual) {
    assert actual == Ok(3)
  }
}

pub fn anchor_before_binds_to_following_item_test() {
  let assert Ok(seq) = abc()
  // Gap before index 1 (between "a" and "b"), bound to "b".
  let assert Ok(anchor) = sequence.anchor_at(seq, 1, sequence.Before)
  // Insert at the front pushes the anchor right with its item.
  let assert Ok(shifted) = sequence.insert(seq, 0, "x")
  sequence.resolve(shifted, anchor)
  |> fn(actual) {
    assert actual == Ok(2)
  }
}

pub fn anchor_after_binds_to_preceding_item_test() {
  let assert Ok(seq) = abc()
  // Gap before index 1, After bias binds to "a" (item at index 0).
  let assert Ok(anchor) = sequence.anchor_at(seq, 1, sequence.After)
  // Insert at the front shifts everything, anchor still sits after "a".
  let assert Ok(shifted) = sequence.insert(seq, 0, "x")
  sequence.resolve(shifted, anchor)
  |> fn(actual) {
    assert actual == Ok(2)
  }
}

pub fn anchor_after_stays_put_on_insert_at_gap_test() {
  let assert Ok(seq) = abc()
  // After bias binds to "a"; inserting at the gap lands after the anchor.
  let assert Ok(anchor) = sequence.anchor_at(seq, 1, sequence.After)
  let assert Ok(updated) = sequence.insert(seq, 1, "z")
  sequence.resolve(updated, anchor)
  |> fn(actual) {
    assert actual == Ok(1)
  }
}

pub fn anchor_before_pushes_right_on_insert_at_gap_test() {
  let assert Ok(seq) = abc()
  // Before bias binds to "b"; inserting at the gap pushes the anchor right.
  let assert Ok(anchor) = sequence.anchor_at(seq, 1, sequence.Before)
  let assert Ok(updated) = sequence.insert(seq, 1, "z")
  sequence.resolve(updated, anchor)
  |> fn(actual) {
    assert actual == Ok(2)
  }
}

pub fn anchor_at_left_boundary_after_degrades_to_start_test() {
  let assert Ok(seq) = abc()
  let assert Ok(anchor) = sequence.anchor_at(seq, 0, sequence.After)
  sequence.resolve(seq, anchor)
  |> fn(actual) {
    assert actual == Ok(0)
  }
}

pub fn anchor_at_right_boundary_before_degrades_to_end_test() {
  let assert Ok(seq) = abc()
  let assert Ok(anchor) = sequence.anchor_at(seq, 3, sequence.Before)
  sequence.resolve(seq, anchor)
  |> fn(actual) {
    assert actual == Ok(3)
  }
}

pub fn anchor_on_deleted_item_collapses_to_gap_test() {
  let assert Ok(seq) = abc()
  // Bind Before to "b" at index 1.
  let assert Ok(anchor) = sequence.anchor_at(seq, 1, sequence.Before)
  // Delete "b"; the anchor collapses to the gap "b" occupied.
  let assert Ok(deleted) = sequence.delete(seq, 1)
  sequence.resolve(deleted, anchor)
  |> fn(actual) {
    assert actual == Ok(1)
  }
}

pub fn anchor_at_out_of_bounds_test() {
  let assert Ok(seq) = abc()
  sequence.anchor_at(seq, 4, sequence.Before)
  |> fn(actual) {
    assert actual == Error(sequence.AnchorIndexOutOfBounds(index: 4, length: 3))
  }
}

pub fn anchor_at_negative_out_of_bounds_test() {
  let assert Ok(seq) = abc()
  sequence.anchor_at(seq, -1, sequence.After)
  |> fn(actual) {
    assert actual
      == Error(sequence.AnchorIndexOutOfBounds(index: -1, length: 3))
  }
}

pub fn resolve_unknown_target_test() {
  // Anchor created on replica B, resolved on a replica that never merged B.
  let assert Ok(seq_b) =
    sequence.new(rid("B"))
    |> sequence.insert(0, "q")
  let assert Ok(anchor) = sequence.anchor_at(seq_b, 1, sequence.After)

  let assert Ok(seq_a) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
  sequence.resolve(seq_a, anchor)
  |> fn(actual) {
    assert actual == Error(sequence.UnknownAnchorTarget)
  }
}

pub fn anchor_survives_merge_test() {
  let assert Ok(seq_a) = abc()
  let assert Ok(anchor) = sequence.anchor_at(seq_a, 2, sequence.After)

  // Concurrent insert on another replica, then merge.
  let assert Ok(seq_b) =
    sequence.new(rid("B"))
    |> sequence.insert(0, "z")
  let merged = sequence.merge(seq_a, seq_b, rid("A"))

  // The anchor still resolves to a valid index bound to "b".
  let assert Ok(index) = sequence.resolve(merged, anchor)
  assert index >= 0 && index <= sequence.length(merged)
}
