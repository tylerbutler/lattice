import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence

fn rid(id: String) {
  replica_id.new(id)
}

fn frontier_a(counter: Int) {
  version_vector.new() |> version_vector.set_max(rid("A"), counter)
}

fn count_kind(seq: sequence.Sequence(String), kind: String) -> Int {
  let encoded = json.to_string(sequence.to_json(seq, json.string))
  list.length(string.split(encoded, "\"kind\":\"" <> kind <> "\"")) - 1
}

fn abc() {
  {
    let assert Ok(asserted_69) =
      {
        let assert Ok(asserted_70) =
          {
            let assert Ok(asserted_71) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_71
          }
          |> sequence.insert(1, "b")
        asserted_70
      }
      |> sequence.insert(2, "c")
    asserted_69
  }
}

// --- basic passes ---------------------------------------------------------

pub fn compact_empty_sequence_test() {
  let #(compacted, forwardings) =
    sequence.compact(sequence.new(rid("A")), frontier_a(1))

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { [] }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
  sequence.frontier(compacted)
  |> fn(actual) {
    assert actual == { frontier_a(1) }
  }
}

pub fn compact_all_stable_merges_run_into_one_block_test() {
  let #(compacted, forwardings) = sequence.compact(abc(), frontier_a(3))

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["a", "b", "c"] }
  }
  count_kind(compacted, "block")
  |> fn(actual) {
    assert actual == { 1 }
  }
  count_kind(compacted, "item")
  |> fn(actual) {
    assert actual == { 0 }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn compact_all_volatile_keeps_items_test() {
  // A frontier for an unrelated replica advances past the stored frontier
  // without covering any local op: nothing is stable.
  let frontier = version_vector.new() |> version_vector.set_max(rid("Z"), 5)
  let #(compacted, forwardings) = sequence.compact(abc(), frontier)

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["a", "b", "c"] }
  }
  count_kind(compacted, "block")
  |> fn(actual) {
    assert actual == { 0 }
  }
  count_kind(compacted, "item")
  |> fn(actual) {
    assert actual == { 3 }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn compact_drops_stable_tombstone_test() {
  let seq = {
    let assert Ok(asserted_68) = abc() |> sequence.delete(1)
    asserted_68
  }
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(4))

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["a", "c"] }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 1 }
  }
  // a (counter 1) and c (counter 3) are not sequential: two blocks.
  count_kind(compacted, "block")
  |> fn(actual) {
    assert actual == { 2 }
  }
  count_kind(compacted, "item")
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn compact_retains_tombstone_above_frontier_test() {
  let seq = {
    let assert Ok(asserted_65) =
      {
        let assert Ok(asserted_66) =
          {
            let assert Ok(asserted_67) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_67
          }
          |> sequence.insert(1, "b")
        asserted_66
      }
      |> sequence.delete(0)
    asserted_65
  }
  // Frontier covers both inserts but not the delete op (counter 3): the
  // delete may still be unacknowledged, so the tombstone must survive.
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(2))

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["b"] }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
  count_kind(compacted, "item")
  |> fn(actual) {
    assert actual == { 1 }
  }
  count_kind(compacted, "block")
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn compact_does_not_merge_blocks_across_replicas_test() {
  let a_state = {
    let assert Ok(asserted_64) =
      sequence.new(rid("A")) |> sequence.insert(0, "a")
    asserted_64
  }
  let b_state = {
    let assert Ok(asserted_63) =
      sequence.merge(sequence.new(rid("B")), a_state, rid("B"))
      |> sequence.insert(1, "b")
    asserted_63
  }
  let merged = sequence.merge(a_state, b_state, rid("A"))
  // B's counter continues from the merged maximum, so its insert is B:2.
  let frontier =
    version_vector.new()
    |> version_vector.set_max(rid("A"), 1)
    |> version_vector.set_max(rid("B"), 2)
  let #(compacted, _forwardings) = sequence.compact(merged, frontier)

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["a", "b"] }
  }
  count_kind(compacted, "block")
  |> fn(actual) {
    assert actual == { 2 }
  }
}

