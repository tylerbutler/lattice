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
import gleam/json
import gleam/list
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
  let assert Ok(#(alice, alice_delta)) =
    or_map.update_with_delta(alice, "page-views", increment_by(5))
  io.println(
    "Alice +=5 on page-views; delta wire size: "
    <> int.to_string(wire_size(alice_delta))
    <> " bytes",
  )

  // Step 2 — Bob concurrently increments "page-views" by 3 and adds "api-calls".
  let assert Ok(#(bob, bob_views_delta)) =
    or_map.update_with_delta(bob, "page-views", increment_by(3))
  let assert Ok(#(bob, bob_calls_delta)) =
    or_map.update_with_delta(bob, "api-calls", increment_by(10))
  let assert Ok(bob_combined_delta) =
    or_map.merge_deltas(bob_views_delta, bob_calls_delta)
  io.println(
    "Bob +=3 page-views, +=10 api-calls; combined delta wire size: "
    <> int.to_string(wire_size(bob_combined_delta))
    <> " bytes",
  )

  // Step 3 — Exchange deltas over the simulated socket.
  let assert Ok(alice) = or_map.apply_delta(alice, bob_combined_delta)
  let assert Ok(bob) = or_map.apply_delta(bob, alice_delta)

  // Step 4 — Alice does another mutation; ship only the delta.
  let assert Ok(#(alice, alice_second_delta)) =
    or_map.update_with_delta(alice, "page-views", increment_by(2))
  let assert Ok(bob) = or_map.apply_delta(bob, alice_second_delta)

  // Both replicas have converged.
  io.println("")
  io.println("Alice's view: " <> render(alice))
  io.println("Bob's view:   " <> render(bob))

  // Compare wire size of full-state shipping vs delta shipping for the last op.
  let alice_full_size = wire_size_full(alice)
  io.println("")
  io.println(
    "Last delta wire size: "
    <> int.to_string(wire_size(alice_second_delta))
    <> " bytes vs full-state size: "
    <> int.to_string(alice_full_size)
    <> " bytes",
  )
}

fn increment_by(amount: Int) -> fn(crdt.Crdt) -> crdt.Crdt {
  fn(value) {
    let assert crdt.CrdtGCounter(counter) = value
    crdt.CrdtGCounter(g_counter.increment(counter, amount))
  }
}

fn render(map: or_map.ORMap) -> String {
  or_map.keys(map)
  |> list.sort(string.compare)
  |> list.map(fn(key) {
    let count = case or_map.get(map, key) {
      Ok(crdt.CrdtGCounter(counter)) -> g_counter.value(counter)
      Ok(crdt.CrdtPnCounter(_))
      | Ok(crdt.CrdtLwwRegister(_))
      | Ok(crdt.CrdtMvRegister(_))
      | Ok(crdt.CrdtGSet(_))
      | Ok(crdt.CrdtTwoPSet(_))
      | Ok(crdt.CrdtOrSet(_))
      | Ok(crdt.CrdtVersionVector(_))
      | Error(Nil) -> 0
    }
    key <> "=" <> int.to_string(count)
  })
  |> string.join(", ")
}

fn wire_size(delta: or_map.ORMapDelta) -> Int {
  string.length(json.to_string(or_map.delta_to_json(delta)))
}

fn wire_size_full(map: or_map.ORMap) -> Int {
  string.length(json.to_string(or_map.to_json(map)))
}
