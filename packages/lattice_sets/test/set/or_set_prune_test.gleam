import gleam/json
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sets/or_set
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn prune_removes_tombstones_test() {
  let s1 =
    or_set.new(rid("A"))
    |> or_set.add("item1")
    |> or_set.add("item2")
    |> or_set.remove("item1")

  or_set.contains(s1, "item1") |> expect.to_be_false()
  or_set.contains(s1, "item2") |> expect.to_be_true()

  // Stable vector covering A:1 but not A:2
  let stable = version_vector.new() |> version_vector.increment(rid("A"))

  let s2 = or_set.prune(s1, stable)

  // Behavior unchanged after prune
  or_set.contains(s2, "item1") |> expect.to_be_false()
  or_set.contains(s2, "item2") |> expect.to_be_true()
}

pub fn prune_prevents_zombies_test() {
  // Replica A prunes "item1" (A:1). A stale replica B sends A:1.
  // "item1" should NOT reappear.
  let s_pruned =
    or_set.new(rid("A"))
    |> or_set.add("item1")
    |> or_set.remove("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment(rid("A")))

  // Simulate zombie: fresh set where A adds item1 (creates tag A:1)
  let s_zombie =
    or_set.new(rid("A"))
    |> or_set.add("item1")

  let merged = or_set.merge(s_pruned, s_zombie)

  // Zombie tag (A:1) should be filtered out by pruned vector
  or_set.contains(merged, "item1") |> expect.to_be_false()
}

pub fn active_items_survive_pruning_test() {
  let s =
    or_set.new(rid("A"))
    |> or_set.add("item1")

  let stable = version_vector.new() |> version_vector.increment(rid("A"))
  let s_pruned = or_set.prune(s, stable)

  // Active items are not affected by pruning (pruning only removes tombstones)
  or_set.contains(s_pruned, "item1") |> expect.to_be_true()
}

pub fn active_items_survive_pruning_after_merge_test() {
  let pruned =
    or_set.new(rid("A"))
    |> or_set.add("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment(rid("A")))

  let stale = or_set.new(rid("B"))

  let merged = or_set.merge(pruned, stale)

  or_set.contains(merged, "item1") |> expect.to_be_true()
}

pub fn json_round_trip_v2_test() {
  let s =
    or_set.new(rid("A"))
    |> or_set.add("item1")
    |> or_set.remove("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment(rid("A")))

  let json_str = json.to_string(or_set.to_json(s))

  let assert Ok(decoded) = or_set.from_json(json_str)

  or_set.contains(decoded, "item1") |> expect.to_be_false()

  // Pruned vector should survive round-trip: zombie should be rejected
  let s_zombie = or_set.new(rid("A")) |> or_set.add("item1")
  let merged = or_set.merge(decoded, s_zombie)
  or_set.contains(merged, "item1") |> expect.to_be_false()
}
