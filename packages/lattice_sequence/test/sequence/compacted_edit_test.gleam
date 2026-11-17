import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence

fn mixed_origin_base() -> sequence.Sequence(String) {
  let a = replica_id.new("A")
  let b = replica_id.new("B")
  let assert Ok(base) =
    sequence.insert_many(sequence.new(b), 0, ["L", "X", "W"])
  let base = sequence.merge(sequence.new(a), base, a)
  let assert Ok(base) = sequence.insert(base, 1, "P")
  base
}

fn mixed_frontier() -> version_vector.VersionVector {
  version_vector.new()
  |> version_vector.set_max(replica_id.new("A"), 4)
  |> version_vector.set_max(replica_id.new("B"), 3)
}

fn replay(state: sequence.Sequence(String)) -> sequence.Sequence(String) {
  let assert Ok(decoded) =
    state
    |> sequence.to_json(json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)
  decoded
}

fn check_compacted_edit(moving: Bool) -> Nil {
  let a = replica_id.new("A")
  let b = replica_id.new("B")
  let base = mixed_origin_base()
  let #(sender, _) =
    sequence.compact(sequence.merge(sequence.new(b), base, b), mixed_frontier())
  let #(sender, delta, expected) = case moving {
    True -> {
      let assert Ok(#(sender, delta)) = sequence.move_with_delta(sender, 2, 0)
      #(sender, delta, ["X", "L", "P", "W"])
    }
    False -> {
      let assert Ok(#(sender, delta)) = sequence.delete_with_delta(sender, 2)
      #(sender, delta, ["L", "P", "W"])
    }
  }
  assert sequence.values(sender) == expected
  assert delta == sender
  list.each([delta, sender, replay(delta), replay(sender)], fn(incoming) {
    list.each(
      [
        sequence.merge(base, incoming, a),
        sequence.merge(incoming, base, a),
      ],
      fn(receiver) {
        assert sequence.values(receiver) == expected
        let #(receiver, _) = sequence.compact(receiver, mixed_frontier())
        assert sequence.values(receiver) == expected
        assert sequence.merge(receiver, sender, a)
          == sequence.merge(sender, receiver, a)
        assert sequence.values(sequence.merge(receiver, sender, a)) == expected
      },
    )
  })
}

pub fn compacted_sender_delete_preserves_uncompacted_receiver_order_test() -> Nil {
  check_compacted_edit(False)
}

pub fn compacted_sender_move_preserves_uncompacted_receiver_order_test() -> Nil {
  check_compacted_edit(True)
}

pub fn covered_delete_and_old_insert_join_in_either_order_test() -> Nil {
  check_covered_edit_join(False)
}

pub fn covered_move_and_old_insert_join_in_either_order_test() -> Nil {
  check_covered_edit_join(True)
}

fn check_covered_edit_join(moving: Bool) -> Nil {
  let a = replica_id.new("A")
  let b = replica_id.new("B")
  let assert Ok(#(base, insertion)) =
    sequence.insert_many_with_delta(sequence.new(b), 0, ["1", "2"])
  let stable = version_vector.new() |> version_vector.set_max(b, 2)
  let #(sender, _) = sequence.compact(base, stable)
  let #(receiver, _) =
    sequence.compact(sequence.merge(sequence.new(a), insertion, a), stable)
  let #(edited, delta) = case moving {
    True -> {
      let assert Ok(edit) = sequence.move_with_delta(sender, 0, 1)
      edit
    }
    False -> {
      let assert Ok(edit) = sequence.delete_with_delta(sender, 0)
      edit
    }
  }
  use delta <- list.each([delta, replay(delta)])
  use insertion <- list.each([insertion, replay(insertion)])
  let first =
    receiver
    |> sequence.merge(delta, a)
    |> sequence.merge(insertion, a)
  let second =
    receiver
    |> sequence.merge(insertion, a)
    |> sequence.merge(delta, a)
  let grouped = sequence.merge(receiver, sequence.merge(delta, insertion, a), a)
  assert first == second
  assert first == grouped
  assert sequence.values(first) == sequence.values(edited)
  assert sequence.merge(first, first, a) == first
  let assert Ok(#(edited_again, sparse)) = sequence.move_with_delta(first, 0, 0)
  assert sequence.frontier(sparse) == version_vector.new()
  assert sequence.length(sparse) == 1
  assert sequence.merge(first, sparse, a) == edited_again
}
