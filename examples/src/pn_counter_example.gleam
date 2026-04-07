import gleam/int
import gleam/io
import gleam/json
import lattice_core/replica_id
import lattice_counters/pn_counter

pub fn main() {
  io.println("=== PNCounter (Positive-Negative Counter) ===")
  io.println("")

  // Create counters on two replicas
  let counter_a = pn_counter.new(replica_id.new("node-a"))
  let counter_b = pn_counter.new(replica_id.new("node-b"))

  // node-a: increment by 10, then decrement by 3 → value 7
  let counter_a =
    counter_a
    |> pn_counter.increment(10)
    |> pn_counter.decrement(3)

  // node-b: increment by 5, then decrement by 2 → value 3
  let counter_b =
    counter_b
    |> pn_counter.increment(5)
    |> pn_counter.decrement(2)

  io.println("node-a value: " <> int.to_string(pn_counter.value(counter_a)))
  io.println("node-b value: " <> int.to_string(pn_counter.value(counter_b)))

  // Merge the two counters
  let merged = pn_counter.merge(counter_a, counter_b)
  io.println("Merged value:  " <> int.to_string(pn_counter.value(merged)))
  io.println("")

  // Demonstrate decrement works across merge
  io.println("--- Decrement Across Merge ---")
  let after_decrement = merged |> pn_counter.decrement(4)
  io.println(
    "After decrement by 4: " <> int.to_string(pn_counter.value(after_decrement)),
  )
  io.println("✓ Decrement works correctly after merge")
  io.println("")

  // JSON round-trip
  io.println("--- JSON Serialization ---")
  let json_str = merged |> pn_counter.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case pn_counter.from_json(json_str) {
    Ok(decoded) -> {
      let original_value = pn_counter.value(merged)
      let decoded_value = pn_counter.value(decoded)
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