pub fn compact_does_not_merge_blocks_across_counter_gaps_test() {
  let seq = {
    let assert Ok(asserted_59) =
      {
        let assert Ok(asserted_60) =
          {
            let assert Ok(asserted_61) =
              {
                let assert Ok(asserted_62) =
                  sequence.new(rid("A"))
                  |> sequence.insert(0, "a")
                asserted_62
              }
              |> sequence.insert(1, "b")
            asserted_61
          }
          |> sequence.delete(1)
        asserted_60
      }
      |> sequence.insert(1, "c")
    asserted_59
  }
  // Elements: a (1), dropped tombstone b (2), c (4) — the counter gap
  // between 1 and 4 must keep a and c in separate blocks.
  let #(compacted, _forwardings) = sequence.compact(seq, frontier_a(4))

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["a", "c"] }
  }
  count_kind(compacted, "block")
  |> fn(actual) {
    assert actual == { 2 }
  }
}

pub fn compact_reclaims_alongside_a_moved_item_test() {
  // Regression for #98: `compact` used to bail on ANY move record, and
  // nothing ever cleared one, so a replica that performed or received a
  // single move could never reclaim anything again. Moves are now an overlay
  // on the stored base rather than baked into it, so the pass runs normally.
  let seq = {
    let assert Ok(asserted_58) = abc() |> sequence.move(0, 2)
    asserted_58
  }
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(4))

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["b", "c", "a"] }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
  // "a" stays live as the mover and "c" as the move's target anchor; only
  // "b" is free to stabilize.
  count_kind(compacted, "block")
  |> fn(actual) {
    assert actual == { 1 }
  }
  count_kind(compacted, "item")
  |> fn(actual) {
    assert actual == { 2 }
  }
}

pub fn compact_reclaims_tombstones_with_a_move_live_test() {
  let seq = {
    let assert Ok(asserted_52) =
      {
        let assert Ok(asserted_53) =
          {
            let assert Ok(asserted_54) =
              {
                let assert Ok(asserted_55) =
                  {
                    let assert Ok(asserted_56) =
                      {
                        let assert Ok(asserted_57) =
                          sequence.new(rid("A"))
                          |> sequence.insert(0, "a")
                        asserted_57
                      }
                      |> sequence.insert(1, "b")
                    asserted_56
                  }
                  |> sequence.insert(2, "c")
                asserted_55
              }
              |> sequence.insert(3, "d")
            asserted_54
          }
          // tombstones "b" with op counter 5
          |> sequence.delete(1)
        asserted_53
      }
      // moves "a" after "d" with op counter 6
      |> sequence.move(0, 2)
    asserted_52
  }
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(6))

  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["c", "d", "a"] }
  }
  // The stable tombstone is reclaimed even though a move record is live.
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn compact_preserves_co_gap_move_order_across_a_tombstone_test() {
  // "c" falls back to AfterGap("L") when "e" is moved, while "b" still
  // resolves BeforeElement("R"). The unrelated tombstone between L and R
  // must neither split that visible gap nor change its mover order when it is
  // reclaimed.
  let base = {
    let assert Ok(asserted_45) =
      {
        let assert Ok(asserted_46) =
          {
            let assert Ok(asserted_47) =
              {
                let assert Ok(asserted_48) =
                  {
                    let assert Ok(asserted_49) =
                      {
                        let assert Ok(asserted_50) =
                          {
                            let assert Ok(asserted_51) =
                              sequence.new(rid("Z"))
                              |> sequence.insert(0, "L")
                            asserted_51
                          }
                          |> sequence.insert(1, "tombstone")
                        asserted_50
                      }
                      |> sequence.insert(2, "e")
                    asserted_49
                  }
                  |> sequence.insert(3, "R")
                asserted_48
              }
              |> sequence.insert(4, "c")
            asserted_47
          }
          |> sequence.insert(5, "b")
        asserted_46
      }
      |> sequence.delete(1)
    asserted_45
  }
  let a = {
    let assert Ok(asserted_44) =
      sequence.merge(sequence.new(rid("A")), base, rid("A"))
      |> sequence.move(3, 1)
    asserted_44
  }
  let b = {
    let assert Ok(asserted_43) =
      sequence.merge(sequence.new(rid("B")), base, rid("B"))
      |> sequence.move(4, 2)
    asserted_43
  }
  let merged = {
    let assert Ok(asserted_42) =
      sequence.merge(a, b, rid("A"))
      // Moving "e" strips the shared boundary during move resolution.
      |> sequence.move(2, 4)
    asserted_42
  }
  let frontier = version_vector.new() |> version_vector.set_max(rid("Z"), 7)
  let #(compacted, forwardings) = sequence.compact(merged, frontier)

  sequence.values(merged)
  |> fn(actual) {
    assert actual == { ["L", "c", "b", "R", "e"] }
  }
  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { sequence.values(merged) }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn compact_retains_a_live_moves_target_anchors_test() {
  // A move splices at an exact position, so reclaiming one of its target-gap
  // boundaries would leave a compacted replica and an uncompacted one
  // splicing the mover differently. Anchors are retained until the move is.
  let seq = {
    let assert Ok(asserted_37) =
      {
        let assert Ok(asserted_38) =
          {
            let assert Ok(asserted_39) =
              {
                let assert Ok(asserted_40) =
                  {
                    let assert Ok(asserted_41) =
                      sequence.new(rid("A"))
                      |> sequence.insert(0, "a")
                    asserted_41
                  }
                  |> sequence.insert(1, "b")
                asserted_40
              }
              |> sequence.insert(2, "c")
            asserted_39
          }
          // "b" becomes the move's right anchor, then is tombstoned
          |> sequence.move(2, 1)
        asserted_38
      }
      |> sequence.delete(2)
    asserted_37
  }
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(5))

  // The tombstoned anchor is NOT reclaimed while the move is live.
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { sequence.values(seq) }
  }
}

