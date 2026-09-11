import gleam/list
import lattice_core/replica_id
import lattice_sequence/sequence

pub fn state_and_delta_edits_return_the_same_bounds_errors_test() {
  let empty = sequence.new(replica_id.new("A"))
  let assert Ok(base) = sequence.insert_many(empty, 0, ["a", "b"])

  list.each([-1, 3], fn(index) {
    let error = sequence.IndexOutOfBounds(index, 2)
    sequence.insert(base, index, "x")
    |> fn(actual) {
      assert actual == { Error(error) }
    }
    sequence.insert_with_delta(base, index, "x")
    |> fn(actual) {
      assert actual == { Error(error) }
    }
    list.each([[], ["x"]], fn(values) {
      sequence.insert_many(base, index, values)
      |> fn(actual) {
        assert actual == { Error(error) }
      }
      sequence.insert_many_with_delta(base, index, values)
      |> fn(actual) {
        assert actual == { Error(error) }
      }
    })
    sequence.anchor_at(base, index, sequence.Before)
    |> fn(actual) {
      assert actual == { Error(sequence.AnchorIndexOutOfBounds(index, 2)) }
    }
  })
  list.each([-1, 2], fn(index) {
    let error = sequence.DeleteIndexOutOfBounds(index, 2)
    sequence.delete(base, index)
    |> fn(actual) {
      assert actual == { Error(error) }
    }
    sequence.delete_with_delta(base, index)
    |> fn(actual) {
      assert actual == { Error(error) }
    }
    let error = sequence.MoveFromIndexOutOfBounds(index, 2)
    sequence.move(base, index, 0)
    |> fn(actual) {
      assert actual == { Error(error) }
    }
    sequence.move_with_delta(base, index, 0)
    |> fn(actual) {
      assert actual == { Error(error) }
    }
    let error = sequence.MoveToIndexOutOfBounds(index, 1)
    sequence.move(base, 0, index)
    |> fn(actual) {
      assert actual == { Error(error) }
    }
    sequence.move_with_delta(base, 0, index)
    |> fn(actual) {
      assert actual == { Error(error) }
    }
  })
  sequence.delete(empty, 0)
  |> fn(actual) {
    assert actual == { Error(sequence.DeleteIndexOutOfBounds(0, 0)) }
  }
  sequence.delete_with_delta(empty, 0)
  |> fn(actual) {
    assert actual == { Error(sequence.DeleteIndexOutOfBounds(0, 0)) }
  }
  sequence.move(empty, 0, 0)
  |> fn(actual) {
    assert actual == { Error(sequence.MoveFromIndexOutOfBounds(0, 0)) }
  }
  sequence.move_with_delta(empty, 0, 0)
  |> fn(actual) {
    assert actual == { Error(sequence.MoveFromIndexOutOfBounds(0, 0)) }
  }
  sequence.values(base)
  |> fn(actual) {
    assert actual == { ["a", "b"] }
  }
}

pub fn state_edits_match_successful_delta_results_test() {
  let assert Ok(base) =
    sequence.insert_many(sequence.new(replica_id.new("A")), 0, ["a", "b"])
  let assert Ok(#(inserted, _)) = sequence.insert_with_delta(base, 2, "c")
  sequence.insert(base, 2, "c")
  |> fn(actual) {
    assert actual == { Ok(inserted) }
  }
  let assert Ok(#(inserted_many, _)) =
    sequence.insert_many_with_delta(base, 1, ["c", "d"])
  sequence.insert_many(base, 1, ["c", "d"])
  |> fn(actual) {
    assert actual == { Ok(inserted_many) }
  }
  let assert Ok(#(deleted, _)) = sequence.delete_with_delta(base, 0)
  sequence.delete(base, 0)
  |> fn(actual) {
    assert actual == { Ok(deleted) }
  }
  let assert Ok(#(moved, _)) = sequence.move_with_delta(base, 0, 1)
  sequence.move(base, 0, 1)
  |> fn(actual) {
    assert actual == { Ok(moved) }
  }
  sequence.insert_many(base, 2, [])
  |> fn(actual) {
    assert actual == { Ok(base) }
  }
}
