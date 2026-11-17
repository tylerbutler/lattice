import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence

fn large_values() -> List(Int) {
  list.repeat(Nil, 20_000) |> list.index_map(fn(_, index) { index })
}

pub fn delete_at_end_of_large_live_and_compacted_sequences_test() {
  let replica = replica_id.new("A")
  let values = large_values()
  let assert Ok(base) = sequence.insert_many(sequence.new(replica), 0, values)
  let floor = version_vector.new() |> version_vector.set_max(replica, 20_000)
  let #(compacted, _) = sequence.compact(base, floor)
  use state <- list.each([base, compacted])
  let assert Ok(#(deleted, delta)) = sequence.delete_with_delta(state, 19_999)
  assert sequence.values(deleted) == list.take(values, 19_999)
  let assert Ok(decoded) =
    sequence.to_json(deleted, json.int)
    |> json.to_string()
    |> sequence.from_json(decode.int)
  assert decoded == deleted
  let floor = version_vector.set_max(floor, replica, 20_001)
  let #(settled, forwardings) = sequence.compact(deleted, floor)
  assert sequence.forwarding_size(forwardings) == 1
  assert sequence.values(settled) == list.take(values, 19_999)
  assert sequence.values(sequence.merge(compacted, delta, replica))
    == list.take(values, 19_999)
}

pub fn moves_and_edits_of_large_sequences_preserve_order_test() {
  let replica = replica_id.new("A")
  let values = large_values()
  let assert Ok(base) = sequence.insert_many(sequence.new(replica), 0, values)
  // Keep the 20,000-element scans without rebuilding 20,000 volatile items.
  let floor = version_vector.new() |> version_vector.set_max(replica, 20_000)
  let #(base, _) = sequence.compact(base, floor)
  let assert Ok(first_anchor) = sequence.anchor_at(base, 0, sequence.Before)
  let assert Ok(last_to_first) = sequence.move(base, 19_999, 0)
  assert sequence.values(last_to_first) == [19_999, ..list.take(values, 19_999)]
  let assert Ok(first_to_last) = sequence.move(base, 0, 19_999)
  let expected = list.append(list.drop(values, 1), [0])
  assert sequence.values(first_to_last) == expected
  assert sequence.resolve(first_to_last, first_anchor) == Ok(19_999)
  assert sequence.anchor_at(first_to_last, 19_999, sequence.Before)
    == Ok(first_anchor)
  let assert Ok(decoded) =
    sequence.to_json(first_to_last, json.int)
    |> json.to_string()
    |> sequence.from_json(decode.int)
  assert decoded == first_to_last
  assert sequence.values(decoded) == expected
  let assert Ok(inserted) = sequence.insert(decoded, 19_999, -1)
  assert sequence.values(inserted) == list.append(list.drop(values, 1), [-1, 0])
  assert sequence.resolve(inserted, first_anchor) == Ok(20_000)
  let assert Ok(prepended) = sequence.insert(decoded, 0, -2)
  assert sequence.values(prepended) == [-2, ..expected]
}

pub fn large_move_records_survive_translation_compaction_and_merge_test() {
  let replica = replica_id.new("A")
  let values = large_values()
  let assert Ok(base) = sequence.insert_many(sequence.new(replica), 0, values)
  let floor = version_vector.new() |> version_vector.set_max(replica, 20_000)
  let #(compacted, _) = sequence.compact(base, floor)
  let assert Ok(#(moved, delta)) =
    sequence.move_with_delta(compacted, 0, 19_999)
  let assert Ok(translated) = sequence.translate_origins(moved, compacted)
  assert translated == moved
  let expected = list.append(list.drop(values, 1), [0])
  assert sequence.values(translated) == expected
  let #(settled, _) =
    sequence.compact(translated, version_vector.set_max(floor, replica, 20_001))
  assert sequence.values(settled) == expected
  let assert Ok(translated_delta) = sequence.translate_origins(delta, compacted)
  use merged <- list.each([
    sequence.merge(compacted, translated_delta, replica),
    sequence.merge(translated_delta, compacted, replica),
    sequence.merge(settled, moved, replica),
    sequence.merge(moved, settled, replica),
  ])
  assert sequence.values(merged) == expected
}
