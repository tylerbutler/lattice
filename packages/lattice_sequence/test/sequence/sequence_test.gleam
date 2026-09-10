import gleam/dynamic/decode
import gleam/json
import gleam/list
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
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal([42])
}

pub fn insert_appends_at_end_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "h")
  |> expect.to_be_ok()
  |> sequence.insert(1, "i")
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal(["h", "i"])
}

pub fn ten_thousand_items_insert_run_and_merge_delta_preserve_order_and_ids_test() {
  let values = list.repeat(0, 10_000) |> list.index_map(fn(_, index) { index })
  let assert Ok(base) = sequence.insert_many(sequence.new(rid("A")), 0, values)
  let assert Ok(old_anchor) = sequence.anchor_at(base, 9999, sequence.Before)
  let assert Ok(#(updated, delta)) =
    sequence.insert_many_with_delta(base, 9999, [-1, -2])
  let expected = list.append(list.take(values, 9999), [-1, -2, 9999])
  sequence.values(updated) |> expect.to_equal(expected)
  sequence.values(delta) |> expect.to_equal([-1, -2])
  sequence.resolve(updated, old_anchor) |> expect.to_equal(Ok(10_001))
  sequence.anchor_at(updated, 10_001, sequence.Before)
  |> expect.to_equal(Ok(old_anchor))
  sequence.merge(base, delta, rid("A")) |> expect.to_equal(updated)
  sequence.merge(delta, base, rid("A")) |> expect.to_equal(updated)

  let assert Ok(#(appended, append_delta)) =
    sequence.insert_with_delta(updated, 10_002, -3)
  sequence.values(appended) |> expect.to_equal(list.append(expected, [-3]))
  sequence.length(append_delta) |> expect.to_equal(1)
  sequence.merge(updated, append_delta, rid("A")) |> expect.to_equal(appended)
}

pub fn insert_in_middle_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.insert(1, "c")
  |> expect.to_be_ok()
  |> sequence.insert(1, "b")
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal(["a", "b", "c"])
}

pub fn try_insert_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert_with_delta(-1, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: -1, length: 0)))
}

pub fn try_insert_past_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.insert_with_delta(2, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: 2, length: 1)))
}

pub fn delete_removes_visible_item_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.insert(1, "b")
  |> expect.to_be_ok()
  |> sequence.insert(2, "c")
  |> expect.to_be_ok()
  |> sequence.delete(1)
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal(["a", "c"])
}

pub fn try_delete_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.delete_with_delta(-1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: -1, length: 0)),
  )
}

pub fn try_delete_at_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.delete_with_delta(1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: 1, length: 1)),
  )
}

pub fn merge_concurrent_insert_same_position_is_deterministic_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "c")
    |> expect.to_be_ok()
  let alice =
    sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
  let bob =
    sequence.merge(sequence.new(rid("bob")), base, rid("bob"))
    |> sequence.insert(1, "X")
    |> expect.to_be_ok()

  let ab = sequence.merge(alice, bob, rid("A")) |> sequence.values()
  let ba = sequence.merge(bob, alice, rid("A")) |> sequence.values()

  ab |> expect.to_equal(ba)
  ab |> expect.to_equal(["a", "b", "X", "c"])
}

pub fn unicode_order_concurrent_first_inserts_and_deltas_test() {
  // UTF-8 orders U+E000 before U+10000, unlike UTF-16 code units.
  let #(bmp, bmp_delta) =
    sequence.new(rid("\u{e000}"))
    |> sequence.insert_with_delta(0, "b")
    |> expect.to_be_ok()
  let #(supplementary, supplementary_delta) =
    sequence.new(rid("\u{10000}"))
    |> sequence.insert_with_delta(0, "s")
    |> expect.to_be_ok()

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
  ])
  sequence.merge(pair.0, pair.1, rid("observer"))
  |> sequence.values()
  |> expect.to_equal(["b", "s"])
}

