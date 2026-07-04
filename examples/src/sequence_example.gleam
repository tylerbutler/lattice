import gleam/int
import gleam/io
import lattice_core/replica_id
import lattice_sequence/sequence

pub fn main() {
  let base = sequence.new(replica_id.new("base")) |> sequence.insert(0, 1)

  let alice =
    sequence.merge(sequence.new(replica_id.new("alice")), base)
    |> sequence.insert(1, 2)

  let bob =
    sequence.merge(sequence.new(replica_id.new("bob")), base)
    |> sequence.insert(1, 3)
    |> sequence.move(0, 1)

  sequence.merge(alice, bob)
  |> sequence.values()
  |> list_to_string()
  |> io.println()
}

fn list_to_string(values: List(Int)) -> String {
  values
  |> list_to_string_loop("")
}

fn list_to_string_loop(values: List(Int), output: String) -> String {
  case values {
    [] -> output
    [first] -> output <> int.to_string(first)
    [first, ..rest] ->
      list_to_string_loop(rest, output <> int.to_string(first) <> ",")
  }
}
