//// Two ORMap levels retain a sparse Text delta through serialization.

import gleam/io
import gleam/json
import gleam/result
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_text/text

pub fn main() {
  let alice = replica_id.new("alice")
  let bob = replica_id.new("bob")
  let schema = crdt.OrMapSpec(crdt.TextSpec)
  let local: or_map.ORMap(String) = or_map.new(alice, schema)

  let assert Ok(#(local, created)) =
    insert_note(local, "board", "card", 0, "draft")
  let assert Ok(remote) = or_map.apply_delta(or_map.new(bob, schema), created)

  let assert Ok(#(local, edit)) =
    insert_note(local, "board", "card", 5, " ready")
  let encoded = edit |> or_map.delta_to_json |> json.to_string
  let assert Ok(decoded) = or_map.delta_from_json(encoded)
  let assert Ok(remote) = or_map.apply_delta(remote, decoded)
  let assert Ok(remote) = or_map.apply_delta(remote, decoded)

  let assert True = note(local) == note(remote)
  let assert "draft ready" = note(remote)
  io.println("Nested ORMaps: " <> note(remote))
}

fn insert_note(map, board, card, index, content) {
  or_map.update_delta(map, board, fn(value, _context) {
    let assert crdt.CrdtOrMap(cards) = value
    or_map.update_delta(cards, card, fn(value, _context) {
      let assert crdt.CrdtText(document) = value
      text.insert_with_delta(document, index, content)
      |> result.map(fn(pair) {
        let #(_updated, delta) = pair
        crdt.StateDelta(crdt.CrdtText(delta))
      })
    })
    |> result.map(fn(pair) {
      let #(_updated, delta) = pair
      crdt.OrMapChange(delta)
    })
  })
}

fn note(map: or_map.ORMap(String)) -> String {
  let assert Ok(crdt.CrdtOrMap(cards)) = or_map.get(map, "board")
  let assert Ok(crdt.CrdtText(document)) = or_map.get(cards, "card")
  text.value(document)
}
