//// Backend-agnostic grapheme and range helpers shared by lattice text CRDTs.
////
//// A text CRDT is a sequence CRDT of single-grapheme values plus a thin layer
//// of grapheme/range bookkeeping: splitting inserted strings into graphemes,
//// validating `[start, end)` ranges, slicing out substrings, and folding
//// multi-grapheme inserts/deletes into a single mergeable delta. That layer is
//// identical regardless of which sequence CRDT stores the graphemes, so it
//// lives here and is shared by `lattice_text` (backed by `lattice_sequence`)
//// and `lattice_text_fugue` (backed by `lattice_fugue`).
////
//// The multi-grapheme fold helpers are generic over the backend's state type
//// `s` and take the backend's `insert`, `delete`, and `merge` as ordinary
//// function arguments, so no dependency on any particular sequence package is
//// needed.

import gleam/bool
import gleam/list
import gleam/result
import gleam/string

/// An error returned when a grapheme range does not satisfy
/// `0 <= start <= end <= length`.
pub type RangeError {
  RangeOutOfBounds(start: Int, end: Int, length: Int)
}

/// Validate that `[start, end)` is a range within `[0, length]`.
///
/// ## Examples
///
/// ```gleam
/// validate_range(1, 3, 4)
/// // -> Ok(Nil)
/// validate_range(0, 5, 3)
/// // -> Error(RangeOutOfBounds(start: 0, end: 5, length: 3))
/// ```
pub fn validate_range(
  start: Int,
  end: Int,
  length: Int,
) -> Result(Nil, RangeError) {
  use <- bool.guard(
    start < 0 || end > length || start > end,
    Error(RangeOutOfBounds(start: start, end: end, length: length)),
  )
  Ok(Nil)
}

/// Concatenate a list of graphemes into a single string.
pub fn value(graphemes: List(String)) -> String {
  string.concat(graphemes)
}

/// Return the graphemes in `[start, end)` as a string.
///
/// Indexes are used as-is (no clamping); callers that need clamping or
/// validation should apply it first with `validate_range`.
pub fn slice(graphemes: List(String), start: Int, end: Int) -> String {
  graphemes
  |> list.drop(start)
  |> list.take(end - start)
  |> string.concat()
}

/// Insert a list of graphemes at `index` as a single batched operation,
/// returning the updated state and one delta covering every inserted node.
///
/// Generic over the backend state `s` and insert-error `e`:
/// - `length` reports the backend's current visible length.
/// - `insert_many` inserts the whole grapheme run starting at `index`,
///   returning the updated state and its combined delta, or a backend error.
/// - `index_out_of_bounds` builds the backend error for an invalid `index`.
///
/// Returns `Error` (via `index_out_of_bounds`) when `index` is outside
/// `[0, length]`, mirroring the backend's own bounds contract even when the
/// grapheme list is empty. An empty grapheme list at a valid index is passed
/// to `insert_many`, allowing the backend to return its neutral delta.
pub fn insert_graphemes(
  graphemes: List(String),
  state: s,
  index: Int,
  length: fn(s) -> Int,
  insert_many: fn(s, Int, List(String)) -> Result(#(s, s), e),
  index_out_of_bounds: fn(Int, Int) -> e,
) -> Result(#(s, s), e) {
  let len = length(state)
  case index < 0 || index > len {
    True -> Error(index_out_of_bounds(index, len))
    False -> insert_many(state, index, graphemes)
  }
}

/// Delete the graphemes in `[start, end)` one at a time, threading a merged
/// delta of every deletion.
///
/// Generic over the backend state `s` and delete-error `e`:
/// - `delete` deletes the single grapheme at an index, returning the updated
///   state and its delta, or the backend's own error.
/// - `merge` joins two deltas.
///
/// Repeatedly deletes at `start`, since each deletion shifts the following
/// graphemes left. An empty range is a no-op whose delta is the unchanged
/// state.
pub fn delete_graphemes(
  state: s,
  start: Int,
  end: Int,
  delete: fn(s, Int) -> Result(#(s, s), e),
  merge: fn(s, s) -> s,
) -> Result(#(s, s), e) {
  case end - start {
    count if count <= 0 -> Ok(#(state, state))
    count -> {
      use #(first_state, first_delta) <- result.try(delete(state, start))
      list.repeat(Nil, count - 1)
      |> list.try_fold(#(first_state, first_delta), fn(acc, _) {
        let #(current, delta) = acc
        use #(updated, next_delta) <- result.try(delete(current, start))
        Ok(#(updated, merge(delta, next_delta)))
      })
    }
  }
}
