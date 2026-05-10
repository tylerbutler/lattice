import gleam/io
import lattice_core/replica_id
import lattice_text/text

pub fn main() {
  let base = text.new(replica_id.new("base")) |> text.insert(0, "!")

  let alice =
    text.merge(text.new(replica_id.new("alice")), base)
    |> text.insert(0, "h")
    |> text.insert(1, "i")

  let bob =
    text.merge(text.new(replica_id.new("bob")), base)
    |> text.insert(0, "o")
    |> text.insert(1, "k")

  text.merge(alice, bob)
  |> text.value()
  |> io.println()
}
