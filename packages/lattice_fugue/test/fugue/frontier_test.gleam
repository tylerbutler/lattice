import lattice_core/replica_id
import lattice_core/version_vector
import lattice_fugue/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn empty_frontier_is_empty_test() {
  sequence.new(rid("A"))
  |> sequence.frontier()
  |> version_vector.is_empty()
  |> expect.to_be_true()
}

pub fn frontier_tracks_local_inserts_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  sequence.frontier(seq)
  |> version_vector.get(rid("A"))
  |> expect.to_equal(3)
}

pub fn frontier_merges_across_replicas_test() {
  let seq_a =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
  let seq_b =
    sequence.new(rid("B"))
    |> sequence.insert(0, "x")
    |> sequence.insert(1, "y")
  let frontier =
    sequence.merge(seq_a, seq_b)
    |> sequence.frontier()

  expect.to_equal(version_vector.get(frontier, rid("A")), 3)
  expect.to_equal(version_vector.get(frontier, rid("B")), 2)
}

pub fn frontier_is_monotonic_under_merge_test() {
  let seq_a =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
  let seq_b =
    sequence.new(rid("B"))
    |> sequence.insert(0, "x")
    |> sequence.insert(1, "y")
  let merged = sequence.merge(seq_a, seq_b)

  version_vector.dominates(sequence.frontier(merged), sequence.frontier(seq_a))
  |> expect.to_be_true()
}
