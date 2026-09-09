import lattice_core/replica_id
import lattice_sequence/sequence
import lattice_text/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_value_is_empty_test() {
  text.new(rid("A"))
  |> text.value()
  |> expect.to_equal("")
}

pub fn new_values_is_empty_test() {
  text.new(rid("A"))
  |> text.values()
  |> expect.to_equal([])
}

pub fn insert_into_empty_text_test() {
  text.new(rid("A"))
  |> text.insert(0, "h")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("h")
}

pub fn insert_appends_at_end_test() {
  text.new(rid("A"))
  |> text.insert(0, "h")
  |> expect.to_be_ok()
  |> text.insert(1, "i")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("hi")
}

pub fn insert_in_middle_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> expect.to_be_ok()
  |> text.insert(1, "c")
  |> expect.to_be_ok()
  |> text.insert(1, "b")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("abc")
}

pub fn insert_multi_character_value_uses_character_indexes_test() {
  text.new(rid("A"))
  |> text.insert(0, "hi")
  |> expect.to_be_ok()
  |> text.insert(1, "!")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("h!i")
}

pub fn insert_multi_grapheme_value_preserves_each_grapheme_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍")
  |> expect.to_be_ok()
  |> text.insert(1, "!")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("a!👍")
}

pub fn try_insert_negative_index_returns_error_test() {
  text.new(rid("A"))
  |> text.insert_with_delta(-1, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: -1, length: 0)))
}

pub fn try_insert_past_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> expect.to_be_ok()
  |> text.insert_with_delta(2, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: 2, length: 1)))
}

pub fn delete_removes_visible_unit_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> expect.to_be_ok()
  |> text.insert(1, "b")
  |> expect.to_be_ok()
  |> text.insert(2, "c")
  |> expect.to_be_ok()
  |> text.delete(1)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("ac")
}

pub fn delete_removes_character_from_multi_character_insert_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.delete(1)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("ac")
}

pub fn try_delete_negative_index_returns_error_test() {
  text.new(rid("A"))
  |> text.delete_with_delta(-1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: -1, length: 0)),
  )
}

pub fn try_delete_at_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> expect.to_be_ok()
  |> text.delete_with_delta(1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: 1, length: 1)),
  )
}

pub fn merge_concurrent_insert_same_position_is_deterministic_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> expect.to_be_ok()
    |> text.insert(1, "c")
    |> expect.to_be_ok()
  let alice =
    text.merge(text.new(rid("alice")), base, rid("alice"))
    |> text.insert(1, "b")
    |> expect.to_be_ok()
  let bob =
    text.merge(text.new(rid("bob")), base, rid("bob"))
    |> text.insert(1, "X")
    |> expect.to_be_ok()

  let ab = text.merge(alice, bob, rid("A")) |> text.value()
  let ba = text.merge(bob, alice, rid("A")) |> text.value()

  ab |> expect.to_equal(ba)
  ab |> expect.to_equal("abXc")
}

pub fn merge_delete_and_insert_after_deleted_anchor_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> expect.to_be_ok()
    |> text.insert(1, "b")
    |> expect.to_be_ok()
    |> text.insert(2, "c")
    |> expect.to_be_ok()

  let alice = base |> text.delete(1) |> expect.to_be_ok()
  let bob =
    text.merge(text.new(rid("B")), base, rid("B"))
    |> text.insert(2, "Y")
    |> expect.to_be_ok()

  text.merge(alice, bob, rid("A"))
  |> text.value()
  |> expect.to_equal("aYc")
}

pub fn merge_concurrent_runs_do_not_interleave_for_forward_typing_test() {
  let base = text.new(rid("base")) |> text.insert(0, "_") |> expect.to_be_ok()
  let alice =
    text.merge(text.new(rid("alice")), base, rid("alice"))
    |> text.insert(1, "m")
    |> expect.to_be_ok()
    |> text.insert(2, "o")
    |> expect.to_be_ok()
    |> text.insert(3, "m")
    |> expect.to_be_ok()
  let bob =
    text.merge(text.new(rid("bob")), base, rid("bob"))
    |> text.insert(1, "d")
    |> expect.to_be_ok()
    |> text.insert(2, "a")
    |> expect.to_be_ok()
    |> text.insert(3, "d")
    |> expect.to_be_ok()

  text.merge(alice, bob, rid("A"))
  |> text.value()
  |> expect.to_equal("_momdad")
}

