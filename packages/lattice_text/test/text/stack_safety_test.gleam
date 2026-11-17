import gleam/json
import gleam/string
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import lattice_text/text

pub fn large_text_delegates_deletes_moves_and_reads_without_stack_growth_test() {
  let replica = replica_id.new("A")
  let middle = string.repeat("x", 19_998)
  let assert Ok(base) = text.insert(text.new(replica), 0, "a" <> middle <> "z")
  let assert Ok(deleted) = text.delete(base, 19_999)
  assert text.value(deleted) == "a" <> middle
  // Compaction keeps the long scans but avoids the volatile move rebuild.
  let floor = version_vector.new() |> version_vector.set_max(replica, 20_000)
  let #(base, _) = text.compact(base, floor)
  let assert Ok(last_to_first) = text.move(base, 19_999, 0)
  assert text.value(last_to_first) == "za" <> middle
  let assert Ok(moved) = text.move(base, 0, 19_999)
  assert text.value(moved) == middle <> "za"
  let assert Ok(anchor) = text.anchor_at(moved, 19_999, sequence.Before)
  let assert Ok(decoded) =
    text.to_json(moved) |> json.to_string() |> text.from_json()
  assert decoded == moved
  let assert Ok(inserted) = text.insert(decoded, 19_999, "!")
  assert text.value(inserted) == middle <> "z!a"
  assert text.resolve_anchor(inserted, anchor) == Ok(20_000)
}