pub fn merge_delete_and_insert_after_deleted_anchor_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()

  let alice = base |> sequence.delete(1) |> expect.to_be_ok()
  let bob =
    sequence.merge(sequence.new(rid("B")), base, rid("B"))
    |> sequence.insert(2, "Y")
    |> expect.to_be_ok()

  sequence.merge(alice, bob, rid("A"))
  |> sequence.values()
  |> expect.to_equal(["a", "Y", "c"])
}

pub fn merge_concurrent_runs_do_not_interleave_for_forward_typing_test() {
  let base =
    sequence.new(rid("base")) |> sequence.insert(0, "_") |> expect.to_be_ok()
  let alice =
    sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
    |> sequence.insert(1, "m")
    |> expect.to_be_ok()
    |> sequence.insert(2, "o")
    |> expect.to_be_ok()
    |> sequence.insert(3, "m")
    |> expect.to_be_ok()
  let bob =
    sequence.merge(sequence.new(rid("bob")), base, rid("bob"))
    |> sequence.insert(1, "d")
    |> expect.to_be_ok()
    |> sequence.insert(2, "a")
    |> expect.to_be_ok()
    |> sequence.insert(3, "d")
    |> expect.to_be_ok()

  sequence.merge(alice, bob, rid("A"))
  |> sequence.values()
  |> expect.to_equal(["_", "m", "o", "m", "d", "a", "d"])
}

pub fn merge_applies_insert_delta_test() {
  let base = sequence.new(rid("A"))
  let #(updated, delta) =
    sequence.insert_with_delta(base, 0, "x") |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn merge_applies_delete_delta_test() {
  let base =
    sequence.new(rid("A")) |> sequence.insert(0, "x") |> expect.to_be_ok()
  let #(updated, delta) =
    sequence.delete_with_delta(base, 0) |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn insert_after_delete_at_same_index_is_canonically_ordered_test() {
  // Regression: a local insert whose position is preceded by tombstones must
  // produce the same item order as merge/from_json normalization, so that
  // merge(base, delta, local) structurally equals the directly updated state.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.delete(0)
    |> expect.to_be_ok()
  let #(updated, delta) =
    sequence.insert_with_delta(base, 0, "x") |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
  sequence.values(updated) |> expect.to_equal(["x", "b"])
}

pub fn insert_many_into_empty_test() {
  sequence.new(rid("A"))
  |> sequence.insert_many(0, ["a", "b", "c"])
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal(["a", "b", "c"])
}

pub fn insert_many_in_middle_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.insert(1, "d")
  |> expect.to_be_ok()
  |> sequence.insert_many(1, ["b", "c"])
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal(["a", "b", "c", "d"])
}

pub fn insert_many_empty_list_is_noop_test() {
  let base =
    sequence.new(rid("A")) |> sequence.insert(0, "a") |> expect.to_be_ok()
  base
  |> sequence.insert_many(1, [])
  |> expect.to_be_ok()
  |> expect.to_equal(base)
}

pub fn try_insert_many_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert_many_with_delta(-1, ["x"])
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: -1, length: 0)))
}

pub fn try_insert_many_past_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.insert_many_with_delta(2, ["x"])
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: 2, length: 1)))
}

pub fn insert_many_delta_merges_to_direct_state_test() {
  // The batched delta applied via merge on a peer must structurally equal the
  // directly-updated state — the same invariant single inserts uphold.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "d")
    |> expect.to_be_ok()
  let #(direct, delta) =
    sequence.insert_many_with_delta(base, 1, ["b", "c"]) |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(direct)
}

pub fn insert_many_equivalent_to_looped_inserts_test() {
  // A single batched insert must produce a state structurally identical to
  // inserting the same values one at a time.
  let looped =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "d")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
  let batched =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "d")
    |> expect.to_be_ok()
    |> sequence.insert_many(1, ["b", "c"])
    |> expect.to_be_ok()

  batched |> expect.to_equal(looped)
}

