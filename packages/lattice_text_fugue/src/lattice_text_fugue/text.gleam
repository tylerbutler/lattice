//// A non-interleaving plain-text CRDT backed by `lattice_fugue`.
////
//// This is the fugue-backed counterpart to `lattice_text`. Both present the
//// same grapheme-oriented text API; the difference is the ordering guarantee
//// of the underlying sequence CRDT. `lattice_text` uses `lattice_sequence`
//// (YATA-style), which converges but can *interleave* two users' concurrent
//// runs of typing at the same position. `lattice_text_fugue` uses
//// `lattice_fugue`, which keeps each concurrent run contiguous.
////
//// ## Supported subset
////
//// Because `lattice_fugue` deliberately does not implement move or compaction,
//// this package exposes only the features that a fugue backend supports:
//// insert, delete, range edits, substring, append, position anchors, causal
//// frontier, merge, and JSON. There are no `move` or `compact` functions.
//// Applications that need those should use `lattice_text`.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_text_fugue/text
////
//// let doc =
////   text.new(replica_id.new("A"))
////   |> text.insert(0, "hello")
////   |> text.append(" world")
////
//// text.value(doc)  // -> "hello world"
//// ```

import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_fugue/sequence
import lattice_text_core/grapheme

/// A non-interleaving plain-text CRDT value.
pub opaque type Text {
  Text(sequence: sequence.Sequence(String))
}

/// An error returned when a grapheme range does not satisfy
/// `0 <= start <= end <= length`.
pub type RangeError {
  RangeOutOfBounds(start: Int, end: Int, length: Int)
}

/// Create an empty text CRDT for a replica.
pub fn new(replica_id: ReplicaId) -> Text {
  Text(sequence.new(replica_id))
}

/// Insert a value at the visible grapheme index.
///
/// Panics with `IndexOutOfBounds` when `index` is outside `[0, length]`. Use
/// `try_insert_with_delta` to handle an untrusted index without crashing.
pub fn insert(text: Text, index: Int, value: String) -> Text {
  let assert Ok(#(updated, _delta)) = try_insert_with_delta(text, index, value)
  updated
}

/// Insert a value and return both the updated text and insertion delta.
///
/// Panics with `IndexOutOfBounds` when `index` is outside `[0, length]`. Use
/// `try_insert_with_delta` to handle an untrusted index without crashing.
pub fn insert_with_delta(
  text: Text,
  index: Int,
  value: String,
) -> #(Text, Text) {
  let assert Ok(result) = try_insert_with_delta(text, index, value)
  result
}

/// Safely insert a value and return both the updated text and insertion delta.
pub fn try_insert_with_delta(
  text: Text,
  index: Int,
  value: String,
) -> Result(#(Text, Text), sequence.InsertError) {
  let Text(seq) = text
  value
  |> string.to_graphemes()
  |> insert_graphemes_with_delta(seq, index)
  |> result.map(fn(pair) {
    let #(updated, delta) = pair
    #(Text(updated), Text(delta))
  })
}

/// Delete the value at the visible grapheme index.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
/// Use `try_delete_with_delta` to handle an untrusted index without crashing.
pub fn delete(text: Text, index: Int) -> Text {
  let assert Ok(#(updated, _delta)) = try_delete_with_delta(text, index)
  updated
}

/// Delete a value and return both the updated text and deletion delta.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
/// Use `try_delete_with_delta` to handle an untrusted index without crashing.
pub fn delete_with_delta(text: Text, index: Int) -> #(Text, Text) {
  let assert Ok(result) = try_delete_with_delta(text, index)
  result
}

