import gleam/set
import lattice/two_p_set
import startest/expect

pub fn new_creates_empty_set_test() {
  two_p_set.new()
  |> two_p_set.value
  |> expect.to_equal(set.new())
}

pub fn new_contains_returns_false_test() {
  two_p_set.new()
  |> two_p_set.contains("a")
  |> expect.to_be_false
}

pub fn add_then_contains_returns_true_test() {
  two_p_set.new()
  |> two_p_set.add("hello")
  |> two_p_set.contains("hello")
  |> expect.to_be_true
}

pub fn add_then_remove_then_contains_returns_false_test() {
  two_p_set.new()
  |> two_p_set.add("hello")
  |> two_p_set.remove("hello")
  |> two_p_set.contains("hello")
  |> expect.to_be_false
}

pub fn value_returns_added_minus_removed_test() {
  two_p_set.new()
  |> two_p_set.add("a")
  |> two_p_set.add("b")
  |> two_p_set.remove("b")
  |> two_p_set.value
  |> expect.to_equal(set.from_list(["a"]))
}

pub fn tombstone_is_permanent_test() {
  // add("x") -> remove("x") -> add("x") -- "x" should still be False
  two_p_set.new()
  |> two_p_set.add("x")
  |> two_p_set.remove("x")
  |> two_p_set.add("x")
  |> two_p_set.contains("x")
  |> expect.to_be_false
}

pub fn remove_without_prior_add_blocks_future_add_test() {
  // Pre-tombstone: remove before add; subsequent add is blocked
  two_p_set.new()
  |> two_p_set.remove("z")
  |> two_p_set.add("z")
  |> two_p_set.contains("z")
  |> expect.to_be_false
}

pub fn merge_unions_added_and_removed_sets_test() {
  // set_a: added={"a","b"}, removed={"b"}
  let set_a =
    two_p_set.new()
    |> two_p_set.add("a")
    |> two_p_set.add("b")
    |> two_p_set.remove("b")

  // set_b: added={"b","c"}, removed={}
  let set_b =
    two_p_set.new()
    |> two_p_set.add("b")
    |> two_p_set.add("c")

  // merged: added={"a","b","c"}, removed={"b"} -> value = {"a","c"}
  two_p_set.merge(set_a, set_b)
  |> two_p_set.value
  |> expect.to_equal(set.from_list(["a", "c"]))
}

pub fn merge_empty_left_test() {
  let s = two_p_set.new() |> two_p_set.add("x")

  two_p_set.merge(two_p_set.new(), s)
  |> two_p_set.value
  |> expect.to_equal(set.from_list(["x"]))
}

pub fn merge_empty_right_test() {
  let s = two_p_set.new() |> two_p_set.add("x")

  two_p_set.merge(s, two_p_set.new())
  |> two_p_set.value
  |> expect.to_equal(set.from_list(["x"]))
}
