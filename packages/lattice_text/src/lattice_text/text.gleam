//// A plain-text CRDT backed by `lattice_sequence`.
////
//// Text stores each inserted string segment as a sequence item. Insert,
//// delete, move, merge, and delta operations delegate to `lattice_sequence`.
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

import gleam/dynamic/decode
import gleam/json
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence

pub opaque type Text {
  Text(sequence: sequence.Sequence(String))
}

/// An error returned when an insert cannot be applied.
pub type InsertError {
  IndexOutOfBounds(index: Int, length: Int)
}

/// An error returned when a delete cannot be applied.
pub type DeleteError {
  DeleteIndexOutOfBounds(index: Int, length: Int)
}

/// An error returned when a move cannot be applied.
pub type MoveError {
  MoveFromIndexOutOfBounds(index: Int, length: Int)
  MoveToIndexOutOfBounds(index: Int, length_after_removal: Int)
}

pub fn new(replica_id: ReplicaId) -> Text {
  Text(sequence.new(replica_id))
}

/// Insert a value at the visible character index.
pub fn insert(text: Text, index: Int, value: String) -> Text {
  let assert Ok(updated) = try_insert(text, index, value)
  updated
}

/// Safely insert a value at the visible character index.
pub fn try_insert(
  text: Text,
  index: Int,
  value: String,
) -> Result(Text, InsertError) {
  let Text(seq) = text
  case sequence.try_insert(seq, index, value) {
    Ok(updated) -> Ok(Text(updated))
    Error(sequence.IndexOutOfBounds(index, length)) ->
      Error(IndexOutOfBounds(index: index, length: length))
  }
}

/// Insert a value and return both the updated text and insertion delta.
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
) -> Result(#(Text, Text), InsertError) {
  let Text(seq) = text
  case sequence.try_insert_with_delta(seq, index, value) {
    Ok(#(updated, delta)) -> Ok(#(Text(updated), Text(delta)))
    Error(sequence.IndexOutOfBounds(index, length)) ->
      Error(IndexOutOfBounds(index: index, length: length))
  }
}

/// Delete the value at the visible character index.
pub fn delete(text: Text, index: Int) -> Text {
  let assert Ok(updated) = try_delete(text, index)
  updated
}

/// Safely delete the value at the visible character index.
pub fn try_delete(text: Text, index: Int) -> Result(Text, DeleteError) {
  let Text(seq) = text
  case sequence.try_delete(seq, index) {
    Ok(updated) -> Ok(Text(updated))
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(DeleteIndexOutOfBounds(index: index, length: length))
  }
}

/// Delete a value and return both the updated text and deletion delta.
pub fn delete_with_delta(text: Text, index: Int) -> #(Text, Text) {
  let assert Ok(result) = try_delete_with_delta(text, index)
  result
}

/// Safely delete a value and return both the updated text and deletion delta.
pub fn try_delete_with_delta(
  text: Text,
  index: Int,
) -> Result(#(Text, Text), DeleteError) {
  let Text(seq) = text
  case sequence.try_delete_with_delta(seq, index) {
    Ok(#(updated, delta)) -> Ok(#(Text(updated), Text(delta)))
    Error(sequence.DeleteIndexOutOfBounds(index, length)) ->
      Error(DeleteIndexOutOfBounds(index: index, length: length))
  }
}

/// Move a visible text segment to another visible index.
///
/// The `to_index` is interpreted after removing the segment from `from_index`.
pub fn move(text: Text, from_index: Int, to_index: Int) -> Text {
  let assert Ok(updated) = try_move(text, from_index, to_index)
  updated
}

/// Safely move a visible text segment to another visible index.
///
/// The `to_index` is interpreted after removing the segment from `from_index`.
pub fn try_move(
  text: Text,
  from_index: Int,
  to_index: Int,
) -> Result(Text, MoveError) {
  let Text(seq) = text
  case sequence.try_move(seq, from_index, to_index) {
    Ok(updated) -> Ok(Text(updated))
    Error(sequence.MoveFromIndexOutOfBounds(index, length)) ->
      Error(MoveFromIndexOutOfBounds(index: index, length: length))
    Error(sequence.MoveToIndexOutOfBounds(index, length_after_removal)) ->
      Error(MoveToIndexOutOfBounds(
        index: index,
        length_after_removal: length_after_removal,
      ))
  }
}

/// Move a visible text segment and return both the updated text and move delta.
pub fn move_with_delta(
  text: Text,
  from_index: Int,
  to_index: Int,
) -> #(Text, Text) {
  let assert Ok(result) = try_move_with_delta(text, from_index, to_index)
  result
}

/// Safely move a visible text segment and return both the updated text and move
/// delta.
pub fn try_move_with_delta(
  text: Text,
  from_index: Int,
  to_index: Int,
) -> Result(#(Text, Text), MoveError) {
  let Text(seq) = text
  case sequence.try_move_with_delta(seq, from_index, to_index) {
    Ok(#(updated, delta)) -> Ok(#(Text(updated), Text(delta)))
    Error(sequence.MoveFromIndexOutOfBounds(index, length)) ->
      Error(MoveFromIndexOutOfBounds(index: index, length: length))
    Error(sequence.MoveToIndexOutOfBounds(index, length_after_removal)) ->
      Error(MoveToIndexOutOfBounds(
        index: index,
        length_after_removal: length_after_removal,
      ))
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
