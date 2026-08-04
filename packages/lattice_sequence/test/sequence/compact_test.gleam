import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import startest/expect

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
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> sequence.insert(1, "b")
  |> sequence.insert(2, "c")
}

// --- basic passes ---------------------------------------------------------

pub fn compact_empty_sequence_test() {
  let #(compacted, forwardings) =
    sequence.compact(sequence.new(rid("A")), frontier_a(1))

  sequence.values(compacted) |> expect.to_equal([])
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
  sequence.frontier(compacted) |> expect.to_equal(frontier_a(1))
}

pub fn compact_all_stable_merges_run_into_one_block_test() {
  let #(compacted, forwardings) = sequence.compact(abc(), frontier_a(3))

  sequence.values(compacted) |> expect.to_equal(["a", "b", "c"])
  count_kind(compacted, "block") |> expect.to_equal(1)
  count_kind(compacted, "item") |> expect.to_equal(0)
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
}

pub fn compact_all_volatile_keeps_items_test() {
  // A frontier for an unrelated replica advances past the stored frontier
  // without covering any local op: nothing is stable.
  let frontier = version_vector.new() |> version_vector.set_max(rid("Z"), 5)
  let #(compacted, forwardings) = sequence.compact(abc(), frontier)

  sequence.values(compacted) |> expect.to_equal(["a", "b", "c"])
  count_kind(compacted, "block") |> expect.to_equal(0)
  count_kind(compacted, "item") |> expect.to_equal(3)
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
}

pub fn compact_drops_stable_tombstone_test() {
  let seq = abc() |> sequence.delete(1)
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(4))

  sequence.values(compacted) |> expect.to_equal(["a", "c"])
  sequence.forwarding_size(forwardings) |> expect.to_equal(1)
  // a (counter 1) and c (counter 3) are not sequential: two blocks.
  count_kind(compacted, "block") |> expect.to_equal(2)
  count_kind(compacted, "item") |> expect.to_equal(0)
}

pub fn compact_retains_tombstone_above_frontier_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.delete(0)
  // Frontier covers both inserts but not the delete op (counter 3): the
  // delete may still be unacknowledged, so the tombstone must survive.
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(2))

  sequence.values(compacted) |> expect.to_equal(["b"])
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
  count_kind(compacted, "item") |> expect.to_equal(1)
  count_kind(compacted, "block") |> expect.to_equal(1)
}

pub fn compact_does_not_merge_blocks_across_replicas_test() {
  let a_state = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let b_state =
    sequence.merge(sequence.new(rid("B")), a_state)
    |> sequence.insert(1, "b")
  let merged = sequence.merge(a_state, b_state)
  // B's counter continues from the merged maximum, so its insert is B:2.
  let frontier =
    version_vector.new()
    |> version_vector.set_max(rid("A"), 1)
    |> version_vector.set_max(rid("B"), 2)
  let #(compacted, _forwardings) = sequence.compact(merged, frontier)

  sequence.values(compacted) |> expect.to_equal(["a", "b"])
  count_kind(compacted, "block") |> expect.to_equal(2)
}

pub fn compact_does_not_merge_blocks_across_counter_gaps_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.delete(1)
    |> sequence.insert(1, "c")
  // Elements: a (1), dropped tombstone b (2), c (4) — the counter gap
  // between 1 and 4 must keep a and c in separate blocks.
  let #(compacted, _forwardings) = sequence.compact(seq, frontier_a(4))

  sequence.values(compacted) |> expect.to_equal(["a", "c"])
  count_kind(compacted, "block") |> expect.to_equal(2)
}

pub fn compact_reclaims_alongside_a_moved_item_test() {
  // Regression for #98: `compact` used to bail on ANY move record, and
  // nothing ever cleared one, so a replica that performed or received a
  // single move could never reclaim anything again. Moves are now an overlay
  // on the stored base rather than baked into it, so the pass runs normally.
  let seq = abc() |> sequence.move(0, 2)
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(4))

  sequence.values(compacted) |> expect.to_equal(["b", "c", "a"])
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
  // "a" stays live as the mover and "c" as the move's target anchor; only
  // "b" is free to stabilize.
  count_kind(compacted, "block") |> expect.to_equal(1)
  count_kind(compacted, "item") |> expect.to_equal(2)
}

