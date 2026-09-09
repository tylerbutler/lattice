import gleam/result
import lattice_core/replica_id
import lattice_fugue/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_values_is_empty_test() {
  sequence.new(rid("A"))
  |> sequence.values()
  |> expect.to_equal([])
}

pub fn new_length_is_zero_test() {
  sequence.new(rid("A"))
  |> sequence.length()
  |> expect.to_equal(0)
}

pub fn insert_into_empty_sequence_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, 42)
  |> result.map(sequence.values)
  |> expect.to_equal(Ok([42]))
}

pub fn insert_appends_at_end_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "h")
  |> result.try(sequence.insert(_, 1, "i"))
  |> result.map(sequence.values)
  |> expect.to_equal(Ok(["h", "i"]))
}

pub fn insert_in_middle_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> result.try(sequence.insert(_, 1, "c"))
  |> result.try(sequence.insert(_, 1, "b"))
  |> result.map(sequence.values)
  |> expect.to_equal(Ok(["a", "b", "c"]))
}

// Repeated prepend at index 0 keeps insertion order reversed and contiguous,
// exercising the root-right-child then left-chain construction (Figure 2's
// "prepend" scenario).
pub fn repeated_prepend_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "c")
  |> result.try(sequence.insert(_, 0, "b"))
  |> result.try(sequence.insert(_, 0, "a"))
  |> result.map(sequence.values)
  |> expect.to_equal(Ok(["a", "b", "c"]))
}

// Figure 3/4 behavior: inserting between two items where the left item has a
// right child attaches the new node as a left child of the successor, keeping
// the visible order correct.
pub fn insert_between_when_left_has_right_child_test() {
  // Build a,b,c so that after these appends the tree has right-children.
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
    |> result.try(sequence.insert(_, 2, "c"))
  // Insert g between a and b, then h between a and g.
  seq
  |> sequence.insert(1, "g")
  |> result.try(sequence.insert(_, 1, "h"))
  |> result.map(sequence.values)
  |> expect.to_equal(Ok(["a", "h", "g", "b", "c"]))
}

pub fn length_counts_visible_values_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> result.try(sequence.insert(_, 1, "b"))
  |> result.try(sequence.insert(_, 2, "c"))
  |> result.map(sequence.length)
  |> expect.to_equal(Ok(3))
}

pub fn delete_removes_visible_item_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
    |> result.try(sequence.insert(_, 2, "c"))
  seq
  |> sequence.delete(1)
  |> result.map(sequence.values)
  |> expect.to_equal(Ok(["a", "c"]))
}

pub fn delete_reduces_length_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
  seq
  |> sequence.delete(0)
  |> result.map(sequence.length)
  |> expect.to_equal(Ok(1))
}

// Deleting an item that is an ancestor of live nodes keeps the tombstone in
// place; the descendants remain visible and correctly ordered.
pub fn delete_ancestor_keeps_descendants_test() {
  // "a" is inserted first, then "b" prepended so a becomes a's right subtree;
  // deleting the first visible element must not disturb the rest.
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 0, "b"))
    |> result.try(sequence.insert(_, 0, "c"))
  // values == ["c","b","a"]; delete "b" (index 1)
  seq
  |> sequence.delete(1)
  |> result.map(sequence.values)
  |> expect.to_equal(Ok(["c", "a"]))
}

pub fn insert_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert_with_delta(-1, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: -1, length: 0)))
}

pub fn insert_past_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> result.try(sequence.insert_with_delta(_, 2, "x"))
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(index: 2, length: 1)))
}

pub fn delete_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.delete_with_delta(-1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: -1, length: 0)),
  )
}

pub fn delete_out_of_range_returns_error_test() {
  let assert Ok(seq) = sequence.new(rid("A")) |> sequence.insert(0, "a")
  seq
  |> sequence.delete_with_delta(1)
  |> expect.to_equal(
    Error(sequence.DeleteIndexOutOfBounds(index: 1, length: 1)),
  )
}

// A delta from insert can be merged into another replica to replicate a single
// operation without full-state sync.
pub fn insert_delta_replicates_single_node_test() {
  let base = sequence.new(rid("A"))
  let assert Ok(#(_updated, delta)) = sequence.insert_with_delta(base, 0, "x")
  let other = sequence.new(rid("B"))
  sequence.merge(other, delta, rid("B"))
  |> sequence.values()
  |> expect.to_equal(["x"])
}

pub fn state_only_edits_preserve_errors_test() {
  let empty = sequence.new(rid("A"))
  sequence.insert(empty, -1, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(-1, 0)))
  sequence.insert(empty, 1, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(1, 0)))
  sequence.delete(empty, 0)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(0, 0)))
  sequence.delete(empty, -1)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(-1, 0)))
  let assert Ok(base) = sequence.insert(empty, 0, "a")
  sequence.insert(base, 2, "x")
  |> expect.to_equal(Error(sequence.IndexOutOfBounds(2, 1)))
  sequence.delete(base, 1)
  |> expect.to_equal(Error(sequence.DeleteIndexOutOfBounds(1, 1)))
  sequence.values(base) |> expect.to_equal(["a"])
}

pub fn state_only_edits_match_delta_results_test() {
  let base = sequence.new(rid("A"))
  let assert Ok(#(inserted, _)) = sequence.insert_with_delta(base, 0, "a")
  sequence.insert(base, 0, "a") |> expect.to_equal(Ok(inserted))
  let assert Ok(#(deleted, _)) = sequence.delete_with_delta(inserted, 0)
  sequence.delete(inserted, 0) |> expect.to_equal(Ok(deleted))
}
