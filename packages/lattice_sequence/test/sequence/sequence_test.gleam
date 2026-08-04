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

pub fn insert_many_into_empty_test() {
  sequence.new(rid("A"))
  |> sequence.insert_many(0, ["a", "b", "c"])
  |> sequence.values()
  |> expect.to_equal(["a", "b", "c"])
}

pub fn insert_many_in_middle_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "d")
  |> sequence.insert_many(1, ["b", "c"])
  |> sequence.values()
  |> expect.to_equal(["a", "b", "c", "d"])
}

pub fn insert_many_empty_list_is_noop_test() {
  let base = sequence.new(rid("A")) |> sequence.insert(0, "a")
  base
  |> sequence.insert_many(1, [])
  |> expect.to_equal(base)
}

pub fn try_insert_many_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.try_insert_many_with_delta(-1, ["x"])
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: -1, length: 0)))
}

pub fn try_insert_many_past_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.try_insert_many_with_delta(2, ["x"])
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: 2, length: 1)))
}

pub fn insert_many_delta_merges_to_direct_state_test() {
  // The batched delta applied via merge on a peer must structurally equal the
  // directly-updated state — the same invariant single inserts uphold.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "d")
  let #(direct, delta) = sequence.insert_many_with_delta(base, 1, ["b", "c"])

  sequence.merge(base, delta)
  |> expect.to_equal(direct)
}

pub fn insert_many_equivalent_to_looped_inserts_test() {
  // A single batched insert must produce a state structurally identical to
  // inserting the same values one at a time.
  let looped =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "d")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  let batched =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "d")
    |> sequence.insert_many(1, ["b", "c"])

  batched |> expect.to_equal(looped)
}

pub fn insert_many_delta_merges_after_tombstone_test() {
  // A batched insert whose position is preceded by tombstones must still
  // reconcile structurally with merge, mirroring the single-insert regression.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.delete(0)
  let #(direct, delta) = sequence.insert_many_with_delta(base, 0, ["x", "y"])

  sequence.merge(base, delta)
  |> expect.to_equal(direct)
  sequence.values(direct) |> expect.to_equal(["x", "y", "b"])
}

pub fn insert_after_move_delta_merges_to_direct_state_test() {
  // With a live move record present the fast path falls back to a full
  // rebuild; the delta must still reconcile structurally with merge.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
    |> sequence.move(0, 2)
  let #(direct, delta) = sequence.insert_with_delta(base, 1, "x")

  sequence.merge(base, delta)
  |> expect.to_equal(direct)
  sequence.values(direct) |> expect.to_equal(["b", "x", "c", "a"])
}

pub fn insert_many_after_move_delta_merges_to_direct_state_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
    |> sequence.move(0, 2)
  let #(direct, delta) = sequence.insert_many_with_delta(base, 1, ["x", "y"])

  sequence.merge(base, delta)
  |> expect.to_equal(direct)
  sequence.values(direct) |> expect.to_equal(["b", "x", "y", "c", "a"])
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

pub fn merge_adopts_the_first_arguments_replica_identity_test() {
  // Pins the `merge(self, other)` contract: identity is positional, so
  // applying a remote delta as the FIRST argument re-mints local edits under
  // the remote's replica id and they collide with that replica's own edits.
  // `merge_as` is the order-independent alternative (see the test below).
  let base = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let #(b_state, b_delta) =
    sequence.merge(sequence.new(rid("B")), base)
    |> sequence.insert_with_delta(1, "b")

  let a_state = sequence.merge(b_delta, base) |> sequence.insert(2, "x")
  let b_state = sequence.insert(b_state, 2, "c")

  sequence.merge(a_state, b_state)
  |> sequence.length()
  |> expect.to_equal(3)
}

pub fn merge_as_keeps_local_identity_whatever_the_argument_order_test() {
  let base = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let #(b_state, b_delta) =
    sequence.merge(sequence.new(rid("B")), base)
    |> sequence.insert_with_delta(1, "b")

  // Same reversed call as above, but stating the local identity keeps A
  // minting under its own id, so nothing collides with B's next insert.
  let a_state =
    sequence.merge_as(b_delta, base, rid("A")) |> sequence.insert(2, "x")
  let b_state = sequence.insert(b_state, 2, "c")

  sequence.merge(a_state, b_state)
  |> sequence.length()
  |> expect.to_equal(4)
}

pub fn merge_as_is_argument_order_independent_test() {
  let base = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let #(_, b_delta) =
    sequence.merge(sequence.new(rid("B")), base)
    |> sequence.insert_with_delta(1, "b")

  sequence.merge_as(base, b_delta, rid("A"))
  |> expect.to_equal(sequence.merge_as(b_delta, base, rid("A")))
}