// --- idempotence and frontier regression ----------------------------------

pub fn compact_at_same_frontier_is_noop_test() {
  let seq = {
    let assert Ok(asserted_36) = abc() |> sequence.delete(1)
    asserted_36
  }
  let #(once, _) = sequence.compact(seq, frontier_a(4))
  let #(twice, forwardings) = sequence.compact(once, frontier_a(4))

  twice
  |> fn(actual) {
    assert actual == { once }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn compact_at_older_frontier_is_noop_test() {
  let seq = {
    let assert Ok(asserted_35) = abc() |> sequence.delete(1)
    asserted_35
  }
  let #(once, _) = sequence.compact(seq, frontier_a(4))
  let #(regressed, forwardings) = sequence.compact(once, frontier_a(2))

  regressed
  |> fn(actual) {
    assert actual == { once }
  }
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 0 }
  }
}

// --- editing compacted state ----------------------------------------------

pub fn insert_into_middle_of_block_splits_it_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let updated = {
    let assert Ok(asserted_34) = sequence.insert(compacted, 1, "x")
    asserted_34
  }

  sequence.values(updated)
  |> fn(actual) {
    assert actual == { ["a", "x", "b", "c"] }
  }
  count_kind(updated, "block")
  |> fn(actual) {
    assert actual == { 2 }
  }
  count_kind(updated, "item")
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn delete_inside_block_extracts_tombstone_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let updated = {
    let assert Ok(asserted_33) = sequence.delete(compacted, 1)
    asserted_33
  }

  sequence.values(updated)
  |> fn(actual) {
    assert actual == { ["a", "c"] }
  }
  count_kind(updated, "item")
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn delete_inside_block_converges_across_replicas_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let b_state = sequence.merge(sequence.new(rid("B")), compacted, rid("B"))
  let a_edit = {
    let assert Ok(asserted_32) = sequence.delete(compacted, 1)
    asserted_32
  }
  let b_edit = {
    let assert Ok(asserted_31) = sequence.insert(b_state, 3, "d")
    asserted_31
  }

  sequence.values(sequence.merge(a_edit, b_edit, rid("A")))
  |> fn(actual) {
    assert actual == { ["a", "c", "d"] }
  }
  sequence.values(sequence.merge(b_edit, a_edit, rid("A")))
  |> fn(actual) {
    assert actual == { ["a", "c", "d"] }
  }
}

