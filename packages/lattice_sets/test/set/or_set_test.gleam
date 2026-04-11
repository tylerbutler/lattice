import gleam/set
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sets/or_set
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_creates_empty_set_test() {
  let orset = or_set.new(rid("A"))
  orset
  |> or_set.value
  |> expect.to_equal(set.new())
}

pub fn new_contains_returns_false_test() {
  or_set.new(rid("A"))
  |> or_set.contains("x")
  |> expect.to_be_false
}

pub fn add_then_contains_returns_true_test() {
  or_set.new(rid("A"))
  |> or_set.add("hello")
  |> or_set.contains("hello")
  |> expect.to_be_true
}

pub fn add_then_value_contains_element_test() {
  or_set.new(rid("A"))
  |> or_set.add("hello")
  |> or_set.value
  |> expect.to_equal(set.from_list(["hello"]))
}

pub fn add_then_remove_then_contains_false_test() {
  or_set.new(rid("A"))
  |> or_set.add("x")
  |> or_set.remove("x")
  |> or_set.contains("x")
  |> expect.to_be_false
}

pub fn re_add_after_remove_contains_true_test() {
  // OR-Set allows re-add: add, remove, add -> element is present
  // The second add generates a NEW tag not seen by remove
  or_set.new(rid("A"))
  |> or_set.add("x")
  |> or_set.remove("x")
  |> or_set.add("x")
  |> or_set.contains("x")
  |> expect.to_be_true
}

pub fn add_multiple_elements_test() {
  let orset =
    or_set.new(rid("A"))
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
  let replica_a = or_set.new(rid("A")) |> or_set.add("x")

  // Replica B merges to see A's state, then removes "x" (clears A's tag)
  let replica_b = or_set.new(rid("B")) |> or_set.merge(replica_a)
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

pub fn stale_replica_does_not_resurrect_removed_element_test() {
  let original = or_set.new(rid("A")) |> or_set.add("x")
  let removed =
    or_set.new(rid("B"))
    |> or_set.merge(original)
    |> or_set.remove("x")

  or_set.merge(original, removed)
  |> or_set.contains("x")
  |> expect.to_be_false
}

pub fn merge_empty_left_test() {
  let s = or_set.new(rid("A")) |> or_set.add("x")

  or_set.merge(or_set.new(rid("B")), s)
  |> or_set.contains("x")
  |> expect.to_be_true
}

pub fn merge_commutativity_on_value_test() {
  // merge(a, b) and merge(b, a) should have the same observable value
  let set_a =
    or_set.new(rid("A"))
    |> or_set.add("alpha")
    |> or_set.add("beta")

  let set_b =
    or_set.new(rid("B"))
    |> or_set.add("beta")
    |> or_set.add("gamma")

  let merged_ab = or_set.merge(set_a, set_b) |> or_set.value
  let merged_ba = or_set.merge(set_b, set_a) |> or_set.value

  expect.to_equal(merged_ab, merged_ba)
}

pub fn merge_union_tags_test() {
  // merge combines elements from both sets
  let set_a = or_set.new(rid("A")) |> or_set.add("a") |> or_set.add("b")
  let set_b = or_set.new(rid("B")) |> or_set.add("b") |> or_set.add("c")

  or_set.merge(set_a, set_b)
  |> or_set.value
  |> expect.to_equal(set.from_list(["a", "b", "c"]))
}

pub fn merge_propagates_counter_test() {
  // After merge, the merged set's counter should be max of both sides
  // A subsequent add should create a new unique tag (not collide)
  let set_a = or_set.new(rid("A")) |> or_set.add("a")
  // counter is now 1 in set_a
  let set_b = or_set.new(rid("A")) |> or_set.add("a") |> or_set.add("a")
  // counter is now 2 in set_b

  // After merge, counter should be at least 2
  let merged = or_set.merge(set_a, set_b)

  // A new add should use counter > 2 (no collision with existing tags)
  let after_add = merged |> or_set.add("new_element")

  after_add
  |> or_set.contains("new_element")
  |> expect.to_be_true
}

// --- remove_with_bound ---

pub fn remove_with_bound_single_tag_test() {
  // A adds "x" (tag A:1), then removes with bound → bound should be {A: 1}
  let s = or_set.new(rid("A")) |> or_set.add("x")
  let #(updated, bound) = or_set.remove_with_bound(s, "x")

  or_set.contains(updated, "x") |> expect.to_be_false()
  version_vector.get(bound, rid("A")) |> expect.to_equal(1)
}

pub fn remove_with_bound_multi_tag_takes_max_test() {
  // A adds "x" twice (tags A:1 and A:2), remove bound should be {A: 2}
  let s =
    or_set.new(rid("A"))
    |> or_set.add("x")
    |> or_set.add("x")
  let #(updated, bound) = or_set.remove_with_bound(s, "x")

  or_set.contains(updated, "x") |> expect.to_be_false()
  version_vector.get(bound, rid("A")) |> expect.to_equal(2)
}

pub fn remove_with_bound_missing_element_returns_empty_bound_test() {
  let s = or_set.new(rid("A"))
  let #(updated, bound) = or_set.remove_with_bound(s, "x")

  or_set.contains(updated, "x") |> expect.to_be_false()
  version_vector.is_empty(bound) |> expect.to_be_true()
}

pub fn remove_with_bound_multi_replica_tags_test() {
  // A adds "x" (A:1), B adds "x" (B:1), merge, then remove
  // Bound should be {A: 1, B: 1}
  let sa = or_set.new(rid("A")) |> or_set.add("x")
  let sb = or_set.new(rid("B")) |> or_set.add("x")
  let merged = or_set.merge(sa, sb)

  let #(updated, bound) = or_set.remove_with_bound(merged, "x")
  or_set.contains(updated, "x") |> expect.to_be_false()
  version_vector.get(bound, rid("A")) |> expect.to_equal(1)
  version_vector.get(bound, rid("B")) |> expect.to_equal(1)
}

// --- pruned_vv ---

pub fn pruned_vv_new_set_is_empty_test() {
  or_set.new(rid("A"))
  |> or_set.pruned_vv()
  |> version_vector.is_empty()
  |> expect.to_be_true()
}

pub fn pruned_vv_after_prune_reflects_stable_vv_test() {
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))

  let s =
    or_set.new(rid("A"))
    |> or_set.add("x")
    |> or_set.remove("x")
    |> or_set.prune(stable)

  let pruned = or_set.pruned_vv(s)
  version_vector.get(pruned, rid("A")) |> expect.to_equal(1)
}