pub fn insert_many_delta_merges_after_tombstone_test() {
  // A batched insert whose position is preceded by tombstones must still
  // reconcile structurally with merge, mirroring the single-insert regression.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.delete(0)
    |> expect.to_be_ok()
  let #(direct, delta) =
    sequence.insert_many_with_delta(base, 0, ["x", "y"]) |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(direct)
  sequence.values(direct) |> expect.to_equal(["x", "y", "b"])
}

pub fn insert_after_move_delta_merges_to_direct_state_test() {
  // With a live move record present the fast path falls back to a full
  // rebuild; the delta must still reconcile structurally with merge.
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
    |> sequence.move(0, 2)
    |> expect.to_be_ok()
  let #(direct, delta) =
    sequence.insert_with_delta(base, 1, "x") |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(direct)
  sequence.values(direct) |> expect.to_equal(["b", "x", "c", "a"])
}

pub fn insert_many_after_move_delta_merges_to_direct_state_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
    |> sequence.move(0, 2)
    |> expect.to_be_ok()
  let #(direct, delta) =
    sequence.insert_many_with_delta(base, 1, ["x", "y"]) |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(direct)
  sequence.values(direct) |> expect.to_equal(["b", "x", "y", "c", "a"])
}

pub fn move_reorders_visible_item_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.insert(1, "b")
  |> expect.to_be_ok()
  |> sequence.insert(2, "c")
  |> expect.to_be_ok()
  |> sequence.move(0, 2)
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal(["b", "c", "a"])
}

pub fn try_move_from_index_out_of_bounds_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.move_with_delta(1, 0)
  |> expect.to_equal(
    Error(sequence.MoveFromIndexOutOfBounds(index: 1, length: 1)),
  )
}

pub fn try_move_to_index_out_of_bounds_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> expect.to_be_ok()
  |> sequence.move_with_delta(0, 2)
  |> expect.to_equal(
    Error(sequence.MoveToIndexOutOfBounds(index: 2, length_after_removal: 0)),
  )
}

pub fn move_delta_merges_to_direct_state_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
  let #(direct, delta) =
    sequence.move_with_delta(base, 0, 2) |> expect.to_be_ok()

  sequence.merge(base, delta, rid("A"))
  |> expect.to_equal(direct)
}

pub fn repeated_move_delta_is_idempotent_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
  let #(direct, delta) =
    sequence.move_with_delta(base, 0, 2) |> expect.to_be_ok()

  sequence.merge(sequence.merge(base, delta, rid("A")), delta, rid("A"))
  |> expect.to_equal(direct)
}

pub fn concurrent_moves_of_same_item_converge_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
    |> sequence.insert(3, "d")
    |> expect.to_be_ok()
  let alice =
    sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
    |> sequence.move(1, 0)
    |> expect.to_be_ok()
  let bob =
    sequence.merge(sequence.new(rid("bob")), base, rid("bob"))
    |> sequence.move(1, 2)
    |> expect.to_be_ok()

  let ab = sequence.merge(alice, bob, rid("A")) |> sequence.values()
  let ba = sequence.merge(bob, alice, rid("A")) |> sequence.values()

  ab |> expect.to_equal(ba)
  ab |> expect.to_equal(["a", "c", "b", "d"])
}