pub fn move_out_of_block_converges_across_replicas_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let b_state = sequence.merge(sequence.new(rid("B")), compacted, rid("B"))
  let a_edit = {
    let assert Ok(asserted_30) = sequence.move(compacted, 0, 2)
    asserted_30
  }

  sequence.values(a_edit)
  |> fn(actual) {
    assert actual == { ["b", "c", "a"] }
  }
  sequence.values(sequence.merge(a_edit, b_state, rid("A")))
  |> fn(actual) {
    assert actual == { ["b", "c", "a"] }
  }
  sequence.values(sequence.merge(b_state, a_edit, rid("A")))
  |> fn(actual) {
    assert actual == { ["b", "c", "a"] }
  }
}

// --- merging compacted and uncompacted states ------------------------------

pub fn merge_with_uncompacted_peer_converges_test() {
  let base = abc()
  let b_state = {
    let assert Ok(asserted_29) =
      sequence.merge(sequence.new(rid("B")), base, rid("B"))
      |> sequence.insert(1, "x")
    asserted_29
  }
  let #(compacted, _) = sequence.compact(base, frontier_a(3))

  sequence.values(sequence.merge(compacted, b_state, rid("A")))
  |> fn(actual) {
    assert actual == { ["a", "x", "b", "c"] }
  }
  sequence.values(sequence.merge(b_state, compacted, rid("A")))
  |> fn(actual) {
    assert actual == { ["a", "x", "b", "c"] }
  }
}

pub fn merge_does_not_resurrect_compacted_tombstone_test() {
  let base = {
    let assert Ok(asserted_27) =
      {
        let assert Ok(asserted_28) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_28
      }
      |> sequence.insert(1, "b")
    asserted_27
  }
  let b_state = sequence.merge(sequence.new(rid("B")), base, rid("B"))
  let deleted = {
    let assert Ok(asserted_26) = sequence.delete(base, 0)
    asserted_26
  }
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  sequence.values(sequence.merge(compacted, b_state, rid("A")))
  |> fn(actual) {
    assert actual == { ["b"] }
  }
  sequence.values(sequence.merge(b_state, compacted, rid("A")))
  |> fn(actual) {
    assert actual == { ["b"] }
  }
}

// --- anchors ---------------------------------------------------------------

pub fn anchor_resolves_through_forwarding_after_compaction_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_25) = sequence.anchor_at(seq, 1, sequence.Before)
    asserted_25
  }
  let deleted = {
    let assert Ok(asserted_24) = sequence.delete(seq, 1)
    asserted_24
  }
  let #(compacted, round) = sequence.compact(deleted, frontier_a(4))

  sequence.resolve(deleted, anchor)
  |> fn(actual) {
    assert actual == { Ok(1) }
  }
  sequence.resolve(compacted, anchor)
  |> fn(actual) {
    assert actual == { Ok(1) }
  }

  let expired = sequence.remove_forwardings(compacted, round)
  sequence.resolve(expired, anchor)
  |> fn(actual) {
    assert actual == { Error(sequence.UnknownAnchorTarget) }
  }
}

pub fn forwarding_at_document_start_resolves_to_zero_test() {
  let seq = {
    let assert Ok(asserted_22) =
      {
        let assert Ok(asserted_23) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_23
      }
      |> sequence.insert(1, "b")
    asserted_22
  }
  let anchor = {
    let assert Ok(asserted_21) = sequence.anchor_at(seq, 0, sequence.Before)
    asserted_21
  }
  let deleted = {
    let assert Ok(asserted_20) = sequence.delete(seq, 0)
    asserted_20
  }
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  sequence.resolve(compacted, anchor)
  |> fn(actual) {
    assert actual == { Ok(0) }
  }
}

