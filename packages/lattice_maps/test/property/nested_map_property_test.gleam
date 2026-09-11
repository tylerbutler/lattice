import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_maps/or_map
import lattice_sequence/sequence
import qcheck
import support/composition_fixture as fixture

fn config() {
  qcheck.config(test_count: 100, max_retries: 3, seed: qcheck.seed(53))
}

pub fn nested_three_replica_insert_delete_move_metadata_convergence_test() {
  qcheck.run(config(), qcheck.bounded_int(10, 1000), fn(number) {
    let baseline = fixture.nested("A", [1, 2, 3, 4])
    let #(a, da) = fixture.append(baseline, number)
    let #(b, db) =
      fixture.edit(or_map.bind(baseline, replica_id.new("B")), fn(value) {
        let assert Ok(#(_, delta)) = sequence.delete_with_delta(value, 1)
        delta
      })
    let #(c, dc) =
      fixture.edit(or_map.bind(baseline, replica_id.new("C")), fn(value) {
        let assert Ok(#(_, delta)) = sequence.move_with_delta(value, 3, 0)
        delta
      })
    let receiver = replica_id.new("R")
    let assert Ok(ab) = or_map.merge_as(a, b, receiver)
    let assert Ok(abc) = or_map.merge(ab, c)
    let assert Ok(bc) = or_map.merge_as(b, c, receiver)
    let assert Ok(other) = or_map.merge(bc, a)
    abc
    |> fn(assertion_actual) {
      let assert True = assertion_actual == other
    }
    let assert Ok(idempotent) = or_map.merge(abc, abc)
    abc
    |> fn(assertion_actual) {
      let assert True = assertion_actual == idempotent
    }
    let assert Ok(reordered) =
      list.try_fold(
        [dc, da, db, da, dc, db],
        or_map.bind(baseline, receiver),
        or_map.apply_delta,
      )
    reordered
    |> fn(assertion_actual) {
      let assert True = assertion_actual == abc
    }
    let assert Ok(decoded) =
      or_map.from_json_with(
        or_map.to_json_with(abc, json.int) |> json.to_string,
        decode.int,
      )
    decoded
    |> fn(assertion_actual) {
      let assert True = assertion_actual == abc
    }
    let #(next_a, _) = fixture.append(abc, number + 1)
    let #(next_b, _) = fixture.append(reordered, number + 1)
    next_a
    |> fn(assertion_actual) {
      let assert True = assertion_actual == next_b
    }
    fixture.sequence(abc)
    |> sequence.length
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 4
    }
    Nil
  })
}

pub fn nested_reset_conflicts_generation_join_laws_test() {
  qcheck.run(config(), qcheck.bounded_int(1, 1000), fn(number) {
    let baseline = fixture.nested("A", [0])
    let removed = or_map.remove(baseline, "doc")
    let #(a, da) = fixture.append(removed, number)
    let #(b, db) =
      fixture.append(or_map.bind(baseline, replica_id.new("B")), number + 1)
    let #(c, dc) =
      fixture.append(or_map.bind(removed, replica_id.new("C")), number + 2)
    let receiver = replica_id.new("R")
    let assert Ok(ab) = or_map.merge_as(a, b, receiver)
    let assert Ok(abc) = or_map.merge(ab, c)
    let assert Ok(bc) = or_map.merge_as(b, c, receiver)
    let assert Ok(other) = or_map.merge(bc, a)
    abc
    |> fn(assertion_actual) {
      let assert True = assertion_actual == other
    }
    fixture.sequence(abc)
    |> sequence.values
    |> fn(assertion_actual) {
      let assert True = assertion_actual == [number + 2]
    }
    let assert Ok(reordered) =
      list.try_fold(
        [dc, db, da, dc, db],
        or_map.bind(baseline, receiver),
        or_map.apply_delta,
      )
    reordered
    |> fn(assertion_actual) {
      let assert True = assertion_actual == abc
    }
    let #(removed, dr) = or_map.remove_with_delta(c, "doc")
    let assert Ok(final) =
      list.try_fold(
        [dr, da, dc, db, dr],
        or_map.bind(baseline, receiver),
        or_map.apply_delta,
      )
    let assert Ok(expected) = or_map.merge_as(removed, ab, receiver)
    final
    |> fn(assertion_actual) {
      let assert True = assertion_actual == expected
    }
    or_map.keys(final)
    |> fn(assertion_actual) {
      let assert True = assertion_actual == []
    }
    Nil
  })
}
