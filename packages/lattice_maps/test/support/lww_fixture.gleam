//// Scalar fixtures for the pre-composition timestamp and round-trip properties.
//// Operations assert success; rejection behavior is tested against the public API.

import gleam/json
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register

pub fn new() {
  lww_map.new(replica_id.new("fixture"), crdt.LwwRegisterSpec(""))
}

pub fn new_as(writer) {
  lww_map.new(replica_id.new(writer), crdt.LwwRegisterSpec(""))
}

pub fn bind(map, writer) {
  lww_map.bind(map, replica_id.new(writer))
}

pub fn set(map, key, value, timestamp) {
  let child =
    crdt.CrdtLwwRegister(lww_register.new(
      value,
      timestamp,
      replica_id.new("fixture"),
    ))
  let assert Ok(map) = lww_map.set(map, key, child, timestamp)
  map
}

pub fn remove(map, key, timestamp) {
  let assert Ok(map) = lww_map.remove(map, key, timestamp)
  map
}

pub fn merge(a, b) {
  let assert Ok(map) = lww_map.merge(a, b)
  map
}

pub fn merge_as(a, b, writer) {
  let assert Ok(map) = lww_map.merge_as(a, b, replica_id.new(writer))
  map
}

pub fn get(map, key) {
  case lww_map.get(map, key) {
    Ok(crdt.CrdtLwwRegister(value)) -> Ok(lww_register.value(value))
    Error(Nil) -> Error(Nil)
    Ok(_) -> panic as "fixture schema is LwwRegisterSpec"
  }
}

pub fn keys(map) {
  lww_map.keys(map)
}

pub fn prune(map, timestamp) {
  lww_map.prune(map, timestamp)
}

pub fn pruned_timestamp(map) {
  lww_map.pruned_timestamp(map)
}

pub fn tombstone_count(map) {
  lww_map.tombstone_count(map)
}

pub fn to_json(map) -> json.Json {
  lww_map.to_json(map)
}

pub fn from_json(input) {
  lww_map.from_json(input)
}

pub fn import_legacy(input) {
  lww_map.import_legacy(
    input,
    crdt.LwwRegisterSpec(""),
    replica_id.new("fixture"),
  )
}

pub fn legacy(value: String, timestamp: Int) {
  let input =
    json.object([
      #("type", json.string("lww_map")),
      #("v", json.int(1)),
      #(
        "state",
        json.object([
          #(
            "entries",
            json.array(
              [
                json.object([
                  #("key", json.string("key")),
                  #("value", json.string(value)),
                  #("timestamp", json.int(timestamp)),
                ]),
              ],
              fn(entry) { entry },
            ),
          ),
        ]),
      ),
    ])
    |> json.to_string
  let assert Ok(map) = import_legacy(input)
  map
}
