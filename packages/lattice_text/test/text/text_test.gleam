import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_sequence/sequence
import lattice_text/text

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_value_is_empty_test() {
  text.new(rid("A"))
  |> text.value()
  |> fn(actual) {
    assert actual == ""
  }
}

pub fn new_values_is_empty_test() {
  text.new(rid("A"))
  |> text.values()
  |> fn(actual) {
    assert actual == []
  }
}

pub fn insert_into_empty_text_test() {
  text.new(rid("A"))
  |> text.insert(0, "h")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "h"
  }
}

pub fn insert_appends_at_end_test() {
  text.new(rid("A"))
  |> text.insert(0, "h")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert(1, "i")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "hi"
  }
}

pub fn ten_thousand_graphemes_append_and_merge_delta_preserve_order_test() {
  let value = string.repeat("x", 10_000)
  let assert Ok(base) = text.append(text.new(rid("A")), value)
  let assert Ok(old_anchor) = text.anchor_at(base, 9999, sequence.Before)
  let assert Ok(#(updated, delta)) = text.append_with_delta(base, "!?")
  text.value(updated)
  |> fn(actual) {
    assert actual == value <> "!?"
  }
  text.value(delta)
  |> fn(actual) {
    assert actual == "!?"
  }
  text.length(delta)
  |> fn(actual) {
    assert actual == 2
  }
  text.anchor_at(updated, 9999, sequence.Before)
  |> fn(actual) {
    assert actual == Ok(old_anchor)
  }
  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
  text.merge(delta, base, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn insert_in_middle_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert(1, "c")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert(1, "b")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "abc"
  }
}

pub fn insert_multi_character_value_uses_character_indexes_test() {
  text.new(rid("A"))
  |> text.insert(0, "hi")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert(1, "!")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "h!i"
  }
}

pub fn insert_multi_grapheme_value_preserves_each_grapheme_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert(1, "!")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "a!👍"
  }
}

pub fn try_insert_negative_index_returns_error_test() {
  text.new(rid("A"))
  |> text.insert_with_delta(-1, "x")
  |> fn(actual) {
    assert actual == Error(sequence.IndexOutOfBounds(index: -1, length: 0))
  }
}

pub fn try_insert_past_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert_with_delta(2, "x")
  |> fn(actual) {
    assert actual == Error(sequence.IndexOutOfBounds(index: 2, length: 1))
  }
}

pub fn delete_removes_visible_unit_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert(1, "b")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.insert(2, "c")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete(1)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "ac"
  }
}

pub fn delete_removes_character_from_multi_character_insert_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete(1)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "ac"
  }
}

pub fn try_delete_negative_index_returns_error_test() {
  text.new(rid("A"))
  |> text.delete_with_delta(-1)
  |> fn(actual) {
    assert actual
      == Error(sequence.DeleteIndexOutOfBounds(index: -1, length: 0))
  }
}

pub fn try_delete_at_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_with_delta(1)
  |> fn(actual) {
    assert actual == Error(sequence.DeleteIndexOutOfBounds(index: 1, length: 1))
  }
}

pub fn merge_concurrent_insert_same_position_is_deterministic_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
    |> text.insert(1, "c")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let alice =
    text.merge(text.new(rid("alice")), base, rid("alice"))
    |> text.insert(1, "b")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let bob =
    text.merge(text.new(rid("bob")), base, rid("bob"))
    |> text.insert(1, "X")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  let ab = text.merge(alice, bob, rid("A")) |> text.value()
  let ba = text.merge(bob, alice, rid("A")) |> text.value()

  ab
  |> fn(actual) {
    assert actual == ba
  }
  ab
  |> fn(actual) {
    assert actual == "abXc"
  }
}

pub fn unicode_order_concurrent_first_inserts_deltas_and_snapshots_test() {
  let #(bmp, bmp_delta) =
    text.new(rid("\u{e000}"))
    |> text.insert_with_delta(0, "b")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(supplementary, supplementary_delta) =
    text.new(rid("\u{10000}"))
    |> text.insert_with_delta(0, "s")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let decoded_bmp =
    text.to_json(bmp)
    |> json.to_string()
    |> text.from_json()
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let decoded_supplementary =
    text.to_json(supplementary)
    |> json.to_string()
    |> text.from_json()
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
    #(decoded_bmp, decoded_supplementary),
    #(decoded_supplementary, decoded_bmp),
  ])
  text.merge(pair.0, pair.1, rid("observer"))
  |> text.value()
  |> fn(actual) {
    assert actual == "bs"
  }
}

