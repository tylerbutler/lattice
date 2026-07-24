import gleam/int
import gleam/io
import gleam/list
import gleam/string
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
  |> list.map(int.to_string)
  |> string.join(",")
  |> io.println()
}
