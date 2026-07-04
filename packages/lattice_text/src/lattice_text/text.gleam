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

import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence

pub opaque type Text {
  Text(sequence: sequence.Sequence(String))
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
) -> Result(Text, sequence.InsertError) {
  let Text(seq) = text
  value
  |> string.to_graphemes()
  |> insert_graphemes(seq, index)
  |> result.map(Text)
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
pub fn delete(text: Text, index: Int) -> Text {
  let assert Ok(updated) = try_delete(text, index)
  updated
}

/// Safely delete the value at the visible character index.
pub fn try_delete(
  text: Text,
  index: Int,
) -> Result(Text, sequence.DeleteError) {
  let Text(seq) = text
  case sequence.try_delete(seq, index) {
    Ok(updated) -> Ok(Text(updated))
    Error(error) -> Error(error)
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

fn insert_graphemes(
  graphemes: List(String),
  seq: sequence.Sequence(String),
  index: Int,
) -> Result(sequence.Sequence(String), sequence.InsertError) {
  let length = sequence.length(seq)
  case graphemes, index < 0 || index > length {
    _, True -> Error(sequence.IndexOutOfBounds(index: index, length: length))
    [], False -> Ok(seq)
    _, False -> {
      use #(updated, _) <- result.try(
        list.try_fold(graphemes, #(seq, index), fn(state, grapheme) {
          let #(current, current_index) = state
          case sequence.try_insert(current, current_index, grapheme) {
            Ok(updated) -> Ok(#(updated, current_index + 1))
            Error(error) -> Error(error)
          }
        }),
      )
      Ok(updated)
    }
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
  let length = sequence.length(seq)
  case graphemes, index < 0 || index > length {
    _, True -> Error(sequence.IndexOutOfBounds(index: index, length: length))
    [], False -> Ok(#(seq, seq))
    [first, ..rest], False -> {
      use #(first_updated, first_delta) <- result.try(
        sequence.try_insert_with_delta(seq, index, first),
      )
      list.try_fold(
        rest,
        #(first_updated, first_delta, index + 1),
        fn(state, grapheme) {
          let #(current, delta, current_index) = state
          use #(updated, next_delta) <- result.try(
            sequence.try_insert_with_delta(current, current_index, grapheme),
          )
          Ok(#(updated, sequence.merge(delta, next_delta), current_index + 1))
        },
      )
      |> result.map(fn(state) {
        let #(updated, delta, _) = state
        #(updated, delta)
      })
    }
  }
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
