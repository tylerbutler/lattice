import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import qcheck

fn rid(id: String) {
  replica_id.new(id)
}

/// Lower than the rest of the workspace because each case builds and merges
/// whole random sequences — the per-case cost is an order of magnitude above
/// the other CRDTs, and the JavaScript target is ~10x slower again.
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 200, max_retries: 3, seed: qcheck.seed(42))
}

fn doc(id: String, value: Int) {
  {
    let assert Ok(asserted_14) =
      sequence.new(rid(id))
      |> sequence.insert(0, value)
    asserted_14
  }
}

pub fn sequence_merge_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      list.each([#("A", "B"), #("\u{e000}", "\u{10000}")], fn(ids) {
        let left = doc(ids.0, a)
        let right = doc(ids.1, b)

        sequence.merge(left, right, rid("A"))
        |> fn(actual) {
          assert actual == { sequence.merge(right, left, rid("A")) }
        }
      })
      Nil
    },
  )
}

pub fn sequence_merge_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let d = doc("A", n)

    sequence.merge(d, d, rid("A"))
    |> fn(actual) {
      assert actual == { d }
    }
    Nil
  })
}

pub fn sequence_merge_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      list.each([#("A", "B"), #("\u{e000}", "\u{10000}")], fn(ids) {
        let doc_a = doc(ids.0, a)
        let doc_b = doc(ids.1, b)
        let doc_c = doc("C", c)

        sequence.merge(sequence.merge(doc_a, doc_b, rid("A")), doc_c, rid("A"))
        |> fn(actual) {
          assert actual
            == {
              sequence.merge(
                doc_a,
                sequence.merge(doc_b, doc_c, rid("A")),
                rid("A"),
              )
            }
        }
      })
      Nil
    },
  )
}

pub fn sequence_merge_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let state = doc("A", n)

    sequence.merge(state, sequence.new(rid("A")), rid("A"))
    |> fn(actual) {
      assert actual == { state }
    }
    sequence.merge(state, sequence.new(rid("empty")), rid("A"))
    |> fn(actual) {
      assert actual == { state }
    }
    sequence.merge(sequence.new(rid("empty")), state, rid("A"))
    |> fn(actual) {
      assert actual == { state }
    }
    Nil
  })
}

pub fn sequence_insert_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let base = sequence.new(rid("A"))
    let #(direct, delta) = {
      let assert Ok(asserted_13) = sequence.insert_with_delta(base, 0, n)
      asserted_13
    }

    sequence.merge(base, delta, rid("A"))
    |> fn(actual) {
      assert actual == { direct }
    }
    Nil
  })
}

pub fn sequence_delete_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 1), fn(index) {
    let base = {
      let assert Ok(asserted_11) =
        {
          let assert Ok(asserted_12) =
            sequence.new(rid("A"))
            |> sequence.insert(0, int.to_string(1))
          asserted_12
        }
        |> sequence.insert(1, int.to_string(2))
      asserted_11
    }
    let #(direct, delta) = {
      let assert Ok(asserted_10) = sequence.delete_with_delta(base, index)
      asserted_10
    }

    sequence.merge(base, delta, rid("A"))
    |> fn(actual) {
      assert actual == { direct }
    }
    Nil
  })
}

pub fn sequence_move_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 1), fn(to_index) {
    let base = {
      let assert Ok(asserted_7) =
        {
          let assert Ok(asserted_8) =
            {
              let assert Ok(asserted_9) =
                sequence.new(rid("A"))
                |> sequence.insert(0, "a")
              asserted_9
            }
            |> sequence.insert(1, "b")
          asserted_8
        }
        |> sequence.insert(2, "c")
      asserted_7
    }
    let #(direct, delta) = {
      let assert Ok(asserted_6) = sequence.move_with_delta(base, 0, to_index)
      asserted_6
    }

    sequence.merge(base, delta, rid("A"))
    |> fn(actual) {
      assert actual == { direct }
    }
    Nil
  })
}

pub fn sequence_snapshot_reconstructs_operation_high_water_mark__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 2), fn(index) {
    let assert Ok(inserted) =
      sequence.insert_many(sequence.new(rid("A")), 0, [1, 2, 3])
    let assert Ok(deleted) = sequence.delete(inserted, index)
    let assert Ok(moved) = sequence.move(deleted, 0, 1)
    let frontier = version_vector.new() |> version_vector.set_max(rid("A"), 5)
    let #(compacted, forwardings) = sequence.compact(moved, frontier)
    let expired = sequence.remove_forwardings(compacted, forwardings)
    list.each(
      [
        #(inserted, 3),
        #(deleted, 4),
        #(moved, 5),
        #(compacted, 5),
        #(expired, 5),
      ],
      fn(pair) {
        let #(state, counter) = pair
        sequence.to_json(state, json.int)
        |> json.to_string()
        |> string.replace(
          "\"self_id\":\"A\",\"counter\":" <> int.to_string(counter),
          "\"self_id\":\"A\",\"counter\":0",
        )
        |> sequence.from_json(decode.int)
        |> fn(actual) {
          assert actual == { Ok(state) }
        }
      },
    )
    Nil
  })
}

pub fn moved_sequence_merge_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 2), qcheck.bounded_int(0, 2), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let base = {
        let assert Ok(asserted_3) =
          {
            let assert Ok(asserted_4) =
              {
                let assert Ok(asserted_5) =
                  sequence.new(rid("base"))
                  |> sequence.insert(0, "a")
                asserted_5
              }
              |> sequence.insert(1, "b")
            asserted_4
          }
          |> sequence.insert(2, "c")
        asserted_3
      }
      list.each([#("A", "B"), #("\u{e000}", "\u{10000}")], fn(ids) {
        let left = {
          let assert Ok(asserted_2) =
            sequence.merge(sequence.new(rid(ids.0)), base, rid(ids.0))
            |> sequence.move(a, b)
          asserted_2
        }
        let right = {
          let assert Ok(asserted_1) =
            sequence.merge(sequence.new(rid(ids.1)), base, rid(ids.1))
            |> sequence.move(b, a)
          asserted_1
        }

        sequence.merge(left, right, rid("A"))
        |> fn(actual) {
          assert actual == { sequence.merge(right, left, rid("A")) }
        }
      })
      Nil
    },
  )
}
