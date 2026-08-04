import gleam/list
import lattice_core/replica_id
import lattice_fugue/sequence
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

fn doc(id: String, value: Int) {
  sequence.new(rid(id))
  |> sequence.insert(0, value)
}

fn insert_run(
  seq: sequence.Sequence(a),
  start: Int,
  values: List(a),
) -> sequence.Sequence(a) {
  values
  |> list.index_fold(seq, fn(acc, value, offset) {
    sequence.insert(acc, start + offset, value)
  })
}

pub fn merge_commutativity__test() {
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

pub fn merge_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let d = doc("A", n)
    sequence.merge(d, d) |> expect.to_equal(d)
    Nil
  })
}

pub fn merge_associativity__test() {
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

pub fn merge_bottom_identity__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let state = doc("A", n)
    let empty = sequence.new(rid("A"))

    sequence.values(sequence.merge(state, empty))
    |> expect.to_equal(sequence.values(state))
    Nil
  })
}

// Convergence: two replicas that received the same op set converge to the same
// visible sequence regardless of merge order.
pub fn merge_convergence__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let da = doc("A", a) |> sequence.insert(1, a + 1)
      let db = doc("B", b) |> sequence.insert(1, b + 1)

      let left = sequence.merge(da, db)
      let right = sequence.merge(db, da)

      sequence.values(left)
      |> expect.to_equal(sequence.values(right))
      Nil
    },
  )
}

// Forward non-interleaving (Definition 2): two disjoint runs inserted
// concurrently at the same position never interleave in the merged result.
pub fn non_interleaving__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let run_a = [n, n + 1, n + 2]
    let run_b = [n + 1000, n + 1001, n + 1002]

    let a = sequence.new(rid("A")) |> insert_run(0, run_a)
    let b = sequence.new(rid("B")) |> insert_run(0, run_b)

    let values = sequence.values(sequence.merge(a, b))

    // Every element of run A is entirely before or entirely after every
    // element of run B: equivalently, each run occupies a contiguous block.
    let contiguous_a = contiguous(values, run_a)
    let contiguous_b = contiguous(values, run_b)
    expect.to_equal(contiguous_a && contiguous_b, True)
    Nil
  })
}

fn contiguous(values: List(Int), run: List(Int)) -> Bool {
  let positions = list.map(run, fn(item) { index_of(values, item) })
  case positions {
    [] -> True
    [first, ..rest] -> consecutive(first, rest)
  }
}

fn consecutive(prev: Int, rest: List(Int)) -> Bool {
  case rest {
    [] -> True
    [next, ..tail] ->
      case next == prev + 1 {
        True -> consecutive(next, tail)
        False -> False
      }
  }
}

fn index_of(values: List(Int), item: Int) -> Int {
  values
  |> list.index_fold(-1, fn(found, value, i) {
    case found == -1 && value == item {
      True -> i
      False -> found
    }
  })
}
