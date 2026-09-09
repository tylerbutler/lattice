import gleam/int
import gleam/io
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_sequence/sequence

pub fn main() {
  let assert Ok(base) =
    sequence.new(replica_id.new("base")) |> sequence.insert(0, 1)

  let alice_id = replica_id.new("alice")
  let bob_id = replica_id.new("bob")
  let assert Ok(alice) =
    sequence.merge(sequence.new(alice_id), base, alice_id)
    |> sequence.insert(1, 2)

  let assert Ok(bob) =
    sequence.merge(sequence.new(bob_id), base, bob_id)
    |> sequence.insert(1, 3)
  let assert Ok(bob) = sequence.move(bob, 0, 1)

  sequence.merge(alice, bob, alice_id)
  |> sequence.values()
  |> list.map(int.to_string)
  |> string.join(",")
  |> io.println()
}
