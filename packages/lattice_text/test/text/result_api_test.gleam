import gleam/list
import lattice_core/replica_id
import lattice_sequence/sequence
import lattice_text/text
import startest/expect

pub fn state_and_delta_edits_return_the_same_bounds_errors_test() {
  let empty = text.new(replica_id.new("A"))
  let assert Ok(base) = text.insert(empty, 0, "ab")

  list.each([-1, 3], fn(index) {
    list.each(["", "x"], fn(value) {
      let error = sequence.IndexOutOfBounds(index, 2)
      text.insert(base, index, value) |> expect.to_equal(Error(error))
      text.insert_with_delta(base, index, value)
      |> expect.to_equal(Error(error))
    })
    text.anchor_at(base, index, sequence.Before)
    |> expect.to_equal(Error(sequence.AnchorIndexOutOfBounds(index, 2)))
  })
  list.each([-1, 2], fn(index) {
    let error = sequence.DeleteIndexOutOfBounds(index, 2)
    text.delete(base, index) |> expect.to_equal(Error(error))
    text.delete_with_delta(base, index) |> expect.to_equal(Error(error))
    let error = sequence.MoveFromIndexOutOfBounds(index, 2)
    text.move(base, index, 0) |> expect.to_equal(Error(error))
    text.move_with_delta(base, index, 0) |> expect.to_equal(Error(error))
    let error = sequence.MoveToIndexOutOfBounds(index, 1)
    text.move(base, 0, index) |> expect.to_equal(Error(error))
    text.move_with_delta(base, 0, index) |> expect.to_equal(Error(error))
  })
  list.each([#(-1, 1), #(0, 3), #(2, 1), #(3, 3)], fn(bounds) {
    let #(start, end) = bounds
    let error = text.RangeOutOfBounds(start, end, 2)
    text.delete_range(base, start, end) |> expect.to_equal(Error(error))
    text.delete_range_with_delta(base, start, end)
    |> expect.to_equal(Error(error))
    list.each(["", "x"], fn(value) {
      text.replace_range(base, start, end, value)
      |> expect.to_equal(Error(error))
      text.replace_range_with_delta(base, start, end, value)
      |> expect.to_equal(Error(error))
    })
  })
  text.delete(empty, 0)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(0, 0)))
  text.delete_with_delta(empty, 0)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(0, 0)))
  text.move(empty, 0, 0)
  |> expect.to_equal(Error(sequence.MoveFromIndexOutOfBounds(0, 0)))
  text.move_with_delta(empty, 0, 0)
  |> expect.to_equal(Error(sequence.MoveFromIndexOutOfBounds(0, 0)))
  text.value(base) |> expect.to_equal("ab")
}

pub fn state_edits_match_successful_delta_results_test() {
  let local = replica_id.new("B")
  let assert Ok(base) = text.insert(text.new(local), 0, "abcd")
  let assert Ok(#(inserted, _)) = text.insert_with_delta(base, 4, "xy")
  text.insert(base, 4, "xy") |> expect.to_equal(Ok(inserted))
  let assert Ok(#(deleted, _)) = text.delete_with_delta(base, 0)
  text.delete(base, 0) |> expect.to_equal(Ok(deleted))
  let assert Ok(#(moved, _)) = text.move_with_delta(base, 0, 3)
  text.move(base, 0, 3) |> expect.to_equal(Ok(moved))

  list.each([#(0, 0), #(1, 3), #(0, 4)], fn(bounds) {
    let #(start, end) = bounds
    let assert Ok(#(deleted, delta)) =
      text.delete_range_with_delta(base, start, end)
    text.delete_range(base, start, end) |> expect.to_equal(Ok(deleted))
    text.merge(base, delta, local) |> expect.to_equal(deleted)
    text.merge(delta, base, local) |> expect.to_equal(deleted)
    list.each(["", "XY"], fn(value) {
      let assert Ok(#(replaced, delta)) =
        text.replace_range_with_delta(base, start, end, value)
      text.replace_range(base, start, end, value)
      |> expect.to_equal(Ok(replaced))
      text.merge(base, delta, local) |> expect.to_equal(replaced)
      text.merge(delta, base, local) |> expect.to_equal(replaced)
    })
  })
  list.each(["", "xy"], fn(value) {
    let assert Ok(#(appended, delta)) = text.append_with_delta(base, value)
    text.append(base, value) |> expect.to_equal(Ok(appended))
    text.merge(base, delta, local) |> expect.to_equal(appended)
    text.merge(delta, base, local) |> expect.to_equal(appended)
  })
}
