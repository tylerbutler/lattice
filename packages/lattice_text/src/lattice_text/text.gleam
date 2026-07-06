//// A plain-text CRDT backed by `lattice_sequence`.
////
//// Text stores each inserted string segment as a sequence item. Insert,
//// delete, merge, and delta operations delegate to `lattice_sequence`.
//// Use `lattice_sequence/sequence` directly when you need a generic list CRDT.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_text/text
////
//// let doc = text.new(replica_id.new("node-a"))
//// text.value(doc)  // -> ""
//// ```

import gleam/bool
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_sequence/sequence
import lattice_text_core/grapheme

pub opaque type Text {
  Text(sequence: sequence.Sequence(String))
}

/// An error returned when a grapheme range does not satisfy
/// `0 <= start <= end <= length`.
pub type RangeError {
  RangeOutOfBounds(start: Int, end: Int, length: Int)
}

pub fn new(replica_id: ReplicaId) -> Text {
  Text(sequence.new(replica_id))
}

/// Insert a value at the visible character index.
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

/// Delete the value at the visible character index.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside
/// `[0, length)`. Use `try_delete_with_delta` to handle an untrusted index
/// without crashing.
pub fn delete(text: Text, index: Int) -> Text {
  let assert Ok(#(updated, _delta)) = try_delete_with_delta(text, index)
  updated
}

/// Delete a value and return both the updated text and deletion delta.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside
/// `[0, length)`. Use `try_delete_with_delta` to handle an untrusted index
/// without crashing.
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

pub fn values(text: Text) -> List(String) {
  let Text(seq) = text
  sequence.values(seq)
}

pub fn value(text: Text) -> String {
  text
  |> values()
  |> string.concat()
}

/// Count the visible graphemes in the text.
///
/// ## Examples
///
/// ```gleam
/// text.new(replica_id.new("A"))
/// |> text.insert(0, "a👍")
/// |> text.length()
/// // -> 2
/// ```
pub fn length(text: Text) -> Int {
  let Text(seq) = text
  sequence.length(seq)
}

/// Return the graphemes in `[start, end)`, clamping both indexes to the
/// text bounds. An empty range (including `start > end`) yields `""`.
///
/// ## Examples
///
/// ```gleam
/// text.new(replica_id.new("A"))
/// |> text.insert(0, "abcd")
/// |> text.substring(1, 3)
/// // -> "bc"
/// ```
pub fn substring(text: Text, start: Int, end: Int) -> String {
  let len = length(text)
  slice_values(text, int.clamp(start, 0, len), int.clamp(end, 0, len))
}

/// Return the graphemes in `[start, end)`, or an error when the range does
/// not satisfy `0 <= start <= end <= length`.
///
/// ## Examples
///
/// ```gleam
/// text.new(replica_id.new("A"))
/// |> text.insert(0, "abc")
/// |> text.try_substring(0, 4)
/// // -> Error(text.RangeOutOfBounds(start: 0, end: 4, length: 3))
/// ```
pub fn try_substring(
  text: Text,
  start: Int,
  end: Int,
) -> Result(String, RangeError) {
  use Nil <- result.try(validate_range(start, end, length(text)))
  Ok(slice_values(text, start, end))
}

/// Delete the graphemes in `[start, end)`.
///
/// ## Examples
///
/// ```gleam
/// text.new(replica_id.new("A"))
/// |> text.insert(0, "abcd")
/// |> text.delete_range(1, 3)
/// |> text.value()
/// // -> "ad"
/// ```
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_delete_range_with_delta` to handle untrusted
/// bounds without crashing.
pub fn delete_range(text: Text, start: Int, end: Int) -> Text {
  let assert Ok(#(updated, _delta)) =
    try_delete_range_with_delta(text, start, end)
  updated
}

/// Delete a grapheme range and return both the updated text and deletion
/// delta.
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_delete_range_with_delta` to handle untrusted
/// bounds without crashing.
pub fn delete_range_with_delta(
  text: Text,
  start: Int,
  end: Int,
) -> #(Text, Text) {
  let assert Ok(result) = try_delete_range_with_delta(text, start, end)
  result
}

/// Safely delete a grapheme range and return both the updated text and
/// deletion delta.
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
/// ## Examples
///
/// ```gleam
/// text.new(replica_id.new("A"))
/// |> text.insert(0, "abcd")
/// |> text.replace_range(1, 3, "XY")
/// |> text.value()
/// // -> "aXYd"
/// ```
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_replace_range_with_delta` to handle untrusted
/// bounds without crashing.
pub fn replace_range(text: Text, start: Int, end: Int, value: String) -> Text {
  let assert Ok(#(updated, _delta)) =
    try_replace_range_with_delta(text, start, end, value)
  updated
}

/// Replace a grapheme range and return both the updated text and
/// replacement delta.
///
/// Panics with `RangeOutOfBounds` when `[start, end)` is not a valid range in
/// `[0, length]`. Use `try_replace_range_with_delta` to handle untrusted
/// bounds without crashing.
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
    True, [] -> updated
    True, _ -> insert_delta
    False, [] -> delete_delta
    False, _ -> sequence.merge(delete_delta, insert_delta)
  }
  Ok(#(Text(updated), Text(delta)))
}

/// Move the grapheme at `from_index` to `to_index`.
///
/// The `to_index` is interpreted after removing the grapheme from
/// `from_index`.
///
/// ## Examples
///
/// ```gleam
/// text.new(replica_id.new("A"))
/// |> text.insert(0, "abc")
/// |> text.move(0, 2)
/// |> text.value()
/// // -> "bca"
/// ```
///
/// Panics with a `MoveError` when either index is out of bounds. Use
/// `try_move_with_delta` to handle untrusted indices without crashing.
pub fn move(text: Text, from_index: Int, to_index: Int) -> Text {
  let assert Ok(#(updated, _delta)) =
    try_move_with_delta(text, from_index, to_index)
  updated
}

/// Move a grapheme and return both the updated text and move delta.
///
/// Panics with a `MoveError` when either index is out of bounds. Use
/// `try_move_with_delta` to handle untrusted indices without crashing.
pub fn move_with_delta(
  text: Text,
  from_index: Int,
  to_index: Int,
) -> #(Text, Text) {
  let assert Ok(result) = try_move_with_delta(text, from_index, to_index)
  result
}

