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
import gleam/list
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_sequence/sequence

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
pub fn delete_range(text: Text, start: Int, end: Int) -> Text {
  let assert Ok(updated) = try_delete_range(text, start, end)
  updated
}

/// Safely delete the graphemes in `[start, end)`.
pub fn try_delete_range(
  text: Text,
  start: Int,
  end: Int,
) -> Result(Text, RangeError) {
  case try_delete_range_with_delta(text, start, end) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Delete a grapheme range and return both the updated text and deletion
/// delta.
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
pub fn replace_range(text: Text, start: Int, end: Int, value: String) -> Text {
  let assert Ok(updated) = try_replace_range(text, start, end, value)
  updated
}

/// Safely replace the graphemes in `[start, end)` with a value.
pub fn try_replace_range(
  text: Text,
  start: Int,
  end: Int,
  value: String,
) -> Result(Text, RangeError) {
  case try_replace_range_with_delta(text, start, end, value) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Replace a grapheme range and return both the updated text and
/// replacement delta.
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
pub fn move(text: Text, from_index: Int, to_index: Int) -> Text {
  let assert Ok(updated) = try_move(text, from_index, to_index)
  updated
}

/// Safely move the grapheme at `from_index` to `to_index`.
///
/// The `to_index` is interpreted after removing the grapheme from
/// `from_index`.
pub fn try_move(
  text: Text,
  from_index: Int,
  to_index: Int,
) -> Result(Text, sequence.MoveError) {
  case try_move_with_delta(text, from_index, to_index) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Move a grapheme and return both the updated text and move delta.
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
  text
  |> values()
  |> list.drop(start)
  |> list.take(end - start)
  |> string.concat()
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
  case end - start {
    0 -> Ok(#(seq, seq))
    count -> {
      use #(first_updated, first_delta) <- result.try(delete_grapheme(
        seq,
        start,
      ))
      list.repeat(Nil, count - 1)
      |> list.try_fold(#(first_updated, first_delta), fn(state, _) {
        let #(current, delta) = state
        use #(updated, next_delta) <- result.try(delete_grapheme(current, start))
        Ok(#(updated, sequence.merge(delta, next_delta)))
      })
    }
  }
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