pub fn unicode_order_competing_moves_of_same_item_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert_many(0, ["a", "b", "c", "d"])
    |> expect.to_be_ok()
  let #(bmp, bmp_delta) =
    sequence.merge(sequence.new(rid("\u{e000}")), base, rid("\u{e000}"))
    |> sequence.move_with_delta(1, 0)
    |> expect.to_be_ok()
  let #(supplementary, supplementary_delta) =
    sequence.merge(sequence.new(rid("\u{10000}")), base, rid("\u{10000}"))
    |> sequence.move_with_delta(1, 2)
    |> expect.to_be_ok()

  sequence.values(bmp) |> expect.to_equal(["b", "a", "c", "d"])
  sequence.values(supplementary) |> expect.to_equal(["a", "c", "b", "d"])
  let move_counters =
    decode.at(
      ["state", "segments"],
      decode.list(decode.at(["move", "op_id", "counter"], decode.int)),
    )
  list.each([bmp_delta, supplementary_delta], fn(delta) {
    sequence.to_json(delta, json.string)
    |> json.to_string()
    |> json.parse(move_counters)
    |> expect.to_equal(Ok([5]))
  })

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
  ])
  sequence.merge(pair.0, pair.1, rid("observer"))
  |> sequence.values()
  |> expect.to_equal(["a", "c", "b", "d"])
}

pub fn unicode_order_different_item_moves_into_same_gap_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert_many(0, ["L", "R", "b", "s"])
    |> expect.to_be_ok()
  let #(bmp, bmp_delta) =
    sequence.merge(sequence.new(rid("\u{e000}")), base, rid("\u{e000}"))
    |> sequence.move_with_delta(2, 1)
    |> expect.to_be_ok()
  let #(supplementary, supplementary_delta) =
    sequence.merge(sequence.new(rid("\u{10000}")), base, rid("\u{10000}"))
    |> sequence.move_with_delta(3, 1)
    |> expect.to_be_ok()

  sequence.values(bmp) |> expect.to_equal(["L", "b", "R", "s"])
  sequence.values(supplementary) |> expect.to_equal(["L", "s", "R", "b"])
  let move_counters =
    decode.at(
      ["state", "segments"],
      decode.list(decode.at(["move", "op_id", "counter"], decode.int)),
    )
  list.each([bmp_delta, supplementary_delta], fn(delta) {
    sequence.to_json(delta, json.string)
    |> json.to_string()
    |> json.parse(move_counters)
    |> expect.to_equal(Ok([5]))
  })

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
  ])
  sequence.merge(pair.0, pair.1, rid("observer"))
  |> sequence.values()
  |> expect.to_equal(["L", "b", "s", "R"])
}

pub fn causal_later_move_wins_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
    |> sequence.insert(3, "d")
    |> expect.to_be_ok()
  let first =
    sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
    |> sequence.move(1, 0)
    |> expect.to_be_ok()
  let later =
    sequence.merge(sequence.new(rid("bob")), first, rid("bob"))
    |> sequence.move(0, 3)
    |> expect.to_be_ok()

  sequence.merge(first, later, rid("A"))
  |> sequence.values()
  |> expect.to_equal(["a", "c", "d", "b"])
}

pub fn concurrent_move_and_delete_delete_wins_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
  let moved =
    sequence.merge(sequence.new(rid("mover")), base, rid("mover"))
    |> sequence.move(1, 0)
    |> expect.to_be_ok()
  let deleted =
    sequence.merge(sequence.new(rid("deleter")), base, rid("deleter"))
    |> sequence.delete(1)
    |> expect.to_be_ok()

  sequence.merge(moved, deleted, rid("A"))
  |> sequence.values()
  |> expect.to_equal(["a", "c"])
}

pub fn move_after_descendant_does_not_drop_items_test() {
  let base =
    sequence.new(rid("base"))
    |> sequence.insert(0, "a")
    |> expect.to_be_ok()
    |> sequence.insert(1, "b")
    |> expect.to_be_ok()
    |> sequence.insert(2, "c")
    |> expect.to_be_ok()
  let moved = base |> sequence.move(0, 1) |> expect.to_be_ok()

  moved
  |> sequence.values()
  |> expect.to_equal(["b", "a", "c"])
  sequence.length(moved) |> expect.to_equal(3)
}

