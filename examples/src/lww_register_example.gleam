import gleam/int
import gleam/io
import gleam/json
import lattice/lww_register

pub fn main() {
  io.println("=== LWWRegister (Last-Writer-Wins Register) ===")
  io.println("")

  // Create a register with initial value "alice" at timestamp 1
  let register = lww_register.new("alice", 1)
  io.println("Created register with value: " <> lww_register.value(register))

  // Simulate two replicas diverging
  // Replica A: set to "bob" at timestamp 2
  let replica_a = lww_register.set(register, "bob", 2)
  // Replica B: set to "charlie" at timestamp 3
  let replica_b = lww_register.set(register, "charlie", 3)

  io.println("Replica A value: " <> lww_register.value(replica_a))
  io.println("Replica B value: " <> lww_register.value(replica_b))

  // Merge — higher timestamp wins, so "charlie" (timestamp 3) wins
  let merged = lww_register.merge(replica_a, replica_b)
  io.println(
    "Merged value: " <> lww_register.value(merged) <> " (higher timestamp wins)",
  )
  io.println("")

  // Same timestamp: second argument wins on tie
  io.println("--- Tie-breaking behavior ---")
  let tie_a = lww_register.new("x-value", 5)
  let tie_b = lww_register.new("y-value", 5)
  let tie_merged = lww_register.merge(tie_a, tie_b)
  io.println(
    "merge(\"x-value\"@t5, \"y-value\"@t5) = " <> lww_register.value(tie_merged),
  )
  io.println("On equal timestamps, the second argument wins")
  io.println("")

  // JSON round-trip
  io.println("--- JSON serialization ---")
  let json_str = merged |> lww_register.to_json |> json.to_string
  io.println("JSON: " <> json_str)

  case lww_register.from_json(json_str) {
    Ok(decoded) ->
      io.println(
        "✓ JSON round-trip successful (value: "
        <> lww_register.value(decoded)
        <> ", timestamp: "
        <> int.to_string(decoded.timestamp)
        <> ")",
      )
    Error(_) -> io.println("✗ JSON round-trip failed")
  }

  io.println("")
  io.println("Done! LWWRegister resolves conflicts by timestamp.")
}
