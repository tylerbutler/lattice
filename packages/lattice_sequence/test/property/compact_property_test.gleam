import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import qcheck

fn rid(id: String) {
  replica_id.new(id)
}

/// Compaction properties guard the convergence rules that are easiest to get
/// wrong, so they run the widest sweep in the workspace. This is not a round
/// number: a change that reordered documents under compaction passed the whole
/// suite at `test_count: 100` and was only caught by raising this. Treat 100 as
/// known-insufficient, and raise this further when touching the interaction
/// between moves and compaction.
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 2000, max_retries: 3, seed: qcheck.seed(11))
}

fn seed_pair_generator() {
  qcheck.map2(
    qcheck.bounded_int(0, 10_000),
    qcheck.bounded_int(0, 10_000),
    fn(a, b) { #(a, b) },
  )
}

fn next_seed(seed: Int) -> Int {
  { seed * 1237 + 12_345 } % 1_000_003
}

/// Deterministically expand a seed into a small random edit history.
fn expand_ops(seed: Int, count: Int) -> List(#(Int, Int)) {
  case count <= 0 {
    True -> []
    False -> {
      let next = next_seed(seed)
      [#(next % 4, { next / 7 } % 19), ..expand_ops(next, count - 1)]
    }
  }
}

/// Like `expand_ops` but never generates move ops (kinds 0-2 only).
fn expand_ops_without_moves(seed: Int, count: Int) -> List(#(Int, Int)) {
  case count <= 0 {
    True -> []
    False -> {
      let next = next_seed(seed)
      [
        #(next % 3, { next / 7 } % 19),
        ..expand_ops_without_moves(next, count - 1)
      ]
    }
  }
}

fn apply_op(
  seq: sequence.Sequence(Int),
  kind: Int,
  pos: Int,
) -> sequence.Sequence(Int) {
  let len = sequence.length(seq)
  case kind {
    2 ->
      case len {
        0 -> {
          let assert Ok(asserted_9) = sequence.insert(seq, 0, pos)
          asserted_9
        }
        _ -> {
          let assert Ok(asserted_8) = sequence.delete(seq, pos % len)
          asserted_8
        }
      }
    3 ->
      case len < 2 {
        True -> {
          let assert Ok(asserted_7) = sequence.insert(seq, 0, pos * 31 + kind)
          asserted_7
        }
        False -> {
          let assert Ok(asserted_6) =
            sequence.move(seq, pos % len, { pos / 3 } % len)
          asserted_6
        }
      }
    _ -> {
      let assert Ok(asserted_5) =
        sequence.insert(seq, pos % { len + 1 }, pos * 31 + kind)
      asserted_5
    }
  }
}

fn apply_ops(
  seq: sequence.Sequence(Int),
  ops: List(#(Int, Int)),
) -> sequence.Sequence(Int) {
  list.fold(ops, seq, fn(s, op) {
    let #(kind, pos) = op
    apply_op(s, kind, pos)
  })
}

/// A two-replica scenario: replica A applies a random history (every op
/// mints exactly one counter, so `A: length(ops)` is a causal cut over it),
/// replica B forks from that state and applies its own random history above
/// the frontier.
fn scenario(seed_a: Int, seed_b: Int) {
  let ops_a = expand_ops(seed_a + 1, 10)
  let ops_b = expand_ops(seed_b + 2, 10)
  let base = apply_ops(sequence.new(rid("A")), ops_a)
  let frontier =
    version_vector.new()
    |> version_vector.set_max(rid("A"), list.length(ops_a))
  let b_state =
    apply_ops(sequence.merge(sequence.new(rid("B")), base, rid("B")), ops_b)
  #(base, b_state, frontier)
}

pub fn compaction_preserves_visible_order__test() {
  qcheck.run(small_test_config(), seed_pair_generator(), fn(seeds) {
    let #(seed_a, seed_b) = seeds
    let #(base, b_state, frontier) = scenario(seed_a, seed_b)
    let merged = sequence.merge(base, b_state, rid("A"))
    let #(compacted, _) = sequence.compact(merged, frontier)

    sequence.values(compacted)
    |> fn(actual) {
      assert actual == { sequence.values(merged) }
    }
    Nil
  })
}

pub fn merge_commutes_with_compaction_for_deltas_above_frontier__test() {
  // The peer history here is move-free: a peer that concurrently MOVES an
  // already-compacted item can make a compacted replica transiently
  // disagree with a never-compacted one about that item's neighborhood
  // (they re-align on the next merge; see
  // moves_above_frontier_still_converge_on_merge__test).
  qcheck.run(small_test_config(), seed_pair_generator(), fn(seeds) {
    let #(seed_a, seed_b) = seeds
    let ops_a = expand_ops(seed_a + 1, 10)
    let base = apply_ops(sequence.new(rid("A")), ops_a)
    let frontier =
      version_vector.new()
      |> version_vector.set_max(rid("A"), list.length(ops_a))
    let b_state =
      apply_ops(
        sequence.merge(sequence.new(rid("B")), base, rid("B")),
        expand_ops_without_moves(seed_b + 2, 10),
      )
    let #(compacted_base, _) = sequence.compact(base, frontier)
    let left = sequence.merge(compacted_base, b_state, rid("A"))
    let #(right, _) =
      sequence.compact(sequence.merge(base, b_state, rid("A")), frontier)

    sequence.values(left)
    |> fn(actual) {
      assert actual == { sequence.values(right) }
    }
    sequence.values(sequence.merge(b_state, compacted_base, rid("A")))
    |> fn(actual) {
      assert actual == { sequence.values(right) }
    }
    Nil
  })
}

pub fn moves_above_frontier_still_converge_on_merge__test() {
  // With moves in the peer history the compacted and never-compacted
  // replicas may transiently order a concurrently moved compacted item
  // differently, but every MERGE direction still converges.
  qcheck.run(small_test_config(), seed_pair_generator(), fn(seeds) {
    let #(seed_a, seed_b) = seeds
    let #(base, b_state, frontier) = scenario(seed_a, seed_b)
    let #(compacted_base, _) = sequence.compact(base, frontier)
    let left = sequence.merge(compacted_base, b_state, rid("A"))
    let swapped = sequence.merge(b_state, compacted_base, rid("A"))

    left
    |> fn(actual) {
      assert actual == { swapped }
    }
    sequence.merge(left, swapped, rid("A"))
    |> fn(actual) {
      assert actual == { left }
    }
    Nil
  })
}

pub fn anchor_resolution_agrees_across_compaction__test() {
  qcheck.run(small_test_config(), seed_pair_generator(), fn(seeds) {
    let #(seed_a, seed_b) = seeds
    let #(base, b_state, frontier) = scenario(seed_a, seed_b)
    let merged = sequence.merge(base, b_state, rid("A"))
    let #(compacted, _) = sequence.compact(merged, frontier)
    let positions = [0, sequence.length(merged) / 2, sequence.length(merged)]

    list.each(positions, fn(position) {
      let assert Ok(before_bias) =
        sequence.anchor_at(merged, position, sequence.Before)
      let assert Ok(after_bias) =
        sequence.anchor_at(merged, position, sequence.After)

      {
        let assert Ok(asserted_4) = sequence.resolve(compacted, before_bias)
        asserted_4
      }
      |> fn(actual) {
        assert actual
          == {
            {
              let assert Ok(asserted_3) = sequence.resolve(merged, before_bias)
              asserted_3
            }
          }
      }
      {
        let assert Ok(asserted_2) = sequence.resolve(compacted, after_bias)
        asserted_2
      }
      |> fn(actual) {
        assert actual
          == {
            {
              let assert Ok(asserted_1) = sequence.resolve(merged, after_bias)
              asserted_1
            }
          }
      }
    })
    Nil
  })
}

pub fn compact_twice_equals_compact_once__test() {
  qcheck.run(small_test_config(), seed_pair_generator(), fn(seeds) {
    let #(seed_a, seed_b) = seeds
    let #(base, b_state, frontier) = scenario(seed_a, seed_b)
    let merged = sequence.merge(base, b_state, rid("A"))
    let #(once, _) = sequence.compact(merged, frontier)
    let #(twice, round) = sequence.compact(once, frontier)

    twice
    |> fn(actual) {
      assert actual == { once }
    }
    sequence.forwarding_size(round)
    |> fn(actual) {
      assert actual == { 0 }
    }
    Nil
  })
}

pub fn compacted_merge_stays_commutative__test() {
  qcheck.run(small_test_config(), seed_pair_generator(), fn(seeds) {
    let #(seed_a, seed_b) = seeds
    let #(base, b_state, frontier) = scenario(seed_a, seed_b)
    let #(compacted, _) = sequence.compact(base, frontier)

    sequence.merge(compacted, b_state, rid("A"))
    |> fn(actual) {
      assert actual == { sequence.merge(b_state, compacted, rid("A")) }
    }
    Nil
  })
}

pub fn concurrent_replicas_converge_across_compaction__test() {
  qcheck.run(small_test_config(), seed_pair_generator(), fn(seeds) {
    let #(seed_a, seed_b) = seeds
    let #(base, b_state, frontier) = scenario(seed_a, seed_b)
    // A third replica edits concurrently with B, both above the frontier.
    let c_state =
      apply_ops(
        sequence.merge(sequence.new(rid("C")), base, rid("C")),
        expand_ops(seed_a + seed_b + 3, 10),
      )
    let #(compacted, _) = sequence.compact(base, frontier)

    let one =
      sequence.merge(
        sequence.merge(compacted, b_state, rid("A")),
        c_state,
        rid("A"),
      )
    let two =
      sequence.merge(
        sequence.merge(c_state, compacted, rid("A")),
        b_state,
        rid("A"),
      )
    let three =
      sequence.merge(
        b_state,
        sequence.merge(c_state, compacted, rid("A")),
        rid("A"),
      )

    two
    |> fn(actual) {
      assert actual == { one }
    }
    three
    |> fn(actual) {
      assert actual == { one }
    }
    Nil
  })
}