pub fn merge_delete_and_insert_after_deleted_anchor_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
    |> text.insert(1, "b")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
    |> text.insert(2, "c")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  let alice =
    base
    |> text.delete(1)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let bob =
    text.merge(text.new(rid("B")), base, rid("B"))
    |> text.insert(2, "Y")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(alice, bob, rid("A"))
  |> text.value()
  |> fn(actual) {
    assert actual == "aYc"
  }
}

pub fn merge_concurrent_runs_do_not_interleave_for_forward_typing_test() {
  let base =
    text.new(rid("base"))
    |> text.insert(0, "_")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let alice =
    text.merge(text.new(rid("alice")), base, rid("alice"))
    |> text.insert(1, "m")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
    |> text.insert(2, "o")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
    |> text.insert(3, "m")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let bob =
    text.merge(text.new(rid("bob")), base, rid("bob"))
    |> text.insert(1, "d")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
    |> text.insert(2, "a")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
    |> text.insert(3, "d")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(alice, bob, rid("A"))
  |> text.value()
  |> fn(actual) {
    assert actual == "_momdad"
  }
}

pub fn merge_applies_insert_delta_test() {
  let base = text.new(rid("A"))
  let #(updated, delta) =
    text.insert_with_delta(base, 0, "x")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn merge_applies_multi_character_insert_delta_test() {
  let base = text.new(rid("A"))
  let #(updated, delta) =
    text.insert_with_delta(base, 0, "hi")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn empty_insert_returns_empty_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "abc")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.insert_with_delta(base, 1, "")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  assert updated == base
  text.value(delta)
  |> fn(actual) {
    assert actual == ""
  }
}

pub fn empty_append_returns_empty_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "abc")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.append_with_delta(base, "")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  assert updated == base
  text.value(delta)
  |> fn(actual) {
    assert actual == ""
  }
}

pub fn merge_applies_delete_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "x")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.delete_with_delta(base, 0)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn length_of_empty_text_is_zero_test() {
  text.new(rid("A"))
  |> text.length()
  |> fn(actual) {
    assert actual == 0
  }
}

pub fn length_counts_graphemes_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍b")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.length()
  |> fn(actual) {
    assert actual == 3
  }
}

pub fn substring_returns_slice_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.substring(1, 3)
  |> fn(actual) {
    assert actual == "bc"
  }
}

pub fn substring_clamps_out_of_bounds_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.substring(-2, 10)
  |> fn(actual) {
    assert actual == "abc"
  }
}

pub fn substring_start_greater_than_end_returns_empty_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.substring(2, 1)
  |> fn(actual) {
    assert actual == ""
  }
}

pub fn substring_slices_graphemes_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍b")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.substring(1, 2)
  |> fn(actual) {
    assert actual == "👍"
  }
}

pub fn try_substring_valid_range_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.try_substring(1, 3)
  |> fn(actual) {
    assert actual == Ok("bc")
  }
}

pub fn try_substring_negative_start_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.try_substring(-1, 2)
  |> fn(actual) {
    assert actual == Error(text.RangeOutOfBounds(start: -1, end: 2, length: 3))
  }
}

pub fn try_substring_end_past_length_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.try_substring(0, 4)
  |> fn(actual) {
    assert actual == Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3))
  }
}

pub fn try_substring_start_greater_than_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.try_substring(2, 1)
  |> fn(actual) {
    assert actual == Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3))
  }
}

pub fn delete_range_removes_middle_graphemes_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_range(1, 3)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "ad"
  }
}

pub fn delete_range_empty_range_is_noop_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_range(1, 1)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "abc"
  }
}

pub fn delete_range_empty_range_returns_empty_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "abc")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.delete_range_with_delta(base, 1, 1)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  assert updated == base
  text.value(delta)
  |> fn(actual) {
    assert actual == ""
  }
}

pub fn delete_range_full_range_empties_text_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_range(0, 3)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == ""
  }
}

