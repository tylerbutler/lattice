import lattice_core/replica_id
import lattice_text/text
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_value_is_empty_test() {
  text.new(rid("A"))
  |> text.value()
  |> expect.to_equal("")
}

pub fn new_values_is_empty_test() {
  text.new(rid("A"))
  |> text.values()
  |> expect.to_equal([])
}

pub fn insert_into_empty_text_test() {
  text.new(rid("A"))
  |> text.insert(0, "h")
  |> text.value()
  |> expect.to_equal("h")
}

pub fn insert_appends_at_end_test() {
  text.new(rid("A"))
  |> text.insert(0, "h")
  |> text.insert(1, "i")
  |> text.value()
  |> expect.to_equal("hi")
}

pub fn insert_in_middle_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> text.insert(1, "c")
  |> text.insert(1, "b")
  |> text.value()
  |> expect.to_equal("abc")
}

pub fn try_insert_negative_index_returns_error_test() {
  text.new(rid("A"))
  |> text.try_insert(-1, "x")
  |> expect.to_equal(Error(text.IndexOutOfBounds(index: -1, length: 0)))
}

pub fn try_insert_past_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> text.try_insert(2, "x")
  |> expect.to_equal(Error(text.IndexOutOfBounds(index: 2, length: 1)))
}

pub fn delete_removes_visible_unit_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> text.insert(1, "b")
  |> text.insert(2, "c")
  |> text.delete(1)
  |> text.value()
  |> expect.to_equal("ac")
}

pub fn try_delete_negative_index_returns_error_test() {
  text.new(rid("A"))
  |> text.try_delete(-1)
  |> expect.to_equal(Error(text.DeleteIndexOutOfBounds(index: -1, length: 0)))
}

pub fn try_delete_at_end_returns_error_test() {
  text.new(rid("A"))
  |> text.insert(0, "a")
  |> text.try_delete(1)
  |> expect.to_equal(Error(text.DeleteIndexOutOfBounds(index: 1, length: 1)))
}

pub fn merge_concurrent_insert_same_position_is_deterministic_test() {
  let base = text.new(rid("A")) |> text.insert(0, "a") |> text.insert(1, "c")
  let alice = text.merge(text.new(rid("alice")), base) |> text.insert(1, "b")
  let bob = text.merge(text.new(rid("bob")), base) |> text.insert(1, "X")

  let ab = text.merge(alice, bob) |> text.value()
  let ba = text.merge(bob, alice) |> text.value()

  ab |> expect.to_equal(ba)
  ab |> expect.to_equal("abXc")
}

pub fn merge_delete_and_insert_after_deleted_anchor_test() {
  let base =
    text.new(rid("A"))
    |> text.insert(0, "a")
    |> text.insert(1, "b")
    |> text.insert(2, "c")

  let alice = base |> text.delete(1)
  let bob = text.merge(text.new(rid("B")), base) |> text.insert(2, "Y")

  text.merge(alice, bob)
  |> text.value()
  |> expect.to_equal("aYc")
}

pub fn merge_concurrent_runs_do_not_interleave_for_forward_typing_test() {
  let base = text.new(rid("base")) |> text.insert(0, "_")
  let alice =
    text.merge(text.new(rid("alice")), base)
    |> text.insert(1, "m")
    |> text.insert(2, "o")
    |> text.insert(3, "m")
  let bob =
    text.merge(text.new(rid("bob")), base)
    |> text.insert(1, "d")
    |> text.insert(2, "a")
    |> text.insert(3, "d")

  text.merge(alice, bob)
  |> text.value()
  |> expect.to_equal("_momdad")
}

pub fn merge_applies_insert_delta_test() {
  let base = text.new(rid("A"))
  let #(updated, delta) = text.insert_with_delta(base, 0, "x")

  text.merge(base, delta)
  |> expect.to_equal(updated)
}

pub fn merge_applies_delete_delta_test() {
  let base = text.new(rid("A")) |> text.insert(0, "x")
  let #(updated, delta) = text.delete_with_delta(base, 0)

  text.merge(base, delta)
  |> expect.to_equal(updated)
}
