import gleam/io
import lattice_core/replica_id
import lattice_text/text

pub fn main() {
  let assert Ok(base) = text.new(replica_id.new("base")) |> text.insert(0, "!")

  let alice_id = replica_id.new("alice")
  let bob_id = replica_id.new("bob")
  let assert Ok(alice) =
    text.merge(text.new(alice_id), base, alice_id)
    |> text.insert(0, "h")
  let assert Ok(alice) = text.insert(alice, 1, "i")

  let assert Ok(bob) =
    text.merge(text.new(bob_id), base, bob_id)
    |> text.insert(0, "o")
  let assert Ok(bob) = text.insert(bob, 1, "k")

  text.merge(alice, bob, alice_id)
  |> text.value()
  |> io.println()
}
