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
  io.println("=== ORMap (Observed-Remove Map) ===")
  io.println("")

  // Create two maps on different replicas using GCounterSpec
  // (so each value in the map is a GCounter)
  let map_a = or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
  let map_b = or_map.new(replica_id.new("node-b"), crdt.GCounterSpec)

  // Map A: increment "page-views" by 5
  let map_a = or_map.update(map_a, "page-views", increment_by(_, 5))

  // Map B: increment "page-views" by 3, "api-calls" by 10
  let map_b = or_map.update(map_b, "page-views", increment_by(_, 3))
  let map_b = or_map.update(map_b, "api-calls", increment_by(_, 10))

  // Print keys of each map
  io.println("Map A (node-a):")
  io.println(
    "  keys: ["
    <> string.join(list.sort(or_map.keys(map_a), string.compare), ", ")
    <> "]",
  )
  print_counter(map_a, "page-views")
  io.println("")

  io.println("Map B (node-b):")
  io.println(
    "  keys: ["
    <> string.join(list.sort(or_map.keys(map_b), string.compare), ", ")
    <> "]",
  )
  print_counter(map_b, "page-views")
  print_counter(map_b, "api-calls")
  io.println("")

  // Merge — "page-views" counters merge (5 + 3 = 8), "api-calls" appears
  let assert Ok(merged) = or_map.merge(map_a, map_b)
  io.println("Merged map:")
  io.println(
    "  keys: ["
    <> string.join(list.sort(or_map.keys(merged), string.compare), ", ")
    <> "]",
  )
  print_counter(merged, "page-views")
  print_counter(merged, "api-calls")
  io.println("  → page-views merged: 5 + 3 = 8 ✓")
  io.println("")

  // Demonstrate remove: remove "api-calls", verify it's gone
  let after_remove = or_map.remove(merged, "api-calls")
  io.println("After removing 'api-calls':")
  io.println(
    "  keys: ["
    <> string.join(list.sort(or_map.keys(after_remove), string.compare), ", ")
    <> "]",
  )
  case or_map.get(after_remove, "api-calls") {
    Ok(_) -> io.println("  → 'api-calls' still present (unexpected)")
    Error(_) -> io.println("  → 'api-calls' is gone ✓")
  }
  io.println("")

  // JSON round-trip
  let json_str = after_remove |> or_map.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case or_map.from_json(json_str) {
    Ok(_decoded) -> io.println("✓ JSON round-trip successful")
    Error(_) -> io.println("✗ JSON round-trip failed")
  }

  io.println("")
  io.println("ORMap example complete!")
}

/// Increment a GCounter value; the map is created with `crdt.GCounterSpec`,
/// so every other variant is left untouched.
fn increment_by(value: crdt.Crdt, amount: Int) -> crdt.Crdt {
  case value {
    crdt.CrdtGCounter(counter) ->
      crdt.CrdtGCounter(g_counter.increment(counter, amount))
    crdt.CrdtPnCounter(_)
    | crdt.CrdtLwwRegister(_)
    | crdt.CrdtMvRegister(_)
    | crdt.CrdtGSet(_)
    | crdt.CrdtTwoPSet(_)
    | crdt.CrdtOrSet(_)
    | crdt.CrdtVersionVector(_) -> value
  }
}

fn get_counter_value(map: or_map.ORMap, key: String) -> Int {
  case or_map.get(map, key) {
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
}

fn print_counter(map: or_map.ORMap, key: String) {
  io.println("  " <> key <> " = " <> int.to_string(get_counter_value(map, key)))
}
