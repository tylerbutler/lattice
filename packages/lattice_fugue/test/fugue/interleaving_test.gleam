import gleam/list
import lattice_core/replica_id
import lattice_fugue/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
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

// Backward non-interleaving (paper Figure 2): two replicas each prepend a run
// of items to a shared (empty) list while offline. After merge, each replica's
// run must stay contiguous — never interspersed item-by-item.
pub fn concurrent_prepend_runs_do_not_interleave_test() {
  let a =
    sequence.new(rid("A"))
    |> insert_run(0, ["a1", "a2", "a3"])
  let b =
    sequence.new(rid("B"))
    |> insert_run(0, ["b1", "b2", "b3"])

  let values = sequence.values(sequence.merge(a, b))

  runs_are_contiguous(values, ["a1", "a2", "a3"], ["b1", "b2", "b3"])
  |> expect.to_equal(True)
}

// Forward non-interleaving (paper Figure 1): two replicas each append a run to
// a shared list concurrently. After merge, the runs must not interleave.
pub fn concurrent_append_runs_do_not_interleave_test() {
  let base =
    sequence.new(rid("S"))
    |> sequence.insert(0, "x")

  // Fork the shared base onto two distinct replicas so their new node IDs
  // don't collide, then each appends its own run concurrently.
  let a = fork(base, "A") |> insert_run(1, ["a1", "a2", "a3"])
  let b = fork(base, "B") |> insert_run(1, ["b1", "b2", "b3"])

  let values = sequence.values(sequence.merge(a, b))

  runs_are_contiguous(values, ["a1", "a2", "a3"], ["b1", "b2", "b3"])
  |> expect.to_equal(True)
}

// Adopt an existing state onto a fresh replica id (a distinct editing identity
// sharing the same causal history).
fn fork(base: sequence.Sequence(a), id: String) -> sequence.Sequence(a) {
  sequence.merge(sequence.new(rid(id)), base)
}

// Merge converges to the same visible sequence regardless of order.
pub fn merge_is_order_independent_test() {
  let a =
    sequence.new(rid("A"))
    |> insert_run(0, ["a1", "a2"])
  let b =
    sequence.new(rid("B"))
    |> insert_run(0, ["b1", "b2"])

  sequence.values(sequence.merge(a, b))
  |> expect.to_equal(sequence.values(sequence.merge(b, a)))
}

fn runs_are_contiguous(
  values: List(String),
  run_a: List(String),
  run_b: List(String),
) -> Bool {
  contiguous(values, run_a) && contiguous(values, run_b)
}

// The elements of `run` occupy consecutive positions within `values`.
fn contiguous(values: List(String), run: List(String)) -> Bool {
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

fn index_of(values: List(String), item: String) -> Int {
  values
  |> list.index_fold(-1, fn(found, value, i) {
    case found == -1 && value == item {
      True -> i
      False -> found
    }
  })
}
