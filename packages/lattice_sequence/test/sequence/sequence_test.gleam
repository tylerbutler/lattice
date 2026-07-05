import lattice_core/replica_id
import lattice_sequence/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_values_is_empty_test() {
  sequence.new(rid("A"))
  |> sequence.values()
  |> expect.to_equal([])
}

pub fn new_length_is_zero_test() {
  sequence.new(rid("A"))
  |> sequence.length()
  |> expect.to_equal(0)
}

pub fn insert_integer_into_empty_sequence_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, 42)
  |> sequence.values()
  |> expect.to_equal([42])
}

pub fn insert_appends_at_end_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "h")
  |> sequence.insert(1, "i")
  |> sequence.values()
  |> expect.to_equal(["h", "i"])
}

pub fn insert_in_middle_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "c")
  |> sequence.insert(1, "b")
  |> sequence.values()
  |> expect.to_equal(["a", "b", "c"])
}

pub fn try_insert_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.try_insert_with_delta(-1, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: -1, length: 0)))
}

pub fn try_insert_past_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.try_insert_with_delta(2, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: 2, length: 1)))
}

pub fn delete_removes_visible_item_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "b")
  |> sequence.insert(2, "c")
  |> sequence.delete(1)
  |> sequence.values()
  |> expect.to_equal(["a", "c"])
}

pub fn try_delete_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.try_delete_with_delta(-1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: -1, length: 0)),
  )
}

pub fn try_delete_at_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.try_delete_with_delta(1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: 1, length: 1)),
  )
}

pub fn merge_concurrent_insert_same_position_is_deterministic_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "c")
  let alice =
    sequence.merge(sequence.new(rid("alice")), base)
    |> sequence.insert(1, "b")
  let bob =
    sequence.merge(sequence.new(rid("bob")), base)
    |> sequence.insert(1, "X")

  let ab = sequence.merge(alice, bob) |> sequence.values()
  let ba = sequence.merge(bob, alice) |> sequence.values()

  ab |> expect.to_equal(ba)
  ab |> expect.to_equal(["a", "b", "X", "c"])
}

pub fn merge_delete_and_insert_after_deleted_anchor_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")

  let alice = base |> sequence.delete(1)
  let bob =
    sequence.merge(sequence.new(rid("B")), base) |> sequence.insert(2, "Y")

  sequence.merge(alice, bob)
  |> sequence.values()
  |> expect.to_equal(["a", "Y", "c"])
}

pub fn merge_concurrent_runs_do_not_interleave_for_forward_typing_test() {
  let base = sequence.new(rid("base")) |> sequence.insert(0, "_")
  let alice =
    sequence.merge(sequence.new(rid("alice")), base)
    |> sequence.insert(1, "m")
    |> sequence.insert(2, "o")
    |> sequence.insert(3, "m")
  let bob =
    sequence.merge(sequence.new(rid("bob")), base)
    |> sequence.insert(1, "d")
    |> sequence.insert(2, "a")
    |> sequence.insert(3, "d")

  sequence.merge(alice, bob)
  |> sequence.values()
  |> expect.to_equal(["_", "m", "o", "m", "d", "a", "d"])
}

pub fn merge_applies_insert_delta_test() {
  let base = sequence.new(rid("A"))
  let #(updated, delta) = sequence.insert_with_delta(base, 0, "x")

  sequence.merge(base, delta)
  |> expect.to_equal(updated)
}

pub fn merge_applies_delete_delta_test() {
  let base = sequence.new(rid("A")) |> sequence.insert(0, "x")
  let #(updated, delta) = sequence.delete_with_delta(base, 0)

  sequence.merge(base, delta)
  |> expect.to_equal(updated)
}

pub fn insert_after_delete_at_same_index_is_canonically_ordered_test() {
  // Regression: a local insert whose position is preceded by tombstones must
  // produce the same item order as merge/from_json normalization, so that
  // merge(base, delta) structurally equals the directly updated state.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.delete(0)
  let #(updated, delta) = sequence.insert_with_delta(base, 0, "x")

  sequence.merge(base, delta)
  |> expect.to_equal(updated)
  sequence.values(updated) |> expect.to_equal(["x", "b"])
}

pub fn move_reorders_visible_item_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "b")
  |> sequence.insert(2, "c")
  |> sequence.move(0, 2)
  |> sequence.values()
  |> expect.to_equal(["b", "c", "a"])
}

pub fn try_move_from_index_out_of_bounds_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.try_move_with_delta(1, 0)
  |> expect.to_equal(
    Error(sequence.MoveFromIndexOutOfBounds(index: 1, length: 1)),
  )
}

pub fn try_move_to_index_out_of_bounds_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.try_move_with_delta(0, 2)
  |> expect.to_equal(
    Error(sequence.MoveToIndexOutOfBounds(index: 2, length_after_removal: 0)),
  )
}

pub fn move_delta_merges_to_direct_state_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  let #(direct, delta) = sequence.move_with_delta(base, 0, 2)

  sequence.merge(base, delta)
  |> expect.to_equal(direct)
}

pub fn repeated_move_delta_is_idempotent_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  let #(direct, delta) = sequence.move_with_delta(base, 0, 2)

  sequence.merge(sequence.merge(base, delta), delta)
  |> expect.to_equal(direct)
}

pub fn concurrent_moves_of_same_item_converge_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
    |> sequence.insert(3, "d")
  let alice =
    sequence.merge(sequence.new(rid("alice")), base)
    |> sequence.move(1, 0)
  let bob =
    sequence.merge(sequence.new(rid("bob")), base)
    |> sequence.move(1, 2)

  let ab = sequence.merge(alice, bob) |> sequence.values()
  let ba = sequence.merge(bob, alice) |> sequence.values()

  ab |> expect.to_equal(ba)
  ab |> expect.to_equal(["a", "c", "b", "d"])
}

pub fn causal_later_move_wins_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
    |> sequence.insert(3, "d")
  let first =
    sequence.merge(sequence.new(rid("alice")), base)
    |> sequence.move(1, 0)
  let later =
    sequence.merge(sequence.new(rid("bob")), first)
    |> sequence.move(0, 3)

  sequence.merge(first, later)
  |> sequence.values()
  |> expect.to_equal(["a", "c", "d", "b"])
}

pub fn concurrent_move_and_delete_delete_wins_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  let moved =
    sequence.merge(sequence.new(rid("mover")), base)
    |> sequence.move(1, 0)
  let deleted =
    sequence.merge(sequence.new(rid("deleter")), base)
    |> sequence.delete(1)

  sequence.merge(moved, deleted)
  |> sequence.values()
  |> expect.to_equal(["a", "c"])
}

pub fn move_after_descendant_does_not_drop_items_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  let moved = base |> sequence.move(0, 1)

  moved
  |> sequence.values()
  |> expect.to_equal(["b", "a", "c"])
  sequence.length(moved) |> expect.to_equal(3)
}
