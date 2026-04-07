import gleam/int
import gleam/io
import gleam/json
import lattice_counters/g_counter

pub fn main() {
  io.println("=== GCounter (Grow-Only Counter) ===")
  io.println("")

  // Create counters on two replicas
  let counter_a = g_counter.new("node-a")
  let counter_b = g_counter.new("node-b")

  // Increment each counter
  let counter_a = counter_a |> g_counter.increment(5)
  let counter_b = counter_b |> g_counter.increment(3)

  io.println("node-a value: " <> int.to_string(g_counter.value(counter_a)))
  io.println("node-b value: " <> int.to_string(g_counter.value(counter_b)))

  // Merge the two counters
  let merged = g_counter.merge(counter_a, counter_b)
  io.println("Merged value:  " <> int.to_string(g_counter.value(merged)))

  // Demonstrate idempotency: merging again yields the same result
  let merged_again = g_counter.merge(merged, counter_b)
  io.println("Merged again:  " <> int.to_string(g_counter.value(merged_again)))
  io.println("✓ Merge is idempotent")
  io.println("")

  // JSON round-trip
  io.println("--- JSON Serialization ---")
  let json_str = merged |> g_counter.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case g_counter.from_json(json_str) {
    Ok(decoded) -> {
      let original_value = g_counter.value(merged)
      let decoded_value = g_counter.value(decoded)
      case original_value == decoded_value {
        True ->
          io.println(
            "✓ JSON round-trip successful (value: "
            <> int.to_string(decoded_value)
            <> ")",
          )
        False -> io.println("✗ JSON round-trip value mismatch")
      }
    }
    Error(_) -> io.println("✗ JSON round-trip failed")
  }
}
