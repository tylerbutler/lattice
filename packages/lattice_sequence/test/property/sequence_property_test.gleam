import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import qcheck
import startest/expect

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
  sequence.new(rid(id))
  |> sequence.insert(0, value)
  |> expect.to_be_ok()
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
        |> expect.to_equal(sequence.merge(right, left, rid("A")))
      })
      Nil
    },
  )
}

pub fn sequence_merge_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let d = doc("A", n)

    sequence.merge(d, d, rid("A")) |> expect.to_equal(d)
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
        |> expect.to_equal(sequence.merge(
          doc_a,
          sequence.merge(doc_b, doc_c, rid("A")),
          rid("A"),
        ))
      })
      Nil
    },
  )
}

pub fn sequence_merge_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let state = doc("A", n)

    sequence.merge(state, sequence.new(rid("A")), rid("A"))
    |> expect.to_equal(state)
    sequence.merge(state, sequence.new(rid("empty")), rid("A"))
    |> expect.to_equal(state)
    sequence.merge(sequence.new(rid("empty")), state, rid("A"))
    |> expect.to_equal(state)
    Nil
  })
}

pub fn sequence_insert_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let base = sequence.new(rid("A"))
    let #(direct, delta) =
      sequence.insert_with_delta(base, 0, n) |> expect.to_be_ok()

    sequence.merge(base, delta, rid("A")) |> expect.to_equal(direct)
    Nil
  })
}

pub fn sequence_delete_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 1), fn(index) {
    let base =
      sequence.new(rid("A"))
      |> sequence.insert(0, int.to_string(1))
      |> expect.to_be_ok()
      |> sequence.insert(1, int.to_string(2))
      |> expect.to_be_ok()
    let #(direct, delta) =
      sequence.delete_with_delta(base, index) |> expect.to_be_ok()

    sequence.merge(base, delta, rid("A")) |> expect.to_equal(direct)
    Nil
  })
}

pub fn sequence_move_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 1), fn(to_index) {
    let base =
      sequence.new(rid("A"))
      |> sequence.insert(0, "a")
      |> expect.to_be_ok()
      |> sequence.insert(1, "b")
      |> expect.to_be_ok()
      |> sequence.insert(2, "c")
      |> expect.to_be_ok()
    let #(direct, delta) =
      sequence.move_with_delta(base, 0, to_index) |> expect.to_be_ok()

    sequence.merge(base, delta, rid("A")) |> expect.to_equal(direct)
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
        |> expect.to_equal(Ok(state))
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
      let base =
        sequence.new(rid("base"))
        |> sequence.insert(0, "a")
        |> expect.to_be_ok()
        |> sequence.insert(1, "b")
        |> expect.to_be_ok()
        |> sequence.insert(2, "c")
        |> expect.to_be_ok()
      list.each([#("A", "B"), #("\u{e000}", "\u{10000}")], fn(ids) {
        let left =
          sequence.merge(sequence.new(rid(ids.0)), base, rid(ids.0))
          |> sequence.move(a, b)
          |> expect.to_be_ok()
        let right =
          sequence.merge(sequence.new(rid(ids.1)), base, rid(ids.1))
          |> sequence.move(b, a)
          |> expect.to_be_ok()

        sequence.merge(left, right, rid("A"))
        |> expect.to_equal(sequence.merge(right, left, rid("A")))
      })
      Nil
    },
  )
}
