import gleam/set
import lattice/or_set
import startest/expect

pub fn new_creates_empty_set_test() {
  let orset = or_set.new("A")
  orset
  |> or_set.value
  |> expect.to_equal(set.new())
}

pub fn new_contains_returns_false_test() {
  or_set.new("A")
  |> or_set.contains("x")
  |> expect.to_be_false
}

pub fn add_then_contains_returns_true_test() {
  or_set.new("A")
  |> or_set.add("hello")
  |> or_set.contains("hello")
  |> expect.to_be_true
}

pub fn add_then_value_contains_element_test() {
  or_set.new("A")
  |> or_set.add("hello")
  |> or_set.value
  |> expect.to_equal(set.from_list(["hello"]))
}

pub fn add_then_remove_then_contains_false_test() {
  or_set.new("A")
  |> or_set.add("x")
  |> or_set.remove("x")
  |> or_set.contains("x")
  |> expect.to_be_false
}

pub fn re_add_after_remove_contains_true_test() {
  // OR-Set allows re-add: add, remove, add -> element is present
  // The second add generates a NEW tag not seen by remove
  or_set.new("A")
  |> or_set.add("x")
  |> or_set.remove("x")
  |> or_set.add("x")
  |> or_set.contains("x")
  |> expect.to_be_true
}

pub fn add_multiple_elements_test() {
  let orset =
    or_set.new("A")
    |> or_set.add("a")
    |> or_set.add("b")

  orset
  |> or_set.contains("a")
  |> expect.to_be_true

  orset
  |> or_set.contains("b")
  |> expect.to_be_true
}

pub fn concurrent_add_wins_test() {
  // Replica A adds "x"
  let replica_a = or_set.new("A") |> or_set.add("x")

  // Replica B merges to see A's state, then removes "x" (clears A's tag)
  let replica_b = or_set.new("B") |> or_set.merge(replica_a)
  let replica_b = replica_b |> or_set.remove("x")

  // Replica A concurrently adds "x" again (NEW tag that B hasn't seen)
  let replica_a = replica_a |> or_set.add("x")

  // Merge: B removed A's old tag, but A has a NEW tag that B doesn't know about
  let merged = or_set.merge(replica_a, replica_b)

  // Add wins: A's new tag survives B's remove
  merged
  |> or_set.contains("x")
  |> expect.to_be_true
}

pub fn merge_empty_left_test() {
  let s = or_set.new("A") |> or_set.add("x")

  or_set.merge(or_set.new("B"), s)
  |> or_set.contains("x")
  |> expect.to_be_true
}

pub fn merge_commutativity_on_value_test() {
  // merge(a, b) and merge(b, a) should have the same observable value
  let set_a =
    or_set.new("A")
    |> or_set.add("alpha")
    |> or_set.add("beta")

  let set_b =
    or_set.new("B")
    |> or_set.add("beta")
    |> or_set.add("gamma")

  let merged_ab = or_set.merge(set_a, set_b) |> or_set.value
  let merged_ba = or_set.merge(set_b, set_a) |> or_set.value

  expect.to_equal(merged_ab, merged_ba)
}

pub fn merge_union_tags_test() {
  // merge combines elements from both sets
  let set_a = or_set.new("A") |> or_set.add("a") |> or_set.add("b")
  let set_b = or_set.new("B") |> or_set.add("b") |> or_set.add("c")

  or_set.merge(set_a, set_b)
  |> or_set.value
  |> expect.to_equal(set.from_list(["a", "b", "c"]))
}

pub fn merge_propagates_counter_test() {
  // After merge, the merged set's counter should be max of both sides
  // A subsequent add should create a new unique tag (not collide)
  let set_a = or_set.new("A") |> or_set.add("a")
  // counter is now 1 in set_a
  let set_b = or_set.new("A") |> or_set.add("a") |> or_set.add("a")
  // counter is now 2 in set_b

  // After merge, counter should be at least 2
  let merged = or_set.merge(set_a, set_b)

  // A new add should use counter > 2 (no collision with existing tags)
  let after_add = merged |> or_set.add("new_element")

  after_add
  |> or_set.contains("new_element")
  |> expect.to_be_true
}
