//// Sequence/Text children, sparse updates, and fresh generation resets.

import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/result
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sequence/sequence
import lattice_text/text

pub fn main() {
  text_example()
  sequence_example()
}

fn text_example() {
  let alice = replica_id.new("alice")
  let bob = replica_id.new("bob")
  let local: or_map.ORMap(String) = or_map.new(alice, crdt.TextSpec)
  let assert Ok(#(local, created)) = insert_text(local, "notes", 0, "hello")
  let assert Ok(remote) =
    or_map.apply_delta(or_map.new(bob, crdt.TextSpec), created)

  let assert Ok(#(local, edit)) = insert_text(local, "notes", 5, "!")
  let assert Ok(remote) = or_map.apply_delta(remote, edit)
  let assert Ok(remote) = or_map.apply_delta(remote, edit)
  let assert Ok(crdt.CrdtText(document)) = or_map.get(remote, "notes")
  let assert "hello!" = text.value(document)

  let removed = or_map.remove(local, "notes")
  let assert Ok(#(fresh, _reset)) = insert_text(removed, "notes", 0, "fresh")
  let assert Ok(fresh) = or_map.apply_delta(fresh, edit)
  let assert Ok(crdt.CrdtText(document)) = or_map.get(fresh, "notes")
  let assert "fresh" = text.value(document)
  io.println(
    "Text: sparse replay converges; a re-add replaces the old generation.",
  )
}

fn insert_text(map, key, index, content) {
  or_map.update_delta(map, key, fn(value, _context) {
    let assert crdt.CrdtText(document) = value
    text.insert_with_delta(document, index, content)
    |> result.map(fn(pair) {
      let #(_updated, delta) = pair
      crdt.StateDelta(crdt.CrdtText(delta))
    })
  })
}

fn sequence_example() {
  let alice = replica_id.new("alice")
  let bob = replica_id.new("bob")
  let local: or_map.ORMap(Int) = or_map.new(alice, crdt.SequenceSpec)
  let assert Ok(#(local, _created)) =
    or_map.update_delta(local, "items", fn(value, _context) {
      let assert crdt.CrdtSequence(items) = value
      sequence.insert_many_with_delta(items, 0, [10, 20, 30])
      |> result.map(fn(pair) {
        let #(_updated, delta) = pair
        crdt.StateDelta(crdt.CrdtSequence(delta))
      })
    })

  let snapshot = or_map.to_json_with(local, json.int) |> json.to_string
  let assert Ok(decoded) = or_map.from_json_with(snapshot, decode.int)
  let assert Ok(remote) =
    or_map.merge_as(or_map.new(bob, crdt.SequenceSpec), decoded, bob)
  let assert Ok(#(remote, moved)) =
    or_map.update_delta(remote, "items", fn(value, _context) {
      let assert crdt.CrdtSequence(items) = value
      sequence.move_with_delta(items, 0, 2)
      |> result.map(fn(pair) {
        let #(_updated, delta) = pair
        crdt.StateDelta(crdt.CrdtSequence(delta))
      })
    })
  let encoded = or_map.delta_to_json_with(moved, json.int) |> json.to_string
  let assert Ok(moved) = or_map.delta_from_json_with(encoded, decode.int)
  let assert Ok(local) = or_map.apply_delta(local, moved)
  let assert Ok(local) = or_map.apply_delta(local, moved)
  let assert Ok(crdt.CrdtSequence(left)) = or_map.get(local, "items")
  let assert Ok(crdt.CrdtSequence(right)) = or_map.get(remote, "items")
  let assert True = sequence.values(left) == sequence.values(right)
  io.println(
    "Sequence(Int): a joining replica edits a typed snapshot with sparse deltas.",
  )
}
