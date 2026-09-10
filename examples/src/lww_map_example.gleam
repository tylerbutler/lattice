import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register

pub fn main() {
  io.println("=== LWWMap: atomic CRDT child assignments ===")
  let alice = replica_id.new("alice")
  let bob = replica_id.new("bob")
  let schema = crdt.LwwRegisterSpec("")

  let left =
    lww_map.new(alice, schema)
    |> assign("name", "Alice", 1, alice)
    |> assign("theme", "light", 1, alice)
  let right =
    lww_map.new(bob, schema)
    |> assign("name", "Bob", 2, bob)
    |> assign("theme", "dark", 2, bob)

  let assert Ok(merged) = lww_map.merge_as(left, right, alice)
  print_map(merged)
  let assert Ok(crdt.CrdtLwwRegister(name)) = lww_map.get(merged, "name")
  let assert "Bob" = lww_register.value(name)

  let assert Ok(removed) = lww_map.remove(merged, "theme", 3)
  let assert Error(Nil) = lww_map.get(removed, "theme")
  io.println(
    "Tombstones before stable pruning: "
    <> int.to_string(lww_map.tombstone_count(removed)),
  )

  // The application must establish this timestamp as stable across peers.
  let pruned = lww_map.prune(removed, 3)
  let assert Error(Nil) = lww_map.get(pruned, "theme")
  let encoded = pruned |> lww_map.to_json |> json.to_string
  let assert Ok(decoded) = lww_map.from_json(encoded)
  let assert Ok(adopted) =
    lww_map.merge_as(lww_map.new(bob, schema), decoded, bob)
  print_map(adopted)
}

fn assign(
  map: lww_map.LWWMap(String),
  key: String,
  value: String,
  timestamp: Int,
  author: ReplicaId,
) -> lww_map.LWWMap(String) {
  let child = crdt.CrdtLwwRegister(lww_register.new(value, timestamp, author))
  let assert Ok(updated) = lww_map.set(map, key, child, timestamp)
  updated
}

fn print_map(map: lww_map.LWWMap(String)) -> Nil {
  lww_map.keys(map)
  |> list.sort(string.compare)
  |> list.each(fn(key) {
    let assert Ok(crdt.CrdtLwwRegister(register)) = lww_map.get(map, key)
    io.println(key <> "=" <> lww_register.value(register))
  })
}
