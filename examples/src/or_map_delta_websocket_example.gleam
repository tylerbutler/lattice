//// Delta-state replication example simulating two websocket peers.
////
//// Two replicas (`alice` and `bob`) maintain an `ORMap` of GCounters.
//// Instead of broadcasting full state on every change, each replica
//// produces a small `ORMapDelta` from its mutation and ships only that.
//// The other replica receives the delta and merges it via `apply_delta`.
////
//// Run with `gleam run -m or_map_delta_websocket_example`.

import gleam/int
import gleam/io
import gleam/json as gleam_json
import gleam/list
import gleam/order as order_module
import gleam/string
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/or_map

pub fn main() {
  io.println("=== ORMap delta-state replication (websocket simulation) ===")
  io.println("")

  let alice = or_map.new(replica_id.new("alice"), crdt.GCounterSpec)
  let bob = or_map.new(replica_id.new("bob"), crdt.GCounterSpec)

  // Step 1 — Alice clicks "page-views" 5 times. Emit delta.
  let #(alice, d1) = or_map.update_with_delta(alice, "page-views", inc(5))
  io.println(
    "Alice +=5 on page-views; delta wire size: "
    <> int.to_string(wire_size(d1))
    <> " bytes",
  )

  // Step 2 — Bob concurrently increments "page-views" by 3 and adds "api-calls".
  let #(bob, d_b1) = or_map.update_with_delta(bob, "page-views", inc(3))
  let #(bob, d_b2) = or_map.update_with_delta(bob, "api-calls", inc(10))
  let assert Ok(d_bob_combined) = or_map.merge_deltas(d_b1, d_b2)
  io.println(
    "Bob +=3 page-views, +=10 api-calls; combined delta wire size: "
    <> int.to_string(wire_size(d_bob_combined))
    <> " bytes",
  )

  // Step 3 — Exchange deltas over the simulated socket.
  let assert Ok(alice) = or_map.apply_delta(alice, d_bob_combined)
  let assert Ok(bob) = or_map.apply_delta(bob, d1)

  // Step 4 — Alice does another mutation; ship only the delta.
  let #(alice, d2) = or_map.update_with_delta(alice, "page-views", inc(2))
  let assert Ok(bob) = or_map.apply_delta(bob, d2)

  // Both replicas have converged.
  io.println("")
  io.println("Alice's view: " <> render(alice))
  io.println("Bob's view:   " <> render(bob))

  // Compare wire size of full-state shipping vs delta shipping for the last op.
  let alice_full_size = wire_size_full(alice)
  io.println("")
  io.println(
    "Last delta wire size: "
    <> int.to_string(wire_size(d2))
    <> " bytes vs full-state size: "
    <> int.to_string(alice_full_size)
    <> " bytes",
  )
}

fn inc(n: Int) -> fn(crdt.Crdt) -> #(crdt.Crdt, crdt.Crdt) {
  fn(c) {
    let assert crdt.CrdtGCounter(gc) = c
    let #(new_gc, delta_gc) = g_counter.increment_with_delta(gc, n)
    #(crdt.CrdtGCounter(new_gc), crdt.CrdtGCounter(delta_gc))
  }
}

fn render(map: or_map.ORMap) -> String {
  or_map.keys(map)
  |> list.sort(string_compare)
  |> list.map(fn(key) {
    let v = case or_map.get(map, key) {
      Ok(crdt.CrdtGCounter(gc)) -> g_counter.value(gc)
      _ -> 0
    }
    key <> "=" <> int.to_string(v)
  })
  |> string.join(", ")
}

fn wire_size(d: or_map.ORMapDelta) -> Int {
  string.length(gleam_json.to_string(or_map.delta_to_json(d)))
}

fn wire_size_full(m: or_map.ORMap) -> Int {
  string.length(gleam_json.to_string(or_map.to_json(m)))
}

fn string_compare(a: String, b: String) -> order_module.Order {
  string.compare(a, b)
}