pub fn compact_reclaims_tombstones_with_a_move_live_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
    |> sequence.insert(3, "d")
    // tombstones "b" with op counter 5
    |> sequence.delete(1)
    // moves "a" after "d" with op counter 6
    |> sequence.move(0, 2)
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(6))

  sequence.values(compacted) |> expect.to_equal(["c", "d", "a"])
  // The stable tombstone is reclaimed even though a move record is live.
  sequence.forwarding_size(forwardings) |> expect.to_equal(1)
}

pub fn compact_retains_a_live_moves_target_anchors_test() {
  // A move splices at an exact position, so reclaiming one of its target-gap
  // boundaries would leave a compacted replica and an uncompacted one
  // splicing the mover differently. Anchors are retained until the move is.
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
    |> sequence.insert(2, "c")
    // "b" becomes the move's right anchor, then is tombstoned
    |> sequence.move(2, 1)
    |> sequence.delete(2)
  let #(compacted, forwardings) = sequence.compact(seq, frontier_a(5))

  // The tombstoned anchor is NOT reclaimed while the move is live.
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
  sequence.values(compacted) |> expect.to_equal(sequence.values(seq))
}

// --- idempotence and frontier regression ----------------------------------

pub fn compact_at_same_frontier_is_noop_test() {
  let seq = abc() |> sequence.delete(1)
  let #(once, _) = sequence.compact(seq, frontier_a(4))
  let #(twice, forwardings) = sequence.compact(once, frontier_a(4))

  twice |> expect.to_equal(once)
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
}

pub fn compact_at_older_frontier_is_noop_test() {
  let seq = abc() |> sequence.delete(1)
  let #(once, _) = sequence.compact(seq, frontier_a(4))
  let #(regressed, forwardings) = sequence.compact(once, frontier_a(2))

  regressed |> expect.to_equal(once)
  sequence.forwarding_size(forwardings) |> expect.to_equal(0)
}

// --- editing compacted state ----------------------------------------------

pub fn insert_into_middle_of_block_splits_it_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let updated = sequence.insert(compacted, 1, "x")

  sequence.values(updated) |> expect.to_equal(["a", "x", "b", "c"])
  count_kind(updated, "block") |> expect.to_equal(2)
  count_kind(updated, "item") |> expect.to_equal(1)
}

pub fn delete_inside_block_extracts_tombstone_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let updated = sequence.delete(compacted, 1)

  sequence.values(updated) |> expect.to_equal(["a", "c"])
  count_kind(updated, "item") |> expect.to_equal(1)
}

pub fn delete_inside_block_converges_across_replicas_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let b_state = sequence.merge(sequence.new(rid("B")), compacted)
  let a_edit = sequence.delete(compacted, 1)
  let b_edit = sequence.insert(b_state, 3, "d")

  sequence.values(sequence.merge(a_edit, b_edit))
  |> expect.to_equal(["a", "c", "d"])
  sequence.values(sequence.merge(b_edit, a_edit))
  |> expect.to_equal(["a", "c", "d"])
}

pub fn move_out_of_block_converges_across_replicas_test() {
  let #(compacted, _) = sequence.compact(abc(), frontier_a(3))
  let b_state = sequence.merge(sequence.new(rid("B")), compacted)
  let a_edit = sequence.move(compacted, 0, 2)

  sequence.values(a_edit) |> expect.to_equal(["b", "c", "a"])
  sequence.values(sequence.merge(a_edit, b_state))
  |> expect.to_equal(["b", "c", "a"])
  sequence.values(sequence.merge(b_state, a_edit))
  |> expect.to_equal(["b", "c", "a"])
}

// --- merging compacted and uncompacted states ------------------------------

pub fn merge_with_uncompacted_peer_converges_test() {
  let base = abc()
  let b_state =
    sequence.merge(sequence.new(rid("B")), base)
    |> sequence.insert(1, "x")
  let #(compacted, _) = sequence.compact(base, frontier_a(3))

  sequence.values(sequence.merge(compacted, b_state))
  |> expect.to_equal(["a", "x", "b", "c"])
  sequence.values(sequence.merge(b_state, compacted))
  |> expect.to_equal(["a", "x", "b", "c"])
}