/// Safely move a grapheme and return both the updated text and move delta.
///
/// The `to_index` is interpreted after removing the grapheme from
/// `from_index`.
pub fn try_move_with_delta(
  text: Text,
  from_index: Int,
  to_index: Int,
) -> Result(#(Text, Text), sequence.MoveError) {
  let Text(seq) = text
  case sequence.try_move_with_delta(seq, from_index, to_index) {
    Ok(#(updated, delta)) -> Ok(#(Text(updated), Text(delta)))
    Error(error) -> Error(error)
  }
}

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
/// `Before` bias glues the anchor to the grapheme at `index`, so inserts at
/// the gap push it right; `After` bias glues it to the grapheme at
/// `index - 1`, so inserts at the gap land after it.
///
/// ## Examples
///
/// ```gleam
/// let doc = text.new(replica_id.new("A")) |> text.insert(0, "hello")
/// let cursor = text.anchor_at(doc, 5, sequence.After)
/// let doc = text.insert(doc, 0, "say ")
/// text.resolve_anchor(doc, cursor)  // -> 9
/// ```
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
/// Anchors on deleted graphemes still resolve: they collapse to the gap
/// where the grapheme used to be. Anchors follow moved graphemes. Panics
/// with `UnknownAnchorTarget` when the target was never merged or was
/// compacted away and its forwarding has expired — hosts holding anchors
/// across compaction rounds should use `try_resolve_anchor` and treat
/// failure as "re-anchor".
pub fn resolve_anchor(text: Text, anchor: sequence.Anchor) -> Int {
  let assert Ok(index) = try_resolve_anchor(text, anchor)
  index
}

/// Safely resolve an anchor to a current grapheme index in `[0, length]`.
///
/// Anchors to compacted graphemes resolve through the forwarding map to the
/// gap the grapheme left behind — semantically the same as tombstone
/// collapse.
///
/// Returns `Error(UnknownAnchorTarget)` when the anchor references a
/// grapheme this replica has never seen (created remotely and not yet
/// merged), or one that was compacted away and whose forwarding entry has
/// since been removed by the host's retention policy. Either way the anchor
/// is unusable and the holder should re-anchor.
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

/// Insert a value at the end of the text. Appending is always valid, so no
/// `try_` variant exists.
///
/// ## Examples
///
/// ```gleam
/// text.new(replica_id.new("A"))
/// |> text.insert(0, "ab")
/// |> text.append("cd")
/// |> text.value()
/// // -> "abcd"
/// ```
pub fn append(text: Text, value: String) -> Text {
  insert(text, length(text), value)
}

/// Append a value and return both the updated text and insertion delta.
pub fn append_with_delta(text: Text, value: String) -> #(Text, Text) {
  insert_with_delta(text, length(text), value)
}

fn validate_range(
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

fn slice_values(text: Text, start: Int, end: Int) -> String {
  grapheme.slice(values(text), start, end)
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
    sequence.try_insert_with_delta,
    sequence.merge,
    sequence.IndexOutOfBounds,
  )
}

/// Compact everything at or below a stability frontier.
///
/// Delegates to `sequence.compact`: stable tombstones are dropped, runs of
/// stable graphemes are merged into compact blocks, and every dropped ID
/// gets a forwarding entry so anchors and rebased operations still resolve.
/// See `lattice_sequence/sequence.compact` for the stability contract.
pub fn compact(
  text: Text,
  stable: VersionVector,
) -> #(Text, sequence.ForwardingMap) {
  let Text(seq) = text
  let #(compacted, forwardings) = sequence.compact(seq, stable)
  #(Text(compacted), forwardings)
}

/// Remove previously emitted forwarding entries from the text.
///
/// Forwardings are bounded by the host's retention policy: keep the map
/// returned by each `compact` round and expire old rounds by passing them
/// here.
pub fn remove_forwardings(text: Text, map: sequence.ForwardingMap) -> Text {
  let Text(seq) = text
  Text(sequence.remove_forwardings(seq, map))
}

/// The stability frontier this text was last compacted at.
pub fn frontier(text: Text) -> VersionVector {
  let Text(seq) = text
  sequence.frontier(seq)
}

/// Merge two text CRDT states.
pub fn merge(a: Text, b: Text) -> Text {
  let Text(a_seq) = a
  let Text(b_seq) = b
  Text(sequence.merge(a_seq, b_seq))
}

/// Encode text using the canonical sequence JSON envelope.
pub fn to_json(text: Text) -> json.Json {
  let Text(seq) = text
  sequence.to_json(seq, json.string)
}

/// Decode text from the canonical sequence JSON envelope.
pub fn from_json(json_string: String) -> Result(Text, json.DecodeError) {
  case sequence.from_json(json_string, decode.string) {
    Ok(seq) -> Ok(Text(seq))
    Error(error) -> Error(error)
  }
}