/// Safely delete a value and return both the updated text and deletion delta.
pub fn try_delete_with_delta(
  text: Text,
  index: Int,
) -> Result(#(Text, Text), sequence.DeleteError) {
  let Text(seq) = text
  case sequence.try_delete_with_delta(seq, index) {
    Ok(#(updated, delta)) -> Ok(#(Text(updated), Text(delta)))
    Error(error) -> Error(error)
  }
}

/// Return the visible graphemes as a list.
pub fn values(text: Text) -> List(String) {
  let Text(seq) = text
  sequence.values(seq)
}

/// Return the visible text as a single string.
pub fn value(text: Text) -> String {
  text
  |> values()
  |> grapheme.value()
}

/// Count the visible graphemes in the text.
pub fn length(text: Text) -> Int {
  let Text(seq) = text
  sequence.length(seq)
}

/// Return the graphemes in `[start, end)`, clamping both indexes to the text
/// bounds. An empty range (including `start > end`) yields `""`.
pub fn substring(text: Text, start: Int, end: Int) -> String {
  let len = length(text)
  grapheme.slice(values(text), int.clamp(start, 0, len), int.clamp(end, 0, len))
}

/// Return the graphemes in `[start, end)`, or an error when the range does not
/// satisfy `0 <= start <= end <= length`.
pub fn try_substring(
  text: Text,
  start: Int,
  end: Int,
) -> Result(String, RangeError) {
  use Nil <- result.try(validate_range(start, end, length(text)))
  Ok(grapheme.slice(values(text), start, end))
}

/// Delete the graphemes in `[start, end)`.
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_delete_range_with_delta` to handle untrusted bounds
/// without crashing.
pub fn delete_range(text: Text, start: Int, end: Int) -> Text {
  let assert Ok(#(updated, _delta)) =
    try_delete_range_with_delta(text, start, end)
  updated
}

/// Delete a grapheme range and return both the updated text and deletion delta.
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_delete_range_with_delta` to handle untrusted bounds
/// without crashing.
pub fn delete_range_with_delta(
  text: Text,
  start: Int,
  end: Int,
) -> #(Text, Text) {
  let assert Ok(result) = try_delete_range_with_delta(text, start, end)
  result
}

/// Safely delete a grapheme range and return both the updated text and deletion
/// delta.
pub fn try_delete_range_with_delta(
  text: Text,
  start: Int,
  end: Int,
) -> Result(#(Text, Text), RangeError) {
  let Text(seq) = text
  use Nil <- result.try(validate_range(start, end, sequence.length(seq)))
  delete_graphemes_with_delta(seq, start, end)
  |> result.map(fn(pair) {
    let #(updated, delta) = pair
    #(Text(updated), Text(delta))
  })
}

/// Replace the graphemes in `[start, end)` with a value.
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_replace_range_with_delta` to handle untrusted bounds
/// without crashing.
pub fn replace_range(text: Text, start: Int, end: Int, value: String) -> Text {
  let assert Ok(#(updated, _delta)) =
    try_replace_range_with_delta(text, start, end, value)
  updated
}

/// Replace a grapheme range and return both the updated text and replacement
/// delta.
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_replace_range_with_delta` to handle untrusted bounds
/// without crashing.
pub fn replace_range_with_delta(
  text: Text,
  start: Int,
  end: Int,
  value: String,
) -> #(Text, Text) {
  let assert Ok(result) = try_replace_range_with_delta(text, start, end, value)
  result
}

/// Safely replace a grapheme range and return both the updated text and
/// replacement delta.
pub fn try_replace_range_with_delta(
  text: Text,
  start: Int,
  end: Int,
  value: String,
) -> Result(#(Text, Text), RangeError) {
  let Text(seq) = text
  use Nil <- result.try(validate_range(start, end, sequence.length(seq)))
  use #(deleted, delete_delta) <- result.try(delete_graphemes_with_delta(
    seq,
    start,
    end,
  ))
  let graphemes = string.to_graphemes(value)
  use #(updated, insert_delta) <- result.try(
    insert_graphemes_with_delta(graphemes, deleted, start)
    |> result.map_error(insert_error_to_range_error),
  )
  let delta = case start == end, graphemes {
    True, _ -> insert_delta
    False, [] -> delete_delta
    False, _ -> sequence.merge(delete_delta, insert_delta)
  }
  Ok(#(Text(updated), Text(delta)))
}

/// Insert a value at the end of the text. Appending is always valid, so no
/// `try_` variant exists.
pub fn append(text: Text, value: String) -> Text {
  insert(text, length(text), value)
}

