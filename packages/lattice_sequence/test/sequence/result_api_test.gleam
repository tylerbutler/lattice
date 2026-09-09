import gleam/list
import lattice_core/replica_id
import lattice_sequence/sequence
import startest/expect

pub fn state_and_delta_edits_return_the_same_bounds_errors_test() {
  let empty = sequence.new(replica_id.new("A"))
  let assert Ok(base) = sequence.insert_many(empty, 0, ["a", "b"])

  list.each([-1, 3], fn(index) {
    let error = sequence.IndexOutOfBounds(index, 2)
    sequence.insert(base, index, "x") |> expect.to_equal(Error(error))
    sequence.insert_with_delta(base, index, "x")
    |> expect.to_equal(Error(error))
    list.each([[], ["x"]], fn(values) {
      sequence.insert_many(base, index, values)
      |> expect.to_equal(Error(error))
      sequence.insert_many_with_delta(base, index, values)
      |> expect.to_equal(Error(error))
    })
    sequence.anchor_at(base, index, sequence.Before)
    |> expect.to_equal(Error(sequence.AnchorIndexOutOfBounds(index, 2)))
  })
  list.each([-1, 2], fn(index) {
    let error = sequence.DeleteIndexOutOfBounds(index, 2)
    sequence.delete(base, index) |> expect.to_equal(Error(error))
    sequence.delete_with_delta(base, index) |> expect.to_equal(Error(error))
    let error = sequence.MoveFromIndexOutOfBounds(index, 2)
    sequence.move(base, index, 0) |> expect.to_equal(Error(error))
    sequence.move_with_delta(base, index, 0) |> expect.to_equal(Error(error))
    let error = sequence.MoveToIndexOutOfBounds(index, 1)
    sequence.move(base, 0, index) |> expect.to_equal(Error(error))
    sequence.move_with_delta(base, 0, index) |> expect.to_equal(Error(error))
  })
  sequence.delete(empty, 0)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(0, 0)))
  sequence.delete_with_delta(empty, 0)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(0, 0)))
  sequence.move(empty, 0, 0)
  |> expect.to_equal(Error(sequence.MoveFromIndexOutOfBounds(0, 0)))
  sequence.move_with_delta(empty, 0, 0)
  |> expect.to_equal(Error(sequence.MoveFromIndexOutOfBounds(0, 0)))
  sequence.values(base) |> expect.to_equal(["a", "b"])
}

pub fn state_edits_match_successful_delta_results_test() {
  let assert Ok(base) =
    sequence.insert_many(sequence.new(replica_id.new("A")), 0, ["a", "b"])
  let assert Ok(#(inserted, _)) = sequence.insert_with_delta(base, 2, "c")
  sequence.insert(base, 2, "c") |> expect.to_equal(Ok(inserted))
  let assert Ok(#(inserted_many, _)) =
    sequence.insert_many_with_delta(base, 1, ["c", "d"])
  sequence.insert_many(base, 1, ["c", "d"])
  |> expect.to_equal(Ok(inserted_many))
  let assert Ok(#(deleted, _)) = sequence.delete_with_delta(base, 0)
  sequence.delete(base, 0) |> expect.to_equal(Ok(deleted))
  let assert Ok(#(moved, _)) = sequence.move_with_delta(base, 0, 1)
  sequence.move(base, 0, 1) |> expect.to_equal(Ok(moved))
  sequence.insert_many(base, 2, []) |> expect.to_equal(Ok(base))
}
