import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/set
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sets/or_set

fn rid(id: String) {
  replica_id.new(id)
}

fn later_removal() {
  let original = or_set.new(rid("A")) |> or_set.add("item")
  let observed = or_set.merge(or_set.new(rid("B")), original)
  let stable = version_vector.new() |> version_vector.increment(rid("A"))
  let pruned = or_set.prune(original, stable)
  let #(removed, delta) = or_set.remove_with_delta(observed, "item")
  #(original, pruned, removed, delta)
}

pub fn later_removal_survives_live_tag_pruning_in_both_merge_orders_test() {
  let #(original, pruned, removed, _) = later_removal()
  list.each(
    [or_set.merge(pruned, removed), or_set.merge(removed, pruned)],
    fn(merged) {
      let assert False = or_set.contains(merged, "item")
      let assert True = or_set.value(merged) == set.new()
      let assert True = or_set.pruned_vv(merged) == or_set.pruned_vv(pruned)
      let assert True = or_set.merge(merged, merged) == merged
      let assert False =
        or_set.merge(merged, original) |> or_set.contains("item")
      let assert False =
        or_set.merge(original, merged) |> or_set.contains("item")

      let relayed = or_set.merge(or_set.new(rid("C")), merged)
      let assert False =
        or_set.merge(relayed, original) |> or_set.contains("item")
    },
  )
}

pub fn later_remove_delta_survives_pruning_and_replay_test() {
  let #(original, pruned, removed, delta) = later_removal()
  list.each(
    [or_set.merge(pruned, delta), or_set.merge(delta, pruned)],
    fn(merged) {
      let assert False = or_set.contains(merged, "item")
      let assert True = or_set.value(merged) == or_set.value(removed)
      let assert True = or_set.merge(merged, delta) == merged
      let assert False =
        or_set.merge(merged, original) |> or_set.contains("item")
    },
  )
}

pub fn later_removal_survives_pruned_json_round_trips_test() {
  let #(original, pruned, removed, delta) = later_removal()
  list.each([pruned, removed, delta, or_set.merge(pruned, removed)], fn(state) {
    let assert Ok(legacy) =
      state |> or_set.to_json |> json.to_string |> or_set.from_json
    let assert Ok(generic) =
      state
      |> or_set.to_json_with(json.string)
      |> json.to_string
      |> or_set.from_json_with(decode.string)
    list.each([legacy, generic], fn(loaded) {
      let assert True = loaded == state
      let merged = or_set.merge(pruned, loaded) |> or_set.merge(removed)
      let assert False = or_set.contains(merged, "item")
      let assert False =
        or_set.merge(merged, original) |> or_set.contains("item")
      let assert True = or_set.merge(merged, delta) == merged
    })
  })
}

pub fn later_removal_preserves_new_tags_and_associative_joins_test() {
  let #(original, pruned, removed, delta) = later_removal()
  let #(concurrent, fresh_delta) = or_set.add_with_delta(pruned, "item")
  list.each([concurrent, fresh_delta], fn(fresh) {
    let left = or_set.merge(or_set.merge(pruned, removed), fresh)
    let right = or_set.merge(pruned, or_set.merge(removed, fresh))
    let assert True = left == right
    let assert True = or_set.contains(left, "item")
    let assert True = or_set.merge(left, delta) == left
    let without_old = or_set.merge(or_set.merge(pruned, delta), fresh)
    let assert True = or_set.value(without_old) == or_set.value(left)
    let #(removed_again, remove_fresh) = or_set.remove_with_delta(left, "item")
    let assert False =
      or_set.merge(left, remove_fresh) |> or_set.contains("item")
    let assert False =
      or_set.merge(fresh, removed_again) |> or_set.contains("item")
    let assert False =
      or_set.merge(removed_again, original) |> or_set.contains("item")
  })

  let states = [original, pruned, removed, delta, concurrent, fresh_delta]
  list.each(states, fn(a) {
    list.each(states, fn(b) {
      list.each(states, fn(c) {
        let left = or_set.merge(or_set.merge(a, b), c)
        let right = or_set.merge(a, or_set.merge(b, c))
        let assert True = left == right
      })
    })
  })
}

pub fn prune_removes_tombstones_test() {
  let s1 =
    or_set.new(rid("A"))
    |> or_set.add("item1")
    |> or_set.add("item2")
    |> or_set.remove("item1")

  or_set.contains(s1, "item1")
  |> fn(actual) {
    let assert False = actual
    Nil
  }
  or_set.contains(s1, "item2")
  |> fn(actual) {
    let assert True = actual
    Nil
  }

  // Stable vector covering A:1 but not A:2
  let stable = version_vector.new() |> version_vector.increment(rid("A"))

  let s2 = or_set.prune(s1, stable)

  // Behavior unchanged after prune
  or_set.contains(s2, "item1")
  |> fn(actual) {
    let assert False = actual
    Nil
  }
  or_set.contains(s2, "item2")
  |> fn(actual) {
    let assert True = actual
    Nil
  }
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
  or_set.contains(merged, "item1")
  |> fn(actual) {
    let assert False = actual
    Nil
  }
}

pub fn active_items_survive_pruning_test() {
  let s =
    or_set.new(rid("A"))
    |> or_set.add("item1")

  let stable = version_vector.new() |> version_vector.increment(rid("A"))
  let s_pruned = or_set.prune(s, stable)

  // Active items are not affected by pruning (pruning only removes tombstones)
  or_set.contains(s_pruned, "item1")
  |> fn(actual) {
    let assert True = actual
    Nil
  }
}

pub fn active_items_survive_pruning_after_merge_test() {
  let pruned =
    or_set.new(rid("A"))
    |> or_set.add("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment(rid("A")))

  let stale = or_set.new(rid("B"))

  let merged = or_set.merge(pruned, stale)

  or_set.contains(merged, "item1")
  |> fn(actual) {
    let assert True = actual
    Nil
  }
}

pub fn json_round_trip_v2_test() {
  let s =
    or_set.new(rid("A"))
    |> or_set.add("item1")
    |> or_set.remove("item1")
    |> or_set.prune(version_vector.new() |> version_vector.increment(rid("A")))

  let json_str = json.to_string(or_set.to_json(s))

  let assert Ok(decoded) = or_set.from_json(json_str)

  or_set.contains(decoded, "item1")
  |> fn(actual) {
    let assert False = actual
    Nil
  }

  // Pruned vector should survive round-trip: zombie should be rejected
  let s_zombie = or_set.new(rid("A")) |> or_set.add("item1")
  let merged = or_set.merge(decoded, s_zombie)
  or_set.contains(merged, "item1")
  |> fn(actual) {
    let assert False = actual
    Nil
  }
}
