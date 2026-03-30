import gleam/io
import gleam/json
import gleam/string
import lattice_registers/mv_register

pub fn main() {
  io.println("=== MVRegister (Multi-Value Register) ===")
  io.println("")

  // Create two registers on different nodes
  let node_a = mv_register.new("node-a")
  let node_b = mv_register.new("node-b")

  // Concurrent writes on each node
  let node_a = mv_register.set(node_a, "alice")
  let node_b = mv_register.set(node_b, "bob")

  io.println(
    "Node A values: [" <> string.join(mv_register.value(node_a), ", ") <> "]",
  )
  io.println(
    "Node B values: [" <> string.join(mv_register.value(node_b), ", ") <> "]",
  )
  io.println("")

  // Merge — concurrent writes are preserved (both values kept)
  io.println("--- Merging concurrent writes ---")
  let merged = mv_register.merge(node_a, node_b)
  let merged_values = mv_register.value(merged)
  io.println("Merged values: [" <> string.join(merged_values, ", ") <> "]")
  io.println("Both values are kept because the writes were concurrent!")
  io.println("")

  // Resolve conflict by setting a new value
  io.println("--- Resolving conflict ---")
  let resolved = mv_register.set(merged, "charlie")
  io.println(
    "After set(\"charlie\"): ["
    <> string.join(mv_register.value(resolved), ", ")
    <> "]",
  )
  io.println("Conflict resolved — only the new value remains")
  io.println("")

  // JSON round-trip
  io.println("--- JSON serialization ---")
  let json_str = resolved |> mv_register.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case mv_register.from_json(json_str) {
    Ok(decoded) ->
      io.println(
        "✓ JSON round-trip successful (values: ["
        <> string.join(mv_register.value(decoded), ", ")
        <> "])",
      )
    Error(_) -> io.println("✗ JSON round-trip failed")
  }

  io.println("")
  io.println("Done! MVRegister preserves all concurrent values until resolved.")
}
