import gleam/int
import lattice_core/replica_id
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
      let left = doc("A", a)
      let right = doc("B", b)

      sequence.values(sequence.merge(left, right))
      |> expect.to_equal(sequence.values(sequence.merge(right, left)))
      Nil
    },
  )
}

pub fn sequence_merge_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let d = doc("A", n)

    sequence.merge(d, d) |> expect.to_equal(d)
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
      let doc_a = doc("A", a)
      let doc_b = doc("B", b)
      let doc_c = doc("C", c)

      sequence.values(sequence.merge(sequence.merge(doc_a, doc_b), doc_c))
      |> expect.to_equal(
        sequence.values(sequence.merge(doc_a, sequence.merge(doc_b, doc_c))),
      )
      Nil
    },
  )
}

pub fn sequence_merge_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let state = doc("A", n)

    sequence.merge(state, sequence.new(rid("A"))) |> expect.to_equal(state)
    sequence.values(sequence.merge(state, sequence.new(rid("empty"))))
    |> expect.to_equal(sequence.values(state))
    sequence.values(sequence.merge(sequence.new(rid("empty")), state))
    |> expect.to_equal(sequence.values(state))
    Nil
  })
}

pub fn sequence_insert_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let base = sequence.new(rid("A"))
    let #(direct, delta) = sequence.insert_with_delta(base, 0, n)

    sequence.merge(base, delta) |> expect.to_equal(direct)
    Nil
  })
}

pub fn sequence_delete_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 1), fn(index) {
    let base =
      sequence.new(rid("A"))
      |> sequence.insert(0, int.to_string(1))
      |> sequence.insert(1, int.to_string(2))
    let #(direct, delta) = sequence.delete_with_delta(base, index)

    sequence.merge(base, delta) |> expect.to_equal(direct)
    Nil
  })
}

pub fn sequence_move_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 1), fn(to_index) {
    let base =
      sequence.new(rid("A"))
      |> sequence.insert(0, "a")
      |> sequence.insert(1, "b")
      |> sequence.insert(2, "c")
    let #(direct, delta) = sequence.move_with_delta(base, 0, to_index)

    sequence.merge(base, delta) |> expect.to_equal(direct)
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
        |> sequence.insert(1, "b")
        |> sequence.insert(2, "c")
      let left =
        sequence.merge(sequence.new(rid("A")), base)
        |> sequence.move(a, b)
      let right =
        sequence.merge(sequence.new(rid("B")), base)
        |> sequence.move(b, a)

      sequence.values(sequence.merge(left, right))
      |> expect.to_equal(sequence.values(sequence.merge(right, left)))
      Nil
    },
  )
}
