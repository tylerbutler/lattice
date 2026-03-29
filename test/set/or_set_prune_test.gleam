import gleam/json
import lattice/or_set
import lattice/version_vector
import startest/expect

pub fn prune_removes_tombstones_test() {
  let s1 =
    or_set.new("A")
    |> or_set.add("item1")
    |> or_set.add("item2")
    |> or_set.remove("item1")
  // Creates tombstone for item1 (tag: A:1)

  // item2 is active (tag: A:2)
  // item1 is tombstoned (tag: A:1)

  // Verify item1 is gone from value
  or_set.contains(s1, "item1") |> expect.to_be_false()
  or_set.contains(s1, "item2") |> expect.to_be_true()

  // Create a stable vector that covers A:1 but not necessarily A:2
  let stable = version_vector.new() |> version_vector.increment("A")

  // Prune
  let s2 = or_set.prune(s1, stable)

  // Verify behavior is unchanged
  or_set.contains(s2, "item1") |> expect.to_be_false()
  or_set.contains(s2, "item2") |> expect.to_be_true()
  // Internally, the tombstone should be gone. 
  // We can't inspect tombstones directly via public API, 
  // but we can check JSON output or behavior against zombies.
}

pub fn prune_prevents_zombies_test() {
  // Scenario: Replica A has pruned "item1" (A:1). 
  // Replica B sends a merge request containing "item1" (A:1).
  // "item1" should NOT reappear.

  let s_pruned =
    or_set.new("A")
    |> or_set.add("item1")
    // A:1
    |> or_set.remove("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment("A"))
  // Prune A:1

  // Create a zombie set that looks like it has the old item
  // We simulate this by creating a fresh set from "A" and adding item1
  // Note: This will create A:1 because counter starts at 0
  let s_zombie =
    or_set.new("A")
    |> or_set.add("item1")
  // A:1

  // Merge zombie into pruned
  let merged = or_set.merge(s_pruned, s_zombie)

  // The zombie item (A:1) should be filtered out because pruned vector covers A:1
  or_set.contains(merged, "item1") |> expect.to_be_false()
}

pub fn active_items_survive_pruning_test() {
  // Even if an item is "covered" by the pruned vector, if it is active in the set,
  // it should remain active. Pruning only removes TOMBSTONES.

  let s =
    or_set.new("A")
    |> or_set.add("item1")
  // A:1

  // Prune with vector covering A:1
  let stable = version_vector.new() |> version_vector.increment("A")
  let s_pruned = or_set.prune(s, stable)

  // item1 should still be there
  or_set.contains(s_pruned, "item1") |> expect.to_be_true()
}

pub fn active_items_survive_pruning_after_merge_test() {
  let pruned =
    or_set.new("A")
    |> or_set.add("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment("A"))

  let stale = or_set.new("B")

  let merged = or_set.merge(pruned, stale)

  or_set.contains(merged, "item1") |> expect.to_be_true()
}

pub fn json_serialization_v2_test() {
  let s =
    or_set.new("A")
    |> or_set.add("item1")
    |> or_set.remove("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment("A"))

  let json_str = json.to_string(or_set.to_json(s))

  // Decode back
  let assert Ok(decoded) = or_set.from_json(json_str)

  // Behavior should be preserved (item1 is removed and pruned)
  or_set.contains(decoded, "item1") |> expect.to_be_false()

  // And it should reject zombies (proof that pruned vector was deserialized)
  let s_zombie = or_set.new("A") |> or_set.add("item1")
  // A:1
  let merged = or_set.merge(decoded, s_zombie)
  or_set.contains(merged, "item1") |> expect.to_be_false()
}