/// Append a value and return both the updated text and insertion delta.
pub fn append_with_delta(text: Text, value: String) -> #(Text, Text) {
  insert_with_delta(text, length(text), value)
}

// ---------------------------------------------------------------------------
// Anchors
// ---------------------------------------------------------------------------

/// Create an anchor at the start of the text. Always resolves to 0.
pub fn start_anchor() -> sequence.Anchor {
  sequence.start_anchor()
}

/// Create an anchor at the end of the text. Always resolves to the current
/// grapheme length, tracking growth.
pub fn end_anchor() -> sequence.Anchor {
  sequence.end_anchor()
}

/// Create an anchor at the gap before the grapheme at `index`.
///
/// Anchors are stable positions that survive concurrent edits and merges:
/// resolve one back to a current grapheme index with `resolve_anchor`.
/// `Before` bias glues the anchor to the grapheme at `index`, so inserts at the
/// gap push it right; `After` bias glues it to the grapheme at `index - 1`, so
/// inserts at the gap land after it.
///
/// Panics with `AnchorIndexOutOfBounds` when `index` is outside `[0, length]`.
/// Use `try_anchor_at` to handle an untrusted index without crashing.
pub fn anchor_at(
  text: Text,
  index: Int,
  bias: sequence.Bias,
) -> sequence.Anchor {
  let assert Ok(anchor) = try_anchor_at(text, index, bias)
  anchor
}

/// Safely create an anchor at the gap before the grapheme at `index`.
///
/// Valid positions are `0 <= index <= length`.
pub fn try_anchor_at(
  text: Text,
  index: Int,
  bias: sequence.Bias,
) -> Result(sequence.Anchor, sequence.AnchorError) {
  let Text(seq) = text
  sequence.try_anchor_at(seq, index, bias)
}

/// Resolve an anchor to a current grapheme index in `[0, length]`.
///
/// Anchors on deleted graphemes still resolve: they collapse to the gap where
/// the grapheme used to be. Panics with `UnknownAnchorTarget` when the target
/// was never merged into this replica; use `try_resolve_anchor` and treat
/// failure as "re-anchor".
pub fn resolve_anchor(text: Text, anchor: sequence.Anchor) -> Int {
  let assert Ok(index) = try_resolve_anchor(text, anchor)
  index
}

/// Safely resolve an anchor to a current grapheme index in `[0, length]`.
///
/// Returns `Error(UnknownAnchorTarget)` when the anchor references a grapheme
/// this replica has never seen (created remotely and not yet merged). Because
/// `lattice_fugue` never drops nodes, any grapheme that was ever merged remains
/// resolvable, so this is the only failure mode.
pub fn try_resolve_anchor(
  text: Text,
  anchor: sequence.Anchor,
) -> Result(Int, sequence.AnchorError) {
  let Text(seq) = text
  sequence.try_resolve(seq, anchor)
}

/// Encode an anchor as a self-describing JSON value.
pub fn anchor_to_json(anchor: sequence.Anchor) -> json.Json {
  sequence.anchor_to_json(anchor)
}

/// Decode an anchor from a JSON string produced by `anchor_to_json`.
pub fn anchor_from_json(
  json_string: String,
) -> Result(sequence.Anchor, json.DecodeError) {
  sequence.anchor_from_json(json_string)
}

// ---------------------------------------------------------------------------
// Frontier, merge, JSON
// ---------------------------------------------------------------------------

/// The causal frontier of this text: for each replica, the greatest node
/// counter it has minted that this replica has observed.
pub fn frontier(text: Text) -> VersionVector {
  let Text(seq) = text
  sequence.frontier(seq)
}

/// Merge two text CRDT states.
///
/// The merged content is order-independent, but the replica identity is NOT:
/// the result adopts `a`'s replica id. Call this as `merge(self, other)` —
/// local state first — or the result takes the remote's identity and later
/// local edits mint colliding node IDs. Deltas are ordinary `Text` values
/// stamped with the minting replica, so `merge(incoming_delta, state)` is the
/// easy way to get this wrong; use `merge_as` when the argument order is not
/// statically obvious.
pub fn merge(a: Text, b: Text) -> Text {
  let Text(a_seq) = a
  let Text(b_seq) = b
  Text(sequence.merge(a_seq, b_seq))
}