pub fn merge_applies_insert_delta_test() {
  let base = text.new(rid("A"))
  let #(updated, delta) =
    text.insert_with_delta(base, 0, "x") |> expect.to_be_ok()

  text.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn merge_applies_multi_character_insert_delta_test() {
  let base = text.new(rid("A"))
  let #(updated, delta) =
    text.insert_with_delta(base, 0, "hi") |> expect.to_be_ok()

  text.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn empty_insert_returns_empty_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "abc") |> expect.to_be_ok()
  let #(updated, delta) =
    text.insert_with_delta(base, 1, "") |> expect.to_be_ok()

  expect.to_equal(updated, base)
  text.value(delta) |> expect.to_equal("")
}

pub fn empty_append_returns_empty_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "abc") |> expect.to_be_ok()
  let #(updated, delta) = text.append_with_delta(base, "") |> expect.to_be_ok()

  expect.to_equal(updated, base)
  text.value(delta) |> expect.to_equal("")
}

pub fn merge_applies_delete_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "x") |> expect.to_be_ok()
  let #(updated, delta) = text.delete_with_delta(base, 0) |> expect.to_be_ok()

  text.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn length_of_empty_text_is_zero_test() {
  text.new(rid("A"))
  |> text.length()
  |> expect.to_equal(0)
}

pub fn length_counts_graphemes_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍b")
  |> expect.to_be_ok()
  |> text.length()
  |> expect.to_equal(3)
}

pub fn substring_returns_slice_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> expect.to_be_ok()
  |> text.substring(1, 3)
  |> expect.to_equal("bc")
}

pub fn substring_clamps_out_of_bounds_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.substring(-2, 10)
  |> expect.to_equal("abc")
}

pub fn substring_start_greater_than_end_returns_empty_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.substring(2, 1)
  |> expect.to_equal("")
}

pub fn substring_slices_graphemes_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍b")
  |> expect.to_be_ok()
  |> text.substring(1, 2)
  |> expect.to_equal("👍")
}

pub fn try_substring_valid_range_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> expect.to_be_ok()
  |> text.try_substring(1, 3)
  |> expect.to_equal(Ok("bc"))
}

pub fn try_substring_negative_start_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.try_substring(-1, 2)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: -1, end: 2, length: 3)))
}

pub fn try_substring_end_past_length_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.try_substring(0, 4)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3)))
}

pub fn try_substring_start_greater_than_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.try_substring(2, 1)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3)))
}

pub fn delete_range_removes_middle_graphemes_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> expect.to_be_ok()
  |> text.delete_range(1, 3)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("ad")
}

pub fn delete_range_empty_range_is_noop_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.delete_range(1, 1)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("abc")
}

pub fn delete_range_empty_range_returns_empty_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "abc") |> expect.to_be_ok()
  let #(updated, delta) =
    text.delete_range_with_delta(base, 1, 1) |> expect.to_be_ok()

  expect.to_equal(updated, base)
  text.value(delta) |> expect.to_equal("")
}

pub fn delete_range_full_range_empties_text_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.delete_range(0, 3)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("")
}

pub fn delete_range_handles_multi_grapheme_content_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍b")
  |> expect.to_be_ok()
  |> text.delete_range(1, 2)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("ab")
}

pub fn try_delete_range_negative_start_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.delete_range_with_delta(-1, 2)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: -1, end: 2, length: 3)))
}

pub fn try_delete_range_end_past_length_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.delete_range_with_delta(0, 4)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3)))
}

pub fn try_delete_range_start_greater_than_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.delete_range_with_delta(2, 1)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3)))
}

pub fn merge_applies_delete_range_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "abcd") |> expect.to_be_ok()
  let #(updated, delta) =
    text.delete_range_with_delta(base, 1, 3) |> expect.to_be_ok()

  text.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn replace_range_with_equal_length_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> expect.to_be_ok()
  |> text.replace_range(1, 3, "XY")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("aXYd")
}