pub fn merge_does_not_resurrect_compacted_tombstone_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
  let b_state = sequence.merge(sequence.new(rid("B")), base)
  let deleted = sequence.delete(base, 0)
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  sequence.values(sequence.merge(compacted, b_state))
  |> expect.to_equal(["b"])
  sequence.values(sequence.merge(b_state, compacted))
  |> expect.to_equal(["b"])
}

// --- anchors ---------------------------------------------------------------

pub fn anchor_resolves_through_forwarding_after_compaction_test() {
  let seq = abc()
  let anchor = sequence.anchor_at(seq, 1, sequence.Before)
  let deleted = sequence.delete(seq, 1)
  let #(compacted, round) = sequence.compact(deleted, frontier_a(4))

  sequence.try_resolve(deleted, anchor) |> expect.to_equal(Ok(1))
  sequence.try_resolve(compacted, anchor) |> expect.to_equal(Ok(1))

  let expired = sequence.remove_forwardings(compacted, round)
  sequence.try_resolve(expired, anchor)
  |> expect.to_equal(Error(sequence.UnknownAnchorTarget))
}

pub fn forwarding_at_document_start_resolves_to_zero_test() {
  let seq =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
  let anchor = sequence.anchor_at(seq, 0, sequence.Before)
  let deleted = sequence.delete(seq, 0)
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  sequence.try_resolve(compacted, anchor) |> expect.to_equal(Ok(0))
}

pub fn anchor_on_visible_item_survives_compaction_test() {
  let seq = abc() |> sequence.delete(0)
  let anchor = sequence.anchor_at(seq, 1, sequence.After)
  let #(compacted, _) = sequence.compact(seq, frontier_a(4))

  sequence.try_resolve(compacted, anchor)
  |> expect.to_equal(sequence.try_resolve(seq, anchor))
}

// --- rebase / origin translation --------------------------------------------

pub fn translate_origins_rebases_dropped_left_origin_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
  let c_state = sequence.merge(sequence.new(rid("C")), base)
  let #(_, delta) = sequence.insert_with_delta(c_state, 1, "x")
  let deleted = sequence.delete(base, 0)
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  let assert Ok(translated) = sequence.translate_origins(delta, compacted)
  sequence.values(sequence.merge(compacted, translated))
  |> expect.to_equal(["x", "b"])
}

pub fn translate_origins_lands_at_same_visible_position_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
  // C appends after b, so the delta's left origin is b's ID.
  let c_state = sequence.merge(sequence.new(rid("C")), base)
  let #(_, delta) = sequence.insert_with_delta(c_state, 2, "x")

  let deleted = sequence.delete(base, 1)
  let uncompacted = sequence.merge(deleted, delta)
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))
  let assert Ok(translated) = sequence.translate_origins(delta, compacted)

  sequence.values(sequence.merge(compacted, translated))
  |> expect.to_equal(sequence.values(uncompacted))
}

pub fn translate_origins_expired_forwarding_fails_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
  let c_state = sequence.merge(sequence.new(rid("C")), base)
  let #(_, delta) = sequence.insert_with_delta(c_state, 1, "x")
  let deleted = sequence.delete(base, 0)
  let #(compacted, round) = sequence.compact(deleted, frontier_a(3))
  let expired = sequence.remove_forwardings(compacted, round)

  sequence.translate_origins(delta, expired)
  |> expect.to_equal(Error(sequence.UnknownOriginTarget))
}

pub fn translate_origins_drops_already_compacted_items_test() {
  let base =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> sequence.insert(1, "b")
  let #(deleted, delete_delta) = sequence.delete_with_delta(base, 0)
  let #(compacted, _) = sequence.compact(deleted, frontier_a(3))

  let assert Ok(translated) =
    sequence.translate_origins(delete_delta, compacted)
  sequence.length(translated) |> expect.to_equal(0)
  sequence.values(sequence.merge(compacted, translated))
  |> expect.to_equal(["b"])
}