pub fn merge_uses_explicit_identity_when_delta_is_first_test() {
  // Reversing delta application must not give A the sender's identity.
  let base =
    sequence.new(rid("A")) |> sequence.insert(0, "a") |> expect.to_be_ok()
  let #(b_state, b_delta) =
    sequence.merge(sequence.new(rid("B")), base, rid("B"))
    |> sequence.insert_with_delta(1, "b")
    |> expect.to_be_ok()

  let a_state =
    sequence.merge(b_delta, base, rid("A"))
    |> sequence.insert(2, "x")
    |> expect.to_be_ok()
  let b_state = sequence.insert(b_state, 2, "c") |> expect.to_be_ok()

  sequence.merge(a_state, b_state, rid("A"))
  |> sequence.length()
  |> expect.to_equal(4)
}

pub fn merge_as_keeps_local_identity_whatever_the_argument_order_test() {
  let base =
    sequence.new(rid("A")) |> sequence.insert(0, "a") |> expect.to_be_ok()
  let #(b_state, b_delta) =
    sequence.merge(sequence.new(rid("B")), base, rid("B"))
    |> sequence.insert_with_delta(1, "b")
    |> expect.to_be_ok()

  // The alias has the same explicit-identity contract as canonical merge.
  let a_state =
    sequence.merge_as(b_delta, base, rid("A"))
    |> sequence.insert(2, "x")
    |> expect.to_be_ok()
  let b_state = sequence.insert(b_state, 2, "c") |> expect.to_be_ok()

  sequence.merge(a_state, b_state, rid("A"))
  |> sequence.length()
  |> expect.to_equal(4)
}

pub fn merge_as_is_argument_order_independent_test() {
  let base =
    sequence.new(rid("A")) |> sequence.insert(0, "a") |> expect.to_be_ok()
  let #(_, b_delta) =
    sequence.merge(sequence.new(rid("B")), base, rid("B"))
    |> sequence.insert_with_delta(1, "b")
    |> expect.to_be_ok()

  sequence.merge_as(base, b_delta, rid("A"))
  |> expect.to_equal(sequence.merge_as(b_delta, base, rid("A")))
}

pub fn co_gap_movers_stack_in_op_order_across_resolution_paths_test() {
  // Three concurrent moves land in the same gap (between "L" and "R") but
  // resolve differently: the ones anchored on the later-moved "e" lose their
  // right boundary (it is itself a mover, stripped for this pass) and fall
  // back to the gap's left anchor, while the one anchored on "R" keeps its
  // right boundary. Whichever path each takes, they must stack left to right
  // in op order.
  let base =
    sequence.new(rid("Z"))
    |> sequence.insert(0, "L")
    |> expect.to_be_ok()
    |> sequence.insert(1, "e")
    |> expect.to_be_ok()
    |> sequence.insert(2, "R")
    |> expect.to_be_ok()
    |> sequence.insert(3, "c")
    |> expect.to_be_ok()
    |> sequence.insert(4, "d")
    |> expect.to_be_ok()
    |> sequence.insert(5, "b")
    |> expect.to_be_ok()

  // All three moves get the same counter, so replica id breaks the tie:
  // A ("c") < B ("d") < C ("b").
  let a =
    sequence.merge(sequence.new(rid("A")), base, rid("A"))
    |> sequence.move(3, 1)
    |> expect.to_be_ok()
  let b =
    sequence.merge(sequence.new(rid("B")), base, rid("B"))
    |> sequence.move(4, 2)
    |> expect.to_be_ok()
  let c =
    sequence.merge(sequence.new(rid("C")), base, rid("C"))
    |> sequence.move(5, 1)
    |> expect.to_be_ok()

  // Moving "e" last turns it into a mover, so it is no longer a usable right
  // boundary for the moves that anchored on it.
  sequence.merge(sequence.merge(a, b, rid("A")), c, rid("A"))
  |> sequence.move(3, 5)
  |> expect.to_be_ok()
  |> sequence.values()
  |> expect.to_equal(["L", "c", "d", "b", "R", "e"])
}
