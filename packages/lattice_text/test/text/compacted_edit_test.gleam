import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_text/text

pub fn compacted_text_edits_replay_on_uncompacted_receiver_test() -> Nil {
  let a = replica_id.new("A")
  let b = replica_id.new("B")
  let assert Ok(base) = text.insert(text.new(b), 0, "LXW")
  let base = text.merge(text.new(a), base, a)
  let assert Ok(base) = text.insert(base, 1, "P")
  let stable =
    version_vector.new()
    |> version_vector.set_max(a, 4)
    |> version_vector.set_max(b, 3)
  let #(sender, _) = text.compact(text.merge(text.new(b), base, b), stable)
  let assert Ok(#(deleted, deletion)) = text.delete_with_delta(sender, 2)
  let assert Ok(#(moved, movement)) = text.move_with_delta(sender, 2, 0)
  let assert Ok(#(range_deleted, range_deletion)) =
    text.delete_range_with_delta(sender, 1, 3)
  let assert Ok(#(replaced, replacement)) =
    text.replace_range_with_delta(sender, 1, 3, "YZ")
  list.each(
    [
      #(deleted, deletion, "LPW"),
      #(moved, movement, "XLPW"),
      #(range_deleted, range_deletion, "LW"),
      #(replaced, replacement, "LYZW"),
    ],
    fn(edit) {
      let #(sender, delta, expected) = edit
      let assert Ok(decoded) =
        delta |> text.to_json() |> json.to_string() |> text.from_json()
      list.each([delta, decoded, sender], fn(incoming) {
        let receiver = text.merge(base, incoming, a)
        assert text.value(receiver) == expected
        assert text.merge(incoming, base, a) == receiver
        let #(receiver, _) = text.compact(receiver, stable)
        assert text.value(text.merge(receiver, sender, a)) == expected
        assert text.merge(receiver, sender, a)
          == text.merge(sender, receiver, a)
      })
    },
  )
}
