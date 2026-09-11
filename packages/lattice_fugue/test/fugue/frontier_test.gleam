import gleam/result
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_fugue/sequence

fn rid(id: String) {
  replica_id.new(id)
}

pub fn empty_frontier_is_empty_test() {
  sequence.new(rid("A"))
  |> sequence.frontier()
  |> version_vector.is_empty()
  |> fn(actual) {
    assert actual
  }
}

pub fn frontier_tracks_local_inserts_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
    |> result.try(sequence.insert(_, 2, "c"))
  sequence.frontier(seq)
  |> version_vector.get(rid("A"))
  |> fn(actual) {
    assert actual == 3
  }
}

pub fn frontier_merges_across_replicas_test() {
  let assert Ok(seq_a) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
    |> result.try(sequence.insert(_, 2, "c"))
  let assert Ok(seq_b) =
    sequence.new(rid("B"))
    |> sequence.insert(0, "x")
    |> result.try(sequence.insert(_, 1, "y"))
  let frontier =
    sequence.merge(seq_a, seq_b, rid("A"))
    |> sequence.frontier()

  assert version_vector.get(frontier, rid("A")) == 3
  assert version_vector.get(frontier, rid("B")) == 2
}

pub fn frontier_is_monotonic_under_merge_test() {
  let assert Ok(seq_a) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
  let assert Ok(seq_b) =
    sequence.new(rid("B"))
    |> sequence.insert(0, "x")
    |> result.try(sequence.insert(_, 1, "y"))
  let merged = sequence.merge(seq_a, seq_b, rid("A"))

  version_vector.dominates(sequence.frontier(merged), sequence.frontier(seq_a))
  |> fn(actual) {
    assert actual
  }
}
