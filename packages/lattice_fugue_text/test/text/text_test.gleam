import gleam/string
import lattice_core/replica_id
import lattice_fugue_text/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn doc() {
  text.new(rid("A"))
}

fn fork(base: text.Text, id: String) -> text.Text {
  text.merge(text.new(rid(id)), base)
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
  |> text.value()
  |> expect.to_equal("hello")
}

pub fn insert_counts_graphemes_test() {
  doc()
  |> text.insert(0, "a👍b")
  |> text.length()
  |> expect.to_equal(3)
}

pub fn insert_in_middle_test() {
  doc()
  |> text.insert(0, "ad")
  |> text.insert(1, "bc")
  |> text.value()
  |> expect.to_equal("abcd")
}

pub fn append_test() {
  doc()
  |> text.insert(0, "ab")
  |> text.append("cd")
  |> text.value()
  |> expect.to_equal("abcd")
}

pub fn delete_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.delete(1)
  |> text.value()
  |> expect.to_equal("ac")
}

pub fn try_insert_out_of_bounds_test() {
  doc()
  |> text.insert(0, "ab")
  |> text.try_insert_with_delta(9, "x")
  |> is_err()
  |> expect.to_be_true()
}

pub fn try_delete_out_of_bounds_test() {
  doc()
  |> text.insert(0, "ab")
  |> text.try_delete_with_delta(9)
  |> is_err()
  |> expect.to_be_true()
}

// ---------------------------------------------------------------------------
// substring
// ---------------------------------------------------------------------------

pub fn substring_test() {
  doc()
  |> text.insert(0, "abcd")
  |> text.substring(1, 3)
  |> expect.to_equal("bc")
}

pub fn substring_clamps_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.substring(-2, 10)
  |> expect.to_equal("abc")
}

pub fn substring_inverted_is_empty_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.substring(2, 1)
  |> expect.to_equal("")
}

pub fn try_substring_valid_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.try_substring(1, 3)
  |> expect.to_equal(Ok("bc"))
}

pub fn try_substring_out_of_bounds_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.try_substring(0, 4)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3)))
}

pub fn try_substring_inverted_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.try_substring(2, 1)
  |> expect.to_equal(Error(text.RangeOutOfBounds(start: 2, end: 1, length: 3)))
}

// ---------------------------------------------------------------------------
// range edits
// ---------------------------------------------------------------------------

pub fn delete_range_test() {
  doc()
  |> text.insert(0, "abcd")
  |> text.delete_range(1, 3)
  |> text.value()
  |> expect.to_equal("ad")
}

pub fn delete_range_empty_is_noop_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.delete_range(1, 1)
  |> text.value()
  |> expect.to_equal("abc")
}

pub fn replace_range_test() {
  doc()
  |> text.insert(0, "abcd")
  |> text.replace_range(1, 3, "XY")
  |> text.value()
  |> expect.to_equal("aXYd")
}

pub fn replace_range_insert_only_test() {
  doc()
  |> text.insert(0, "ad")
  |> text.replace_range(1, 1, "bc")
  |> text.value()
  |> expect.to_equal("abcd")
}

pub fn replace_range_delete_only_test() {
  doc()
  |> text.insert(0, "abcd")
  |> text.replace_range(1, 3, "")
  |> text.value()
  |> expect.to_equal("ad")
}

pub fn try_replace_range_out_of_bounds_test() {
  doc()
  |> text.insert(0, "abc")
  |> text.try_replace_range_with_delta(0, 9, "z")
  |> is_err()
  |> expect.to_be_true()
}

// ---------------------------------------------------------------------------
// deltas and merge
// ---------------------------------------------------------------------------

pub fn insert_delta_merges_into_peer_test() {
  let base = doc() |> text.insert(0, "hi")
  let #(_updated, delta) = text.insert_with_delta(base, 2, "!")
  text.merge(base, delta)
  |> text.value()
  |> expect.to_equal("hi!")
}

pub fn concurrent_edits_converge_test() {
  let base = doc() |> text.insert(0, "abc")
  let a = text.insert(base, 0, "X")
  let b = fork(base, "B") |> text.insert(3, "Y")

  let merged_ab = text.merge(a, b)
  let merged_ba = text.merge(b, a)
  expect.to_equal(text.value(merged_ab), text.value(merged_ba))
}

// ---------------------------------------------------------------------------
// non-interleaving: two replicas concurrently prepend runs at the same gap.
// Fugue keeps each run contiguous rather than interleaving them.
// ---------------------------------------------------------------------------

pub fn concurrent_prepend_runs_stay_contiguous_test() {
  let base = doc() |> text.insert(0, "!")

  // Replica A prepends "abc" one grapheme at a time.
  let a =
    base
    |> text.insert(0, "a")
    |> text.insert(1, "b")
    |> text.insert(2, "c")

  // Replica B concurrently prepends "xyz" at the same front gap.
  let b =
    fork(base, "B")
    |> text.insert(0, "x")
    |> text.insert(1, "y")
    |> text.insert(2, "z")

  let merged = text.value(text.merge(a, b))

  // Both runs must be present and contiguous (not interleaved).
  let has_abc_contiguous = string.contains(merged, "abc")
  let has_xyz_contiguous = string.contains(merged, "xyz")
  expect.to_be_true(has_abc_contiguous && has_xyz_contiguous)
}

fn is_err(result: Result(a, b)) -> Bool {
  case result {
    Error(_) -> True
    Ok(_) -> False
  }
}
