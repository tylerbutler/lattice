import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import qcheck

fn replay(state: sequence.Sequence(Int)) -> sequence.Sequence(Int) {
  let assert Ok(decoded) =
    state
    |> sequence.to_json(json.int)
    |> json.to_string()
    |> sequence.from_json(decode.int)
  decoded
}

fn edit_history(
  state: sequence.Sequence(Int),
  seed: Int,
  remaining: Int,
) -> #(sequence.Sequence(Int), List(sequence.Sequence(Int))) {
  case remaining {
    0 -> #(state, [])
    _ -> {
      let next = { seed * 1237 + 12_345 } % 1_000_003
      let size = sequence.length(state)
      let #(updated, delta) = case next % 3, size {
        0, _ | _, 0 -> {
          let assert Ok(edit) =
            sequence.insert_with_delta(state, next % { size + 1 }, next)
          edit
        }
        1, _ -> {
          let assert Ok(edit) = sequence.delete_with_delta(state, next % size)
          edit
        }
        _, _ -> {
          let assert Ok(edit) =
            sequence.move_with_delta(state, next % size, { next / 7 } % size)
          edit
        }
      }
      let #(final, deltas) = edit_history(updated, next, remaining - 1)
      #(final, [replay(delta), ..deltas])
    }
  }
}

pub fn partial_compaction_and_delayed_duplicate_delivery_converge_test() -> Nil {
  qcheck.run(
    qcheck.config(test_count: 2000, max_retries: 3, seed: qcheck.seed(250)),
    qcheck.bounded_int(0, 100_000),
    fn(seed) {
      let a = replica_id.new("A")
      let b = replica_id.new("B")
      let c = replica_id.new("C")
      let assert Ok(#(base, old_b)) =
        sequence.insert_many_with_delta(sequence.new(b), 0, [0, 1, 2])
      let base = sequence.merge(sequence.new(a), base, a)
      let assert Ok(#(base, old_a)) =
        sequence.insert_with_delta(base, seed % 4, 3)
      let stable =
        version_vector.new()
        |> version_vector.set_max(a, 4)
        |> version_vector.set_max(b, 3)
      let #(compacted, _) = sequence.compact(sequence.bind(base, b), stable)
      let #(sender, deltas_b) = edit_history(compacted, seed, 4)
      let #(peer, deltas_c) = edit_history(sequence.bind(base, c), seed + 17, 4)
      let delayed =
        list.append(deltas_b, [old_a, old_b, ..list.reverse(deltas_c)])
      let left =
        list.fold(delayed, base, fn(state, delta) {
          sequence.merge(state, delta, a)
        })
      let right =
        delayed
        |> list.reverse()
        |> list.index_fold(base, fn(state, delta, index) {
          let state = case index == seed % 8 {
            True -> {
              let #(compacted, _) = sequence.compact(state, stable)
              compacted
            }
            False -> state
          }
          sequence.merge(state, delta, a)
        })
      assert sequence.values(left) == sequence.values(right)
      let expected = sequence.merge(sender, peer, a)
      assert sequence.values(left) == sequence.values(expected)
      let finish = fn(state) {
        state
        |> sequence.merge(expected, a)
        |> sequence.merge(old_a, a)
        |> sequence.merge(old_b, a)
      }
      let left = finish(left)
      let right = finish(right)
      assert left == right
      assert sequence.merge(left, right, a) == sequence.merge(right, left, a)
      assert sequence.values(replay(left)) == sequence.values(left)
      Nil
    },
  )
}
