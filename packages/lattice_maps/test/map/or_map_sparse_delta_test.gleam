import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sequence/sequence
import lattice_text/text
import startest/expect
import support/composition_fixture as fixture

pub fn nested_sparse_thousand_and_ten_thousand_items_test() {
  list.each([1000, 10_000], fn(size) {
    let baseline =
      fixture.nested(
        "A",
        list.repeat(0, size) |> list.index_map(fn(_, index) { index + 1 }),
      )
    let #(updated, delta) = fixture.append(baseline, size + 1)
    let snapshot = or_map.to_json_with(updated, json.int) |> json.to_string
    let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
    fixture.version(snapshot) |> expect.to_equal(3)
    fixture.version(encoded) |> expect.to_equal(2)
    { string.byte_size(encoded) * 10 < string.byte_size(snapshot) }
    |> expect.to_be_true
    let leaf =
      encoded
      |> fixture.delta_child("doc")
      |> fixture.dispatch_payload("or_map")
      |> fixture.delta_child("body")
      |> fixture.dispatch_payload("state")
    let assert Ok(segments) =
      json.parse(leaf, {
        use state <- decode.field("state", {
          use segments <- decode.field(
            "segments",
            decode.list({
              use kind <- decode.field("kind", decode.string)
              use value <- decode.field("value", decode.int)
              decode.success(#(kind, value))
            }),
          )
          decode.success(segments)
        })
        decode.success(state)
      })
    segments |> expect.to_equal([#("item", size + 1)])
    let assert Ok(decoded) = or_map.delta_from_json_with(encoded, decode.int)
    let assert Ok(applied) = or_map.apply_delta(baseline, decoded)
    applied |> expect.to_equal(updated)
  })
}

pub fn sparse_nested_batch_remains_sparse_and_matches_complete_delivery_test() {
  let baseline = fixture.nested("A", [1, 2, 3])
  let #(first, d1) = fixture.append(baseline, 4)
  let #(second, d2) = fixture.append(first, 5)
  let assert Ok(batch) = or_map.merge_deltas(d1, d2)
  let blank = or_map.new(replica_id.new("R"), crdt.OrMapSpec(crdt.SequenceSpec))
  let assert Ok(bound) = or_map.merge(blank, baseline)
  let assert Ok(applied) = or_map.apply_delta(bound, batch)
  let assert Ok(expected) = or_map.merge(blank, second)
  applied |> expect.to_equal(expected)
  let assert Ok(reordered) =
    list.try_fold([d2, d1, d2, d1], bound, or_map.apply_delta)
  reordered |> expect.to_equal(expected)
  let outer = or_map.delta_to_json_with(batch, json.int) |> json.to_string
  let _ =
    outer |> fixture.delta_child("doc") |> fixture.dispatch_payload("or_map")
  let assert Ok(snapshot_batch) =
    crdt.merge_deltas(
      crdt.OrMapChange(batch),
      crdt.StateDelta(crdt.CrdtOrMap(baseline)),
      crdt.OrMapSpec(crdt.OrMapSpec(crdt.SequenceSpec)),
      replica_id.new("R"),
    )
  let assert crdt.StateDelta(crdt.CrdtOrMap(snapshot)) = snapshot_batch
  snapshot |> expect.to_equal(expected)
}

pub fn out_of_order_sparse_origins_eventually_converge_without_pending_queue_test() {
  let baseline = fixture.nested("A", [1, 2])
  let #(later, delta) = fixture.append(baseline, 3)
  let blank = or_map.new(replica_id.new("R"), crdt.OrMapSpec(crdt.SequenceSpec))
  let assert Ok(incomplete) = or_map.apply_delta(blank, delta)
  let assert Ok(repaired) = or_map.merge(incomplete, baseline)
  let assert Ok(expected) = or_map.merge(blank, later)
  repaired |> expect.to_equal(expected)
  fixture.sequence(repaired) |> sequence.values |> expect.to_equal([1, 2, 3])
}

pub fn nested_sparse_thousand_and_ten_thousand_graphemes_test() {
  list.each([1000, 10_000], fn(size) {
    let map: or_map.ORMap(Int) =
      or_map.new(replica_id.new("A"), crdt.OrMapSpec(crdt.TextSpec))
    let assert Ok(baseline) =
      or_map.update(map, "doc", fn(child) {
        let assert crdt.CrdtOrMap(child) = child
        let assert Ok(child) =
          or_map.update(child, "body", fn(value) {
            let assert crdt.CrdtText(value) = value
            let assert Ok(value) = text.append(value, string.repeat("x", size))
            crdt.CrdtText(value)
          })
        crdt.CrdtOrMap(child)
      })
    let assert Ok(#(updated, delta)) =
      or_map.update_delta(baseline, "doc", fn(child, _) {
        let assert crdt.CrdtOrMap(child) = child
        let assert Ok(#(_, delta)) =
          or_map.update_delta(child, "body", fn(value, _) {
            let assert crdt.CrdtText(value) = value
            let assert Ok(#(_, delta)) = text.append_with_delta(value, "!")
            Ok(crdt.StateDelta(crdt.CrdtText(delta)))
          })
        Ok(crdt.OrMapChange(delta))
      })
    let snapshot = or_map.to_json_with(updated, json.int) |> json.to_string
    let encoded = or_map.delta_to_json_with(delta, json.int) |> json.to_string
    { string.byte_size(encoded) * 10 < string.byte_size(snapshot) }
    |> expect.to_be_true
    let leaf =
      encoded
      |> fixture.delta_child("doc")
      |> fixture.dispatch_payload("or_map")
      |> fixture.delta_child("body")
      |> fixture.dispatch_payload("state")
    let assert Ok(crdt.CrdtText(leaf_delta)) =
      crdt.from_json_with(leaf, decode.int)
    text.length(leaf_delta) |> expect.to_equal(1)
    text.value(leaf_delta) |> expect.to_equal("!")
    let assert Ok(decoded) = or_map.delta_from_json_with(encoded, decode.int)
    let assert Ok(applied) = or_map.apply_delta(baseline, decoded)
    applied |> expect.to_equal(updated)
  })
}