pub fn delete_range_handles_multi_grapheme_content_test() {
  text.new(rid("A"))
  |> text.insert(0, "a👍b")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_range(1, 2)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "ab"
  }
}

pub fn try_delete_range_negative_start_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_range_with_delta(-1, 2)
  |> fn(actual) {
    assert actual == Error(text.RangeOutOfBounds(start: -1, end: 2, length: 3))
  }
}

pub fn try_delete_range_end_past_length_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_range_with_delta(0, 4)
  |> fn(actual) {
    assert actual == Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3))
  }
}

pub fn try_delete_range_start_greater_than_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.delete_range_with_delta(2, 1)
  |> fn(actual) {
    assert actual == Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3))
  }
}

pub fn merge_applies_delete_range_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "abcd")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.delete_range_with_delta(base, 1, 3)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn replace_range_with_equal_length_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.replace_range(1, 3, "XY")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "aXYd"
  }
}

pub fn replace_range_with_shorter_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.replace_range(1, 3, "X")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "aXd"
  }
}

pub fn replace_range_with_longer_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.replace_range(1, 3, "XYZ")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "aXYZd"
  }
}

pub fn replace_range_empty_range_inserts_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.replace_range(1, 1, "X")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "aXbc"
  }
}

pub fn replace_range_empty_value_deletes_test() {
  text.new(rid("A"))
  |> text.insert(0, "abcd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.replace_range(1, 3, "")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "ad"
  }
}

pub fn replace_range_empty_edit_returns_empty_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "abc")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.replace_range_with_delta(base, 1, 1, "")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  assert updated == base
  text.value(delta)
  |> fn(actual) {
    assert actual == ""
  }
}

pub fn try_replace_range_invalid_range_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.replace_range_with_delta(2, 1, "x")
  |> fn(actual) {
    assert actual == Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3))
  }
}

pub fn merge_applies_replace_range_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "abcd")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.replace_range_with_delta(base, 1, 3, "XY")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn move_forward_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.move(0, 2)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "bca"
  }
}

pub fn move_backward_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.move(2, 0)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "cab"
  }
}

pub fn try_move_from_index_out_of_bounds_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.move_with_delta(3, 0)
  |> fn(actual) {
    assert actual
      == Error(sequence.MoveFromIndexOutOfBounds(index: 3, length: 3))
  }
}

pub fn try_move_to_index_out_of_bounds_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "abc")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.move_with_delta(0, 3)
  |> fn(actual) {
    assert actual
      == Error(sequence.MoveToIndexOutOfBounds(
        index: 3,
        length_after_removal: 2,
      ))
  }
}

pub fn merge_applies_move_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "abc")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.move_with_delta(base, 0, 2)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn append_to_empty_text_test() {
  text.new(rid("A"))
  |> text.append("hi")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "hi"
  }
}

pub fn append_to_existing_text_test() {
  text.new(rid("A"))
  |> text.insert(0, "ab")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.append("cd")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "abcd"
  }
}

pub fn append_multi_grapheme_value_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.append("👍!")
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> text.value()
  |> fn(actual) {
    assert actual == "a👍!"
  }
}

pub fn merge_applies_append_delta_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "ab")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(updated, delta) =
    text.append_with_delta(base, "cd")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == updated
  }
}

pub fn merge_as_keeps_local_identity_whatever_the_argument_order_test() {
  // The alias keeps the named local identity even when the delta is first.
  let base =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(b_state, b_delta) =
    text.merge(text.new(rid("B")), base, rid("B"))
    |> text.insert_with_delta(1, "b")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  let a_state =
    text.merge_as(b_delta, base, rid("A"))
    |> text.insert(2, "x")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let b_state =
    text.insert(b_state, 2, "c")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge(a_state, b_state, rid("A"))
  |> text.length()
  |> fn(actual) {
    assert actual == 4
  }
}

pub fn merge_as_is_argument_order_independent_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let #(_, b_delta) =
    text.merge(text.new(rid("B")), base, rid("B"))
    |> text.insert_with_delta(1, "b")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.merge_as(base, b_delta, rid("A"))
  |> fn(actual) {
    assert actual == text.merge_as(b_delta, base, rid("A"))
  }
}
