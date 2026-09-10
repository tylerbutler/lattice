import gleam/dynamic/decode
import gleam/json
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sequence/sequence

pub fn nested(writer: String, values: List(Int)) -> or_map.ORMap(Int) {
  let map =
    or_map.new(replica_id.new(writer), crdt.OrMapSpec(crdt.SequenceSpec))
  let assert Ok(map) =
    or_map.update(map, "doc", fn(child) {
      let assert crdt.CrdtOrMap(child) = child
      let assert Ok(child) =
        or_map.update(child, "body", fn(value) {
          let assert crdt.CrdtSequence(value) = value
          let assert Ok(value) = sequence.insert_many(value, 0, values)
          crdt.CrdtSequence(value)
        })
      crdt.CrdtOrMap(child)
    })
  map
}

pub fn edit(
  map: or_map.ORMap(Int),
  callback: fn(sequence.Sequence(Int)) -> sequence.Sequence(Int),
) -> #(or_map.ORMap(Int), or_map.ORMapDelta(Int)) {
  let assert Ok(pair) =
    or_map.update_delta(map, "doc", fn(child, _) {
      let assert crdt.CrdtOrMap(child) = child
      let assert Ok(#(_, delta)) =
        or_map.update_delta(child, "body", fn(value, _) {
          let assert crdt.CrdtSequence(value) = value
          Ok(crdt.StateDelta(crdt.CrdtSequence(callback(value))))
        })
      Ok(crdt.OrMapChange(delta))
    })
  pair
}

pub fn append(map: or_map.ORMap(Int), value: Int) {
  edit(map, fn(state) {
    let assert Ok(#(_, delta)) =
      sequence.insert_with_delta(state, sequence.length(state), value)
    delta
  })
}

pub fn sequence(map: or_map.ORMap(Int)) -> sequence.Sequence(Int) {
  let assert Ok(crdt.CrdtOrMap(child)) = or_map.get(map, "doc")
  let assert Ok(crdt.CrdtSequence(value)) = or_map.get(child, "body")
  value
}

pub fn version(input: String) -> Int {
  let assert Ok(version) =
    json.parse(input, {
      use version <- decode.field("v", decode.int)
      decode.success(version)
    })
  version
}

pub fn delta_child(input: String, expected_key: String) -> String {
  let assert Ok([#(key, child)]) =
    json.parse(input, {
      use state <- decode.field("state", {
        use entries <- decode.field(
          "entries",
          decode.list({
            use key <- decode.field("key", decode.string)
            use value <- decode.field("value", decode.string)
            decode.success(#(key, value))
          }),
        )
        decode.success(entries)
      })
      decode.success(state)
    })
  let assert True = key == expected_key
  child
}

pub fn dispatch_payload(input: String, expected_kind: String) -> String {
  let assert Ok(#(kind, payload)) =
    json.parse(input, {
      use state <- decode.field("state", {
        use kind <- decode.field("kind", decode.string)
        use payload <- decode.field("payload", decode.string)
        decode.success(#(kind, payload))
      })
      decode.success(state)
    })
  let assert True = kind == expected_kind
  payload
}
