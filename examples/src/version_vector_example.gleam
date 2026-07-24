import gleam/dict
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector

fn print_dict(label: String, d: dict.Dict(replica_id.ReplicaId, Int)) -> Nil {
  let contents =
    d
    |> dict.to_list
    |> list.sort(fn(a, b) {
      string.compare(replica_id.to_string(a.0), replica_id.to_string(b.0))
    })
    |> list.map(fn(pair) {
      replica_id.to_string(pair.0) <> "=" <> int.to_string(pair.1)
    })
    |> string.join(", ")
  io.println(label <> "{" <> contents <> "}")
}

pub fn main() {
  io.println("=== VersionVector (Logical Clocks) ===")
  io.println("")

  // Create two version vectors with different clock histories
  io.println("Creating two version vectors...")
  let node_a = replica_id.new("node-a")
  let node_b = replica_id.new("node-b")

  let vector_a =
    version_vector.new()
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_b)

  let vector_b =
    version_vector.new()
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_b)
    |> version_vector.increment(node_b)

  io.println(
    "vector_a: node-a="
    <> int.to_string(version_vector.get(vector_a, node_a))
    <> ", node-b="
    <> int.to_string(version_vector.get(vector_a, node_b)),
  )
  io.println(
    "vector_b: node-a="
    <> int.to_string(version_vector.get(vector_b, node_a))
    <> ", node-b="
    <> int.to_string(version_vector.get(vector_b, node_b)),
  )
  io.println("")

  // Compare — should be Concurrent (neither dominates)
  io.println("--- Comparison ---")
  let order_str = case version_vector.compare(vector_a, vector_b) {
    version_vector.Before -> "Before"
    version_vector.After -> "After"
    version_vector.Concurrent -> "Concurrent"
    version_vector.Equal -> "Equal"
  }
  io.println("compare(vector_a, vector_b) = " <> order_str)
  io.println(
    "(vector_a has higher node-a, vector_b has higher node-b → Concurrent)",
  )
  io.println("")

  // Create a third vector that strictly dominates vector_a
  io.println("--- Strict ordering ---")
  let vector_c =
    version_vector.new()
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_b)
    |> version_vector.increment(node_b)

  io.println(
    "vector_c: node-a="
    <> int.to_string(version_vector.get(vector_c, node_a))
    <> ", node-b="
    <> int.to_string(version_vector.get(vector_c, node_b)),
  )
  let order_str_2 = case version_vector.compare(vector_a, vector_c) {
    version_vector.Before -> "Before"
    version_vector.After -> "After"
    version_vector.Concurrent -> "Concurrent"
    version_vector.Equal -> "Equal"
  }
  io.println("compare(vector_a, vector_c) = " <> order_str_2)
  io.println("(vector_c dominates vector_a on all clocks → Before)")
  io.println("")

  // Merge — pairwise maximum
  io.println("--- Merge (pairwise maximum) ---")
  let merged = version_vector.merge(vector_a, vector_b)
  io.println(
    "merge(vector_a, vector_b): node-a="
    <> int.to_string(version_vector.get(merged, node_a))
    <> ", node-b="
    <> int.to_string(version_vector.get(merged, node_b)),
  )
  io.println("(takes max of each clock: node-a=3, node-b=2)")
  io.println("")

  // Dictionary conversion
  io.println("--- Dict Conversion ---")
  let clocks = version_vector.to_dict(merged)
  print_dict("to_dict: ", clocks)
  let restored = version_vector.from_dict(clocks)
  let roundtrip_ok = case version_vector.compare(merged, restored) {
    version_vector.Equal -> "true"
    version_vector.Before | version_vector.After | version_vector.Concurrent ->
      "false"
  }
  io.println("from_dict round-trip equal: " <> roundtrip_ok)
  io.println("")

  // JSON round-trip
  io.println("--- JSON Serialization ---")
  let json_str = merged |> version_vector.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case version_vector.from_json(json_str) {
    Ok(_decoded) -> io.println("✓ JSON round-trip successful")
    Error(_) -> io.println("✗ JSON round-trip failed")
  }
  io.println("")

  io.println("=== VersionVector Example Complete ===")
}