/// Merge two text CRDT states under an explicitly named replica identity.
///
/// Same as `merge`, except the merged state is stamped with `replica` instead
/// of inheriting the first argument's id, which makes the call fully
/// order-independent. Applying an incoming delta cannot re-mint local edits
/// under the sender's replica id, whichever side it is passed on.
pub fn merge_as(a: Text, b: Text, replica: ReplicaId) -> Text {
  let Text(a_seq) = a
  let Text(b_seq) = b
  Text(sequence.merge_as(a_seq, b_seq, replica))
}

/// Encode text using the canonical fugue sequence JSON envelope.
pub fn to_json(text: Text) -> json.Json {
  let Text(seq) = text
  sequence.to_json(seq, json.string)
}

/// Decode text from the canonical fugue sequence JSON envelope.
pub fn from_json(json_string: String) -> Result(Text, json.DecodeError) {
  case sequence.from_json(json_string, decode.string) {
    Ok(seq) -> Ok(Text(seq))
    Error(error) -> Error(error)
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn validate_range(
  start: Int,
  end: Int,
  length: Int,
) -> Result(Nil, RangeError) {
  grapheme.validate_range(start, end, length)
  |> result.map_error(fn(error) {
    let grapheme.RangeOutOfBounds(start:, end:, length:) = error
    RangeOutOfBounds(start:, end:, length:)
  })
}

fn insert_error_to_range_error(error: sequence.InsertError) -> RangeError {
  let sequence.IndexOutOfBounds(index, length) = error
  RangeOutOfBounds(start: index, end: index, length: length)
}

fn delete_graphemes_with_delta(
  seq: sequence.Sequence(String),
  start: Int,
  end: Int,
) -> Result(#(sequence.Sequence(String), sequence.Sequence(String)), RangeError) {
  use <- bool.guard(start == end, Ok(#(seq, sequence.empty_delta(seq))))
  grapheme.delete_graphemes(seq, start, end, delete_grapheme, sequence.merge)
}

fn delete_grapheme(
  seq: sequence.Sequence(String),
  index: Int,
) -> Result(#(sequence.Sequence(String), sequence.Sequence(String)), RangeError) {
  case sequence.try_delete_with_delta(seq, index) {
    Ok(pair) -> Ok(pair)
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(RangeOutOfBounds(start: index, end: index, length: length))
  }
}

fn insert_graphemes_with_delta(
  graphemes: List(String),
  seq: sequence.Sequence(String),
  index: Int,
) -> Result(
  #(sequence.Sequence(String), sequence.Sequence(String)),
  sequence.InsertError,
) {
  grapheme.insert_graphemes(
    graphemes,
    seq,
    index,
    sequence.length,
    fugue_insert_many,
    sequence.IndexOutOfBounds,
  )
}

/// Insert a grapheme run into the Fugue backend, one node at a time, threading
/// a merged delta. The Fugue backend has no batch primitive yet, so this folds
/// the single-node insert.
fn fugue_insert_many(
  seq: sequence.Sequence(String),
  index: Int,
  graphemes: List(String),
) -> Result(
  #(sequence.Sequence(String), sequence.Sequence(String)),
  sequence.InsertError,
) {
  case graphemes {
    [] -> Ok(#(seq, sequence.empty_delta(seq)))
    [first, ..rest] -> {
      use #(first_state, first_delta) <- result.try(
        sequence.try_insert_with_delta(seq, index, first),
      )
      list.try_fold(
        rest,
        #(first_state, first_delta, index + 1),
        fn(acc, grapheme) {
          let #(current, delta, current_index) = acc
          use #(updated, next_delta) <- result.try(
            sequence.try_insert_with_delta(current, current_index, grapheme),
          )
          Ok(#(updated, sequence.merge(delta, next_delta), current_index + 1))
        },
      )
      |> result.map(fn(acc) {
        let #(updated, delta, _) = acc
        #(updated, delta)
      })
    }
  }
}
