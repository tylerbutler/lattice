import gleam/io
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice/or_set

fn print_set(label: String, s: set.Set(String)) -> Nil {
  let contents =
    s |> set.to_list |> list.sort(string.compare) |> string.join(", ")
  io.println(label <> contents)
}

pub fn main() {
  io.println("=== ORSet (Observed-Remove Set) ===")
  io.println("")

  // Create two sets on different replicas
  io.println("Creating two ORSets on different nodes...")
  let node_a = or_set.new("node-a")
  let node_b = or_set.new("node-b")

  // Both nodes add "apple", then sync via merge
  io.println("Both nodes add \"apple\", then sync...")
  let node_a = or_set.add(node_a, "apple")
  let node_b = or_set.add(node_b, "apple")
  let node_a = or_set.merge(node_a, node_b)
  let node_b = or_set.merge(node_b, node_a)
  print_set("Node A after sync: ", or_set.value(node_a))
  print_set("Node B after sync: ", or_set.value(node_b))
  io.println("")

  // Concurrent operations: node-a removes "apple", node-b adds "apple" again
  io.println("Concurrent operations (no sync between these):")
  io.println("  Node A removes \"apple\"")
  io.println("  Node B adds \"apple\" again")
  let node_a = or_set.remove(node_a, "apple")
  let node_b = or_set.add(node_b, "apple")

  let a_has_apple = case or_set.contains(node_a, "apple") {
    True -> "true"
    False -> "false"
  }
  let b_has_apple = case or_set.contains(node_b, "apple") {
    True -> "true"
    False -> "false"
  }
  io.println("Node A contains \"apple\": " <> a_has_apple)
  io.println("Node B contains \"apple\": " <> b_has_apple)
  io.println("")

  // Merge after concurrent operations
  io.println("Merging after concurrent add/remove...")
  let merged = or_set.merge(node_a, node_b)
  print_set("Merged: ", or_set.value(merged))
  io.println("")
  io.println("\"apple\" is present! The ORSet uses add-wins semantics:")
  io.println("Node B's concurrent add created a new causal tag that")
  io.println("Node A's remove did not observe, so it survives the merge.")
  io.println("")

  // Normal add/remove cycle
  io.println("--- Normal add/remove cycle ---")
  let demo = or_set.new("demo")
  let demo =
    demo
    |> or_set.add("x")
    |> or_set.add("y")
    |> or_set.add("z")
  print_set("After adding x, y, z: ", or_set.value(demo))

  let demo = or_set.remove(demo, "y")
  print_set("After removing y: ", or_set.value(demo))

  // Unlike TwoPSet, we can re-add after remove
  let demo = or_set.add(demo, "y")
  print_set("After re-adding y: ", or_set.value(demo))
  io.println("(ORSet supports re-adding removed elements!)")
  io.println("")

  // JSON round-trip
  io.println("--- JSON Serialization ---")
  let json_str = merged |> or_set.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case or_set.from_json(json_str) {
    Ok(decoded) -> {
      print_set("Decoded: ", or_set.value(decoded))
      io.println("✓ JSON round-trip successful")
    }
    Error(_) -> io.println("✗ JSON round-trip failed")
  }
  io.println("")

  io.println("=== ORSet Example Complete ===")
}
