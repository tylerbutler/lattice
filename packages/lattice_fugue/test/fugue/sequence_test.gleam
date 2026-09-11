import gleam/list
import gleam/result
import lattice_core/replica_id
import lattice_fugue/sequence

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_values_is_empty_test() {
  sequence.new(rid("A"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == []
  }
}

pub fn new_length_is_zero_test() {
  sequence.new(rid("A"))
  |> sequence.length()
  |> fn(actual) {
    assert actual == 0
  }
}

pub fn insert_into_empty_sequence_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, 42)
  |> result.map(sequence.values)
  |> fn(actual) {
    assert actual == Ok([42])
  }
}

pub fn insert_appends_at_end_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "h")
  |> result.try(sequence.insert(_, 1, "i"))
  |> result.map(sequence.values)
  |> fn(actual) {
    assert actual == Ok(["h", "i"])
  }
}

pub fn insert_in_middle_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> result.try(sequence.insert(_, 1, "c"))
  |> result.try(sequence.insert(_, 1, "b"))
  |> result.map(sequence.values)
  |> fn(actual) {
    assert actual == Ok(["a", "b", "c"])
  }
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
  |> fn(actual) {
    assert actual == Ok(["a", "b", "c"])
  }
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
  |> fn(actual) {
    assert actual == Ok(["a", "h", "g", "b", "c"])
  }
}

pub fn length_counts_visible_values_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> result.try(sequence.insert(_, 1, "b"))
  |> result.try(sequence.insert(_, 2, "c"))
  |> result.map(sequence.length)
  |> fn(actual) {
    assert actual == Ok(3)
  }
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
  |> fn(actual) {
    assert actual == Ok(["a", "c"])
  }
}

pub fn delete_reduces_length_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
  seq
  |> sequence.delete(0)
  |> result.map(sequence.length)
  |> fn(actual) {
    assert actual == Ok(1)
  }
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
  |> fn(actual) {
    assert actual == Ok(["c", "a"])
  }
}

pub fn insert_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert_with_delta(-1, "x")
  |> fn(actual) {
    assert actual == Error(sequence.IndexOutOfBounds(index: -1, length: 0))
  }
}

pub fn insert_past_end_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert(0, "a")
  |> result.try(sequence.insert_with_delta(_, 2, "x"))
  |> fn(actual) {
    assert actual == Error(sequence.IndexOutOfBounds(index: 2, length: 1))
  }
}

pub fn delete_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.delete_with_delta(-1)
  |> fn(actual) {
    assert actual
      == Error(sequence.DeleteIndexOutOfBounds(index: -1, length: 0))
  }
}

pub fn delete_out_of_range_returns_error_test() {
  let assert Ok(seq) = sequence.new(rid("A")) |> sequence.insert(0, "a")
  seq
  |> sequence.delete_with_delta(1)
  |> fn(actual) {
    assert actual == Error(sequence.DeleteIndexOutOfBounds(index: 1, length: 1))
  }
}

// A delta from insert can be merged into another replica to replicate a single
// operation without full-state sync.
pub fn insert_delta_replicates_single_node_test() {
  let base = sequence.new(rid("A"))
  let assert Ok(#(_updated, delta)) = sequence.insert_with_delta(base, 0, "x")
  let other = sequence.new(rid("B"))
  sequence.merge(other, delta, rid("B"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == ["x"]
  }
}

pub fn concurrent_insert_unicode_order_and_anchor_test() {
  let assert Ok(bmp) = sequence.new(rid("\u{e000}")) |> sequence.insert(0, "b")
  let assert Ok(supplementary) =
    sequence.new(rid("\u{10000}")) |> sequence.insert(0, "s")
  let assert Ok(anchor) = sequence.anchor_at(bmp, 0, sequence.Before)
  let local = rid("local")

  [
    sequence.merge(bmp, supplementary, local),
    sequence.merge(supplementary, bmp, local),
  ]
  |> list.each(fn(merged) {
    sequence.values(merged)
    |> fn(actual) {
      assert actual == ["b", "s"]
    }
    sequence.resolve(merged, anchor)
    |> fn(actual) {
      assert actual == Ok(0)
    }
  })
}

pub fn concurrent_insert_delta_unicode_order_test() {
  let bmp_id = rid("\u{e000}")
  let supplementary_id = rid("\u{10000}")
  let assert Ok(#(bmp, bmp_delta)) =
    sequence.new(bmp_id) |> sequence.insert_with_delta(0, "b")
  let assert Ok(#(supplementary, supplementary_delta)) =
    sequence.new(supplementary_id) |> sequence.insert_with_delta(0, "s")
  let assert Ok(anchor) = sequence.anchor_at(bmp, 0, sequence.Before)
  let local = rid("local")
  let empty = sequence.new(local)

  [
    sequence.merge(bmp, supplementary_delta, bmp_id),
    sequence.merge(supplementary_delta, bmp, bmp_id),
    sequence.merge(supplementary, bmp_delta, supplementary_id),
    sequence.merge(bmp_delta, supplementary, supplementary_id),
    empty
      |> sequence.merge(bmp_delta, local)
      |> sequence.merge(supplementary_delta, local),
    empty
      |> sequence.merge(supplementary_delta, local)
      |> sequence.merge(bmp_delta, local),
  ]
  |> list.each(fn(merged) {
    sequence.values(merged)
    |> fn(actual) {
      assert actual == ["b", "s"]
    }
    sequence.resolve(merged, anchor)
    |> fn(actual) {
      assert actual == Ok(0)
    }
  })
}

pub fn state_only_edits_preserve_errors_test() {
  let empty = sequence.new(rid("A"))
  sequence.insert(empty, -1, "x")
  |> fn(actual) {
    assert actual == Error(sequence.IndexOutOfBounds(-1, 0))
  }
  sequence.insert(empty, 1, "x")
  |> fn(actual) {
    assert actual == Error(sequence.IndexOutOfBounds(1, 0))
  }
  sequence.delete(empty, 0)
  |> fn(actual) {
    assert actual == Error(sequence.DeleteIndexOutOfBounds(0, 0))
  }
  sequence.delete(empty, -1)
  |> fn(actual) {
    assert actual == Error(sequence.DeleteIndexOutOfBounds(-1, 0))
  }
  let assert Ok(base) = sequence.insert(empty, 0, "a")
  sequence.insert(base, 2, "x")
  |> fn(actual) {
    assert actual == Error(sequence.IndexOutOfBounds(2, 1))
  }
  sequence.delete(base, 1)
  |> fn(actual) {
    assert actual == Error(sequence.DeleteIndexOutOfBounds(1, 1))
  }
  sequence.values(base)
  |> fn(actual) {
    assert actual == ["a"]
  }
}

pub fn state_only_edits_match_delta_results_test() {
  let base = sequence.new(rid("A"))
  let assert Ok(#(inserted, _)) = sequence.insert_with_delta(base, 0, "a")
  sequence.insert(base, 0, "a")
  |> fn(actual) {
    assert actual == Ok(inserted)
  }
  let assert Ok(#(deleted, _)) = sequence.delete_with_delta(inserted, 0)
  sequence.delete(inserted, 0)
  |> fn(actual) {
    assert actual == Ok(deleted)
  }
}
