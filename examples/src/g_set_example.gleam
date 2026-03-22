import gleam/io
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice/g_set

fn print_set(label: String, s: set.Set(String)) -> Nil {
  let contents =
    s |> set.to_list |> list.sort(string.compare) |> string.join(", ")
  io.println(label <> contents)
}

pub fn main() {
  io.println("=== GSet (Grow-Only Set) ===")
  io.println("")

  // Create two sets on different replicas
  io.println("Creating two GSets on different replicas...")
  let set_a =
    g_set.new()
    |> g_set.add("apple")
    |> g_set.add("banana")

  let set_b =
    g_set.new()
    |> g_set.add("banana")
    |> g_set.add("cherry")

  print_set("Set A: ", g_set.value(set_a))
  print_set("Set B: ", g_set.value(set_b))
  io.println("")

  // Check membership
  let has_apple = case g_set.contains(set_a, "apple") {
    True -> "true"
    False -> "false"
  }
  let has_cherry = case g_set.contains(set_a, "cherry") {
    True -> "true"
    False -> "false"
  }
  io.println("Set A contains \"apple\": " <> has_apple)
  io.println("Set A contains \"cherry\": " <> has_cherry)
  io.println("")

  // Merge the two replicas
  io.println("Merging Set A and Set B...")
  let merged = g_set.merge(set_a, set_b)
  print_set("Merged: ", g_set.value(merged))
  io.println("(Union of both sets — all three elements are present)")
  io.println("")

  // Note: elements can never be removed from a GSet
  io.println("Note: Elements can never be removed from a GSet.")
  io.println("This makes GSets simple and highly available, but only")
  io.println("suitable when you never need to delete items.")
  io.println("")

  // JSON round-trip
  io.println("--- JSON Serialization ---")
  let json_str = merged |> g_set.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case g_set.from_json(json_str) {
    Ok(decoded) -> {
      print_set("Decoded: ", g_set.value(decoded))
      io.println("✓ JSON round-trip successful")
    }
    Error(_) -> io.println("✗ JSON round-trip failed")
  }
  io.println("")

  io.println("=== GSet Example Complete ===")
}
