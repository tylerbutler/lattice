import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lattice/lww_map

pub fn main() {
  io.println("=== LWWMap (Last-Writer-Wins Map) ===")
  io.println("")

  // Create two maps simulating user profile settings on different replicas
  let map_a =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.set("email", "alice@example.com", 1)

  let map_b =
    lww_map.new()
    |> lww_map.set("name", "Bob", 2)
    |> lww_map.set("theme", "dark", 1)

  // Print contents of each map
  io.println("Map A (Alice's replica):")
  print_map(map_a)
  io.println("")

  io.println("Map B (Bob's replica):")
  print_map(map_b)
  io.println("")

  // Merge the two maps — "name" resolves to "Bob" (higher timestamp wins)
  let merged = lww_map.merge(map_a, map_b)
  io.println("Merged map:")
  print_map(merged)

  let name = result.unwrap(lww_map.get(merged, "name"), "")
  io.println("  → 'name' resolved to: " <> name <> " (timestamp 2 > 1)")
  io.println("")

  // Demonstrate remove: remove "theme" at t=3
  let after_remove = lww_map.remove(merged, "theme", 3)
  io.println("After removing 'theme' at t=3:")
  print_map(after_remove)

  let theme_result = lww_map.get(after_remove, "theme")
  case theme_result {
    Ok(_) -> io.println("  → 'theme' still present (unexpected)")
    Error(_) -> io.println("  → 'theme' is gone ✓")
  }
  io.println("")

  // JSON round-trip
  let json_str = after_remove |> lww_map.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case lww_map.from_json(json_str) {
    Ok(_decoded) -> io.println("✓ JSON round-trip successful")
    Error(_) -> io.println("✗ JSON round-trip failed")
  }

  io.println("")
  io.println("LWWMap example complete!")
}

fn print_map(map: lww_map.LWWMap) {
  let ks = lww_map.keys(map)
  io.println(
    "  keys: [" <> string.join(list.sort(ks, string.compare), ", ") <> "]",
  )
  list.sort(ks, string.compare)
  |> list.each(fn(k) {
    let v = result.unwrap(lww_map.get(map, k), "")
    io.println("  " <> k <> " = " <> v)
  })
}
