import gleam/list
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_fugue/sequence
import lattice_text_fugue/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn doc() {
  text.new(rid("A"))
}

fn fork(base: text.Text, id: String) -> text.Text {
  text.merge(text.new(rid(id)), base, rid(id))
}

pub fn new_is_empty_test() {
  doc()
  |> text.value()
  |> expect.to_equal("")
}

pub fn new_length_is_zero_test() {
  doc()
  |> text.length()
  |> expect.to_equal(0)
}

pub fn insert_sets_value_test() {
  doc()
  |> text.insert(0, "hello")
  |> result.map(text.value)
  |> expect.to_equal(Ok("hello"))
}

pub fn insert_counts_graphemes_test() {
  doc()
  |> text.insert(0, "a👍b")
  |> result.map(text.length)
  |> expect.to_equal(Ok(3))
}

pub fn insert_in_middle_test() {
  doc()
  |> text.insert(0, "ad")
  |> result.try(text.insert(_, 1, "bc"))
  |> result.map(text.value)
  |> expect.to_equal(Ok("abcd"))
}

pub fn append_test() {
  doc()
  |> text.insert(0, "ab")
  |> result.try(text.append(_, "cd"))
  |> result.map(text.value)
  |> expect.to_equal(Ok("abcd"))
}

pub fn delete_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  base
  |> text.delete(1)
  |> result.map(text.value)
  |> expect.to_equal(Ok("ac"))
}

pub fn insert_out_of_bounds_test() {
  doc()
  |> text.insert(0, "ab")
  |> result.try(text.insert_with_delta(_, 9, "x"))
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(9, 2)))
}

pub fn delete_out_of_bounds_test() {
  let assert Ok(base) = doc() |> text.insert(0, "ab")
  text.delete_with_delta(base, 9)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(9, 2)))
}

// ---------------------------------------------------------------------------
// substring
// ---------------------------------------------------------------------------

pub fn substring_test() {
  doc()
  |> text.insert(0, "abcd")
  |> result.map(text.substring(_, 1, 3))
  |> expect.to_equal(Ok("bc"))
}

pub fn substring_clamps_test() {
  doc()
  |> text.insert(0, "abc")
  |> result.map(text.substring(_, -2, 10))
  |> expect.to_equal(Ok("abc"))
}

pub fn substring_inverted_is_empty_test() {
  doc()
  |> text.insert(0, "abc")
  |> result.map(text.substring(_, 2, 1))
  |> expect.to_equal(Ok(""))
}

pub fn try_substring_valid_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  text.try_substring(base, 1, 3)
  |> expect.to_equal(Ok("bc"))
}

pub fn try_substring_out_of_bounds_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  text.try_substring(base, 0, 4)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3)))
}

pub fn try_substring_inverted_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  text.try_substring(base, 2, 1)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3)))
}

// ---------------------------------------------------------------------------
// range edits
// ---------------------------------------------------------------------------

pub fn delete_range_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abcd")
  base
  |> text.delete_range(1, 3)
  |> result.map(text.value)
  |> expect.to_equal(Ok("ad"))
}

pub fn delete_range_empty_is_noop_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  base
  |> text.delete_range(1, 1)
  |> result.map(text.value)
  |> expect.to_equal(Ok("abc"))
}

pub fn delete_range_empty_returns_empty_delta_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  let assert Ok(#(updated, delta)) = text.delete_range_with_delta(base, 1, 1)

  expect.to_equal(updated, base)
  delta |> expect.to_equal(doc())
}

pub fn replace_range_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abcd")
  base
  |> text.replace_range(1, 3, "XY")
  |> result.map(text.value)
  |> expect.to_equal(Ok("aXYd"))
}

pub fn replace_range_insert_only_test() {
  let assert Ok(base) = doc() |> text.insert(0, "ad")
  base
  |> text.replace_range(1, 1, "bc")
  |> result.map(text.value)
  |> expect.to_equal(Ok("abcd"))
}

pub fn replace_range_delete_only_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abcd")
  base
  |> text.replace_range(1, 3, "")
  |> result.map(text.value)
  |> expect.to_equal(Ok("ad"))
}

pub fn replace_range_out_of_bounds_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  text.replace_range_with_delta(base, 0, 9, "z")
  |> expect.to_equal(Error(text.RangeOutOfBounds(0, 9, 3)))
}

pub fn replace_range_empty_edit_returns_empty_delta_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  let assert Ok(#(updated, delta)) =
    text.replace_range_with_delta(base, 1, 1, "")

  expect.to_equal(updated, base)
  delta |> expect.to_equal(doc())
}

// ---------------------------------------------------------------------------
// deltas and merge
// ---------------------------------------------------------------------------

