import gleam/int
import lattice_core/replica_id
import lattice_text/text
import qcheck
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

/// The workspace default. These ran at 10 cases, which is not enough sweep to
/// exercise the convergence laws they assert.
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 1000, max_retries: 3, seed: qcheck.seed(42))
}

fn doc(id: String, value: String) {
  text.new(rid(id))
  |> text.insert(0, value)
  |> expect.to_be_ok()
}

pub fn text_merge_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let left = doc("A", int.to_string(a))
      let right = doc("B", int.to_string(b))

      text.merge(left, right, rid("A"))
      |> expect.to_equal(text.merge(right, left, rid("A")))
      Nil
    },
  )
}

pub fn text_merge_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let d = doc("A", int.to_string(n))

    text.merge(d, d, rid("A")) |> expect.to_equal(d)
    Nil
  })
}

pub fn text_merge_associativity__test() {
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
      let doc_a = doc("A", int.to_string(a))
      let doc_b = doc("B", int.to_string(b))
      let doc_c = doc("C", int.to_string(c))

      text.merge(text.merge(doc_a, doc_b, rid("A")), doc_c, rid("A"))
      |> expect.to_equal(text.merge(
        doc_a,
        text.merge(doc_b, doc_c, rid("A")),
        rid("A"),
      ))
      Nil
    },
  )
}

pub fn text_merge_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let state = doc("A", int.to_string(n))

    text.merge(state, text.new(rid("A")), rid("A")) |> expect.to_equal(state)
    text.merge(state, text.new(rid("empty")), rid("A"))
    |> expect.to_equal(state)
    text.merge(text.new(rid("empty")), state, rid("A"))
    |> expect.to_equal(state)
    Nil
  })
}

pub fn text_insert_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let base = text.new(rid("A"))
    let #(direct, delta) =
      text.insert_with_delta(base, 0, int.to_string(n)) |> expect.to_be_ok()

    text.merge(base, delta, rid("A")) |> expect.to_equal(direct)
    Nil
  })
}

pub fn text_delete_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 1), fn(index) {
    let base =
      text.new(rid("A"))
      |> text.insert(0, "a")
      |> expect.to_be_ok()
      |> text.insert(1, "b")
      |> expect.to_be_ok()
    let #(direct, delta) =
      text.delete_with_delta(base, index) |> expect.to_be_ok()

    text.merge(base, delta, rid("A")) |> expect.to_equal(direct)
    Nil
  })
}

pub fn text_delete_range_delta_correctness__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 4), qcheck.bounded_int(0, 4), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let start = int.min(a, b)
      let end = int.max(a, b)
      let base =
        text.new(rid("A")) |> text.insert(0, "abcd") |> expect.to_be_ok()
      let #(direct, delta) =
        text.delete_range_with_delta(base, start, end) |> expect.to_be_ok()

      text.merge(base, delta, rid("A")) |> expect.to_equal(direct)
      Nil
    },
  )
}

pub fn text_replace_range_delta_correctness__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 4),
      qcheck.bounded_int(0, 4),
      qcheck.bounded_int(0, 100),
      fn(a, b, n) { #(a, b, n) },
    ),
    fn(triple) {
      let #(a, b, n) = triple
      let start = int.min(a, b)
      let end = int.max(a, b)
      let base =
        text.new(rid("A")) |> text.insert(0, "abcd") |> expect.to_be_ok()
      let #(direct, delta) =
        text.replace_range_with_delta(base, start, end, int.to_string(n))
        |> expect.to_be_ok()

      text.merge(base, delta, rid("A")) |> expect.to_equal(direct)
      Nil
    },
  )
}

pub fn text_move_delta_correctness__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 3),
      qcheck.bounded_int(0, 3),
      fn(from_index, to_index) { #(from_index, to_index) },
    ),
    fn(pair) {
      let #(from_index, to_index) = pair
      let base =
        text.new(rid("A")) |> text.insert(0, "abcd") |> expect.to_be_ok()
      let #(direct, delta) =
        text.move_with_delta(base, from_index, to_index) |> expect.to_be_ok()

      text.merge(base, delta, rid("A")) |> expect.to_equal(direct)
      Nil
    },
  )
}
