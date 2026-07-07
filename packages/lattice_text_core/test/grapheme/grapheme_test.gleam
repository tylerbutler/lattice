import gleam/list
import lattice_text_core/grapheme
import startest/expect

// ---------------------------------------------------------------------------
// A trivial in-memory backend used to exercise the generic fold helpers. State
// is a plain grapheme list; deltas are the graphemes that were inserted or
// deleted, joined by appending.
// ---------------------------------------------------------------------------

type Err {
  IndexOutOfBounds(index: Int, length: Int)
}

fn length(state: List(String)) -> Int {
  list.length(state)
}

fn insert_many(
  state: List(String),
  index: Int,
  graphemes: List(String),
) -> Result(#(List(String), List(String)), Err) {
  let len = list.length(state)
  case index < 0 || index > len {
    True -> Error(IndexOutOfBounds(index: index, length: len))
    False -> {
      let before = list.take(state, index)
      let after = list.drop(state, index)
      Ok(#(list.flatten([before, graphemes, after]), graphemes))
    }
  }
}

fn insert_merge(a: List(String), b: List(String)) -> List(String) {
  list.append(a, b)
}

fn delete(
  state: List(String),
  index: Int,
) -> Result(#(List(String), List(String)), grapheme.RangeError) {
  let len = list.length(state)
  case index < 0 || index >= len {
    True ->
      Error(grapheme.RangeOutOfBounds(start: index, end: index, length: len))
    False -> {
      let before = list.take(state, index)
      let removed = state |> list.drop(index) |> list.take(1)
      let after = list.drop(state, index + 1)
      Ok(#(list.append(before, after), removed))
    }
  }
}

// ---------------------------------------------------------------------------
// validate_range
// ---------------------------------------------------------------------------

pub fn validate_range_accepts_valid_test() {
  grapheme.validate_range(1, 3, 4)
  |> expect.to_equal(Ok(Nil))
}

pub fn validate_range_accepts_empty_range_test() {
  grapheme.validate_range(2, 2, 4)
  |> expect.to_equal(Ok(Nil))
}

pub fn validate_range_rejects_negative_start_test() {
  grapheme.validate_range(-1, 2, 4)
  |> expect.to_equal(
    Error(grapheme.RangeOutOfBounds(start: -1, end: 2, length: 4)),
  )
}

pub fn validate_range_rejects_end_past_length_test() {
  grapheme.validate_range(0, 5, 3)
  |> expect.to_equal(
    Error(grapheme.RangeOutOfBounds(start: 0, end: 5, length: 3)),
  )
}

pub fn validate_range_rejects_inverted_range_test() {
  grapheme.validate_range(3, 1, 4)
  |> expect.to_equal(
    Error(grapheme.RangeOutOfBounds(start: 3, end: 1, length: 4)),
  )
}

// ---------------------------------------------------------------------------
// value / slice
// ---------------------------------------------------------------------------

pub fn value_concatenates_test() {
  grapheme.value(["a", "b", "c"])
  |> expect.to_equal("abc")
}

pub fn slice_returns_subrange_test() {
  grapheme.slice(["a", "b", "c", "d"], 1, 3)
  |> expect.to_equal("bc")
}

pub fn slice_empty_range_is_empty_test() {
  grapheme.slice(["a", "b", "c"], 2, 2)
  |> expect.to_equal("")
}

// ---------------------------------------------------------------------------
// insert_graphemes
// ---------------------------------------------------------------------------

pub fn insert_graphemes_into_empty_test() {
  grapheme.insert_graphemes(
    ["a", "b", "c"],
    [],
    0,
    length,
    insert_many,
    IndexOutOfBounds,
  )
  |> expect.to_equal(Ok(#(["a", "b", "c"], ["a", "b", "c"])))
}

pub fn insert_graphemes_in_middle_test() {
  grapheme.insert_graphemes(
    ["x", "y"],
    ["a", "d"],
    1,
    length,
    insert_many,
    IndexOutOfBounds,
  )
  |> expect.to_equal(Ok(#(["a", "x", "y", "d"], ["x", "y"])))
}

pub fn insert_empty_graphemes_is_noop_test() {
  grapheme.insert_graphemes(
    [],
    ["a", "b"],
    1,
    length,
    insert_many,
    IndexOutOfBounds,
  )
  |> expect.to_equal(Ok(#(["a", "b"], ["a", "b"])))
}

pub fn insert_empty_graphemes_at_bad_index_errors_test() {
  grapheme.insert_graphemes(
    [],
    ["a", "b"],
    9,
    length,
    insert_many,
    IndexOutOfBounds,
  )
  |> expect.to_equal(Error(IndexOutOfBounds(index: 9, length: 2)))
}

pub fn insert_graphemes_out_of_bounds_test() {
  grapheme.insert_graphemes(
    ["z"],
    ["a"],
    5,
    length,
    insert_many,
    IndexOutOfBounds,
  )
  |> expect.to_equal(Error(IndexOutOfBounds(index: 5, length: 1)))
}

// ---------------------------------------------------------------------------
// delete_graphemes
// ---------------------------------------------------------------------------

pub fn delete_graphemes_range_test() {
  grapheme.delete_graphemes(["a", "b", "c", "d"], 1, 3, delete, insert_merge)
  |> expect.to_equal(Ok(#(["a", "d"], ["b", "c"])))
}

pub fn delete_graphemes_empty_range_is_noop_test() {
  grapheme.delete_graphemes(["a", "b"], 1, 1, delete, insert_merge)
  |> expect.to_equal(Ok(#(["a", "b"], ["a", "b"])))
}

pub fn delete_graphemes_all_test() {
  grapheme.delete_graphemes(["a", "b", "c"], 0, 3, delete, insert_merge)
  |> expect.to_equal(Ok(#([], ["a", "b", "c"])))
}