pub fn insert_delta_merges_into_peer_test() {
  let assert Ok(base) = doc() |> text.insert(0, "hi")
  let assert Ok(#(_updated, delta)) = text.insert_with_delta(base, 2, "!")
  text.merge(base, delta, rid("A"))
  |> text.value()
  |> expect.to_equal("hi!")
}

pub fn empty_insert_returns_empty_delta_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  let assert Ok(#(updated, delta)) = text.insert_with_delta(base, 1, "")

  expect.to_equal(updated, base)
  delta |> expect.to_equal(doc())
}

pub fn empty_append_returns_empty_delta_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  let assert Ok(#(updated, delta)) = text.append_with_delta(base, "")

  expect.to_equal(updated, base)
  delta |> expect.to_equal(doc())
}

pub fn concurrent_edits_converge_test() {
  let assert Ok(base) = doc() |> text.insert(0, "abc")
  let assert Ok(a) = text.insert(base, 0, "X")
  let assert Ok(b) = fork(base, "B") |> text.insert(3, "Y")

  let merged_ab = text.merge(a, b, rid("A"))
  let merged_ba = text.merge(b, a, rid("A"))
  expect.to_equal(merged_ab, merged_ba)
}

// ---------------------------------------------------------------------------
// non-interleaving: two replicas concurrently prepend runs at the same gap.
// Fugue keeps each run contiguous rather than interleaving them.
// ---------------------------------------------------------------------------

pub fn concurrent_prepend_runs_stay_contiguous_test() {
  let assert Ok(base) = doc() |> text.insert(0, "!")

  // Replica A prepends "abc" one grapheme at a time.
  let assert Ok(a) =
    base
    |> text.insert(0, "a")
    |> result.try(text.insert(_, 1, "b"))
    |> result.try(text.insert(_, 2, "c"))

  // Replica B concurrently prepends "xyz" at the same front gap.
  let assert Ok(b) =
    fork(base, "B")
    |> text.insert(0, "x")
    |> result.try(text.insert(_, 1, "y"))
    |> result.try(text.insert(_, 2, "z"))

  let merged = text.value(text.merge(a, b, rid("A")))

  // Both runs must be present and contiguous (not interleaved).
  let has_abc_contiguous = string.contains(merged, "abc")
  let has_xyz_contiguous = string.contains(merged, "xyz")
  expect.to_be_true(has_abc_contiguous && has_xyz_contiguous)
}

pub fn plain_edits_preserve_errors_and_input_test() {
  let assert Ok(base) = text.insert(doc(), 0, "a👍b")
  list.each([-1, 4], fn(index) {
    list.each(["", "XY"], fn(value) {
      text.insert(base, index, value)
      |> expect.to_equal(Error(sequence.IndexOutOfBounds(index, 3)))
      text.insert_with_delta(base, index, value)
      |> expect.to_equal(Error(sequence.IndexOutOfBounds(index, 3)))
    })
  })
  list.each([-1, 3, 4], fn(index) {
    text.delete(base, index)
    |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(index, 3)))
    text.delete_with_delta(base, index)
    |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(index, 3)))
  })
  list.each([#(-1, 1), #(2, 1), #(0, 4), #(4, 4)], fn(bounds) {
    let #(start, end) = bounds
    let error = text.RangeOutOfBounds(start, end, 3)
    text.delete_range(base, start, end) |> expect.to_equal(Error(error))
    text.delete_range_with_delta(base, start, end)
    |> expect.to_equal(Error(error))
    list.each(["", "XY"], fn(value) {
      text.replace_range(base, start, end, value)
      |> expect.to_equal(Error(error))
      text.replace_range_with_delta(base, start, end, value)
      |> expect.to_equal(Error(error))
    })
  })
  text.value(base) |> expect.to_equal("a👍b")
  text.delete(doc(), 0)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(0, 0)))
  text.delete_with_delta(doc(), 0)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(0, 0)))
}

pub fn state_only_edits_match_delta_results_test() {
  let assert Ok(base) = text.insert(doc(), 0, "a👍b")
  let assert Ok(#(inserted, _)) = text.insert_with_delta(base, 1, "XY")
  text.insert(base, 1, "XY") |> expect.to_equal(Ok(inserted))
  let assert Ok(#(appended, _)) = text.append_with_delta(base, "XY")
  text.append(base, "XY") |> expect.to_equal(Ok(appended))
  let assert Ok(#(deleted, _)) = text.delete_with_delta(base, 1)
  text.delete(base, 1) |> expect.to_equal(Ok(deleted))
  let assert Ok(#(range_deleted, _)) = text.delete_range_with_delta(base, 1, 3)
  text.delete_range(base, 1, 3) |> expect.to_equal(Ok(range_deleted))
  let assert Ok(#(replaced, _)) =
    text.replace_range_with_delta(base, 1, 3, "XY")
  text.replace_range(base, 1, 3, "XY") |> expect.to_equal(Ok(replaced))
  text.insert(base, 1, "") |> expect.to_equal(Ok(base))
  text.append(base, "") |> expect.to_equal(Ok(base))
  text.delete_range(base, 1, 1) |> expect.to_equal(Ok(base))
  text.replace_range(base, 1, 1, "") |> expect.to_equal(Ok(base))
}