pub fn replace_range_with_shorter_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> expect.to_be_ok()
  |> text.replace_range(1, 3, "X")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("aXd")
}

pub fn replace_range_with_longer_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> expect.to_be_ok()
  |> text.replace_range(1, 3, "XYZ")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("aXYZd")
}

pub fn replace_range_empty_range_inserts_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.replace_range(1, 1, "X")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("aXbc")
}

pub fn replace_range_empty_value_deletes_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> expect.to_be_ok()
  |> text.replace_range(1, 3, "")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("ad")
}

pub fn replace_range_empty_edit_returns_empty_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "abc") |> expect.to_be_ok()
  let #(updated, delta) =
    text.replace_range_with_delta(base, 1, 1, "") |> expect.to_be_ok()

  expect.to_equal(updated, base)
  text.value(delta) |> expect.to_equal("")
}

pub fn try_replace_range_invalid_range_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.replace_range_with_delta(2, 1, "x")
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3)))
}

pub fn merge_applies_replace_range_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "abcd") |> expect.to_be_ok()
  let #(updated, delta) =
    text.replace_range_with_delta(base, 1, 3, "XY") |> expect.to_be_ok()

  text.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn move_forward_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.move(0, 2)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("bca")
}

pub fn move_backward_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.move(2, 0)
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("cab")
}

pub fn try_move_from_index_out_of_bounds_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.move_with_delta(3, 0)
  |> expect.to_equal(
    Error(sequence.MoveFromIndexOutOfBounds(index: 3, length: 3)),
  )
}

pub fn try_move_to_index_out_of_bounds_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> expect.to_be_ok()
  |> text.move_with_delta(0, 3)
  |> expect.to_equal(
    Error(sequence.MoveToIndexOutOfBounds(index: 3, length_after_removal: 2)),
  )
}

pub fn merge_applies_move_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "abc") |> expect.to_be_ok()
  let #(updated, delta) = text.move_with_delta(base, 0, 2) |> expect.to_be_ok()

  text.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn append_to_empty_text_test() {
  text.new(rid("A"))
  |> text.append("hi")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("hi")
}

pub fn append_to_existing_text_test() {
  text.new(rid("A"))
  |> text.insert(0, "ab")
  |> expect.to_be_ok()
  |> text.append("cd")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("abcd")
}

pub fn append_multi_grapheme_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> expect.to_be_ok()
  |> text.append("👍!")
  |> expect.to_be_ok()
  |> text.value()
  |> expect.to_equal("a👍!")
}

pub fn merge_applies_append_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "ab") |> expect.to_be_ok()
  let #(updated, delta) =
    text.append_with_delta(base, "cd") |> expect.to_be_ok()

  text.merge(base, delta, rid("A"))
  |> expect.to_equal(updated)
}

pub fn merge_as_keeps_local_identity_whatever_the_argument_order_test() {
  // The alias keeps the named local identity even when the delta is first.
  let base = text.new(rid("A")) |> text.insert(0, "a") |> expect.to_be_ok()
  let #(b_state, b_delta) =
    text.merge(text.new(rid("B")), base, rid("B"))
    |> text.insert_with_delta(1, "b")
    |> expect.to_be_ok()

  let a_state =
    text.merge_as(b_delta, base, rid("A"))
    |> text.insert(2, "x")
    |> expect.to_be_ok()
  let b_state = text.insert(b_state, 2, "c") |> expect.to_be_ok()

  text.merge(a_state, b_state, rid("A"))
  |> text.length()
  |> expect.to_equal(4)
}

pub fn merge_as_is_argument_order_independent_test() {
  let base = text.new(rid("A")) |> text.insert(0, "a") |> expect.to_be_ok()
  let #(_, b_delta) =
    text.merge(text.new(rid("B")), base, rid("B"))
    |> text.insert_with_delta(1, "b")
    |> expect.to_be_ok()

  text.merge_as(base, b_delta, rid("A"))
  |> expect.to_equal(text.merge_as(b_delta, base, rid("A")))
}