pub fn anchor_on_visible_item_survives_compaction_test() {
  let seq = {
    let assert Ok(asserted_19) = abc() |> sequence.delete(0)
    asserted_19
  }
  let anchor = {
    let assert Ok(asserted_18) = sequence.anchor_at(seq, 1, sequence.After)
    asserted_18
  }
  let #(compacted, _) = sequence.compact(seq, frontier_a(4))

  {
    let assert Ok(asserted_17) = sequence.resolve(compacted, anchor)
    asserted_17
  }
  |> fn(actual) {
    assert actual
      == {
        {
          let assert Ok(asserted_16) = sequence.resolve(seq, anchor)
          asserted_16
        }
      }
  }
}

// --- rebase / origin translation --------------------------------------------

pub fn translate_origins_rebases_dropped_left_origin_test() {
  let base = {
    let assert Ok(asserted_14) =
      {
        let assert Ok(asserted_15) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_15
      }
      |> sequence.insert(1, "b")
    asserted_14
  }
  let c_state = sequence.merge(sequence.new(rid("C")), base, rid("C"))
  let #(_, delta) = {
    let assert Ok(asserted_13) = sequence.insert_with_delta(c_state, 1, "x")
    asserted_13
  }
  let deleted = {
    let assert Ok(asserted_12) = sequence.delete(base, 0)
    asserted_12
  }
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  let assert Ok(translated) = sequence.translate_origins(delta, compacted)
  sequence.values(sequence.merge(compacted, translated, rid("A")))
  |> fn(actual) {
    assert actual == { ["x", "b"] }
  }
}

pub fn translate_origins_lands_at_same_visible_position_test() {
  let base = {
    let assert Ok(asserted_10) =
      {
        let assert Ok(asserted_11) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_11
      }
      |> sequence.insert(1, "b")
    asserted_10
  }
  // C appends after b, so the delta's left origin is b's ID.
  let c_state = sequence.merge(sequence.new(rid("C")), base, rid("C"))
  let #(_, delta) = {
    let assert Ok(asserted_9) = sequence.insert_with_delta(c_state, 2, "x")
    asserted_9
  }

  let deleted = {
    let assert Ok(asserted_8) = sequence.delete(base, 1)
    asserted_8
  }
  let uncompacted = sequence.merge(deleted, delta, rid("A"))
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))
  let assert Ok(translated) = sequence.translate_origins(delta, compacted)

  sequence.values(sequence.merge(compacted, translated, rid("A")))
  |> fn(actual) {
    assert actual == { sequence.values(uncompacted) }
  }
}

pub fn translate_origins_expired_forwarding_fails_test() {
  let base = {
    let assert Ok(asserted_6) =
      {
        let assert Ok(asserted_7) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_7
      }
      |> sequence.insert(1, "b")
    asserted_6
  }
  let c_state = sequence.merge(sequence.new(rid("C")), base, rid("C"))
  let #(_, delta) = {
    let assert Ok(asserted_5) = sequence.insert_with_delta(c_state, 1, "x")
    asserted_5
  }
  let deleted = {
    let assert Ok(asserted_4) = sequence.delete(base, 0)
    asserted_4
  }
  let #(compacted, round) = sequence.compact(deleted, frontier_a(3))
  let expired = sequence.remove_forwardings(compacted, round)

  sequence.translate_origins(delta, expired)
  |> fn(actual) {
    assert actual == { Error(sequence.UnknownOriginTarget) }
  }
}

pub fn translate_origins_drops_already_compacted_items_test() {
  let base = {
    let assert Ok(asserted_2) =
      {
        let assert Ok(asserted_3) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_3
      }
      |> sequence.insert(1, "b")
    asserted_2
  }
  let #(deleted, delete_delta) = {
    let assert Ok(asserted_1) = sequence.delete_with_delta(base, 0)
    asserted_1
  }
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  let assert Ok(translated) =
    sequence.translate_origins(delete_delta, compacted)
  sequence.length(translated)
  |> fn(actual) {
    assert actual == { 0 }
  }
  sequence.values(sequence.merge(compacted, translated, rid("A")))
  |> fn(actual) {
    assert actual == { ["b"] }
  }
}
