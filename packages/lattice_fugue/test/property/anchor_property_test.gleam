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

fn doc_of_length(n: Int) -> sequence.Sequence(Int) {
  list.repeat(0, n)
  |> list.index_fold(sequence.new(rid("A")), fn(acc, _v, i) {
    sequence.insert(acc, i, i)
  })
}

// An anchor with `After` bias, bound to the item before a gap, must not move
// when we insert new items strictly after that gap: those inserts land past
// the anchor, so its resolved index is unchanged.
pub fn after_anchor_stable_under_later_inserts__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 8), fn(n) {
    let seq = doc_of_length(n)
    let gap = 1
    let anchor = sequence.anchor_at(seq, gap, sequence.After)
    let before = sequence.resolve(seq, anchor)

    // Insert at the very end, strictly after the anchor gap.
    let updated = sequence.insert(seq, sequence.length(seq), 99)
    sequence.resolve(updated, anchor)
    |> expect.to_equal(before)
    Nil
  })
}

// An anchor with `Before` bias, bound to the item at a gap, shifts right by
// exactly the number of items inserted strictly before that gap.
pub fn before_anchor_shifts_by_earlier_inserts__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(2, 8), fn(n) {
    let seq = doc_of_length(n)
    let gap = 2
    let anchor = sequence.anchor_at(seq, gap, sequence.Before)
    let before = sequence.resolve(seq, anchor)

    // Insert two items at the front, strictly before the anchor gap.
    let updated =
      seq
      |> sequence.insert(0, 100)
      |> sequence.insert(0, 101)
    sequence.resolve(updated, anchor)
    |> expect.to_equal(before + 2)
    Nil
  })
}

// Anchor resolution is invariant to merge order: resolving the same anchor
// against a merge and its reverse yields the same index.
pub fn anchor_resolution_merge_order_invariant__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(1, 6), fn(n) {
    let seq_a = doc_of_length(n)
    let anchor = sequence.anchor_at(seq_a, 1, sequence.After)

    let seq_b =
      sequence.new(rid("B"))
      |> sequence.insert(0, 500)
      |> sequence.insert(1, 501)

    let forward = sequence.merge(seq_a, seq_b)
    let backward = sequence.merge(seq_b, seq_a)
    sequence.resolve(forward, anchor)
    |> expect.to_equal(sequence.resolve(backward, anchor))
    Nil
  })
}
