import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_sequence/sequence
import support/composition_fixture as fixture

fn rid(value) {
  replica_id.new(value)
}

fn increment(map: or_map.ORMap(Int), amount: Int) {
  let assert Ok(pair) =
    or_map.update_delta(map, "count", fn(value, _) {
      let assert crdt.CrdtGCounter(value) = value
      let assert Ok(#(_, delta)) = g_counter.increment_with_delta(value, amount)
      Ok(crdt.StateDelta(crdt.CrdtGCounter(delta)))
    })
  pair
}

fn count(map) {
  let assert Ok(crdt.CrdtGCounter(value)) = or_map.get(map, "count")
  g_counter.value(value)
}

pub fn joining_replica_counter_edits_use_receiving_identity_test() {
  let #(a, _) = increment(or_map.new(rid("A"), crdt.GCounterSpec), 5)
  let assert Ok(b) = or_map.merge(or_map.new(rid("B"), crdt.GCounterSpec), a)
  let #(a, _) = increment(a, 1)
  let #(b, delta) = increment(b, 2)
  let assert Ok(merged) = or_map.merge(a, b)
  let assert Ok(applied) = or_map.apply_delta(a, delta)
  count(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 8
  }
  applied
  |> fn(assertion_actual) {
    let assert True = assertion_actual == merged
  }
}

pub fn same_replica_fresh_generation_survives_snapshot_prune_and_stale_delivery_test() {
  let #(old, old_delta) =
    increment(or_map.new(rid("A"), crdt.GCounterSpec), 100)
  let removed = or_map.remove(old, "count")
  let stable = version_vector.new() |> version_vector.increment(rid("A"))
  let pruned = or_map.prune(removed, stable)
  let assert Ok(loaded) =
    or_map.from_json_with(
      or_map.to_json_with(pruned, json.int) |> json.to_string,
      decode.int,
    )
  list.each([removed, pruned, loaded], fn(baseline) {
    let #(fresh, delta) = increment(baseline, 1)
    count(fresh)
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 1
    }
    let assert Ok(applied) = or_map.apply_delta(baseline, delta)
    applied
    |> fn(assertion_actual) {
      let assert True = assertion_actual == fresh
    }
    let assert Ok(merged) = or_map.merge(fresh, old)
    let assert Ok(delayed) = or_map.apply_delta(merged, old_delta)
    count(delayed)
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 1
    }
    let #(edited, _) = increment(delayed, 1)
    count(edited)
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 2
    }
  })
}

pub fn newer_removed_floor_suppresses_older_active_snapshot_and_delta_test() {
  let #(old, old_delta) = increment(or_map.new(rid("A"), crdt.GCounterSpec), 50)
  let #(fresh, fresh_delta) = increment(or_map.remove(old, "count"), 1)
  let #(removed, removal_delta) = or_map.remove_with_delta(fresh, "count")
  let pruned =
    or_map.prune(
      removed,
      version_vector.new() |> version_vector.increment(rid("A")),
    )
  let assert Ok(merged) = or_map.merge(pruned, old)
  or_map.keys(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  let blank = or_map.new(rid("B"), crdt.GCounterSpec)
  let assert Ok(received) =
    list.try_fold(
      [removal_delta, old_delta, fresh_delta, removal_delta, old_delta],
      blank,
      or_map.apply_delta,
    )
  let assert Ok(expected) = or_map.merge(blank, removed)
  received
  |> fn(assertion_actual) {
    let assert True = assertion_actual == expected
  }
  or_map.internal_value_count(received)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
  let #(reset, _) = increment(received, 7)
  count(reset)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 7
  }
}

pub fn concurrent_readds_choose_generation_not_merged_old_or_losing_values_test() {
  let #(old, _) = increment(or_map.new(rid("A"), crdt.GCounterSpec), 100)
  let removed = or_map.remove(old, "count")
  let #(a, da) = increment(removed, 1)
  let #(b, db) = increment(or_map.bind(removed, rid("B")), 2)
  let #(stale, ds) = increment(or_map.bind(old, rid("C")), 99)
  let assert Ok(ab) = or_map.merge_as(a, b, rid("R"))
  let assert Ok(ba) = or_map.merge_as(b, a, rid("R"))
  ab
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ba
  }
  count(ab)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 2
  }
  let assert Ok(merged) = or_map.merge(ab, stale)
  count(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 2
  }
  let assert Ok(batch) = or_map.merge_deltas(da, db)
  let assert Ok(batch) = or_map.merge_deltas(batch, ds)
  let assert Ok(applied) =
    or_map.apply_delta(or_map.bind(removed, rid("R")), batch)
  applied
  |> fn(assertion_actual) {
    let assert True = assertion_actual == merged
  }
}

pub fn remove_delivery_order_preserves_current_generation_baseline_test() {
  let #(a, add) = increment(or_map.new(rid("A"), crdt.GCounterSpec), 5)
  let #(removed, remove) = or_map.remove_with_delta(a, "count")
  let blank = or_map.new(rid("R"), crdt.GCounterSpec)
  let assert Ok(reverse) =
    list.try_fold([remove, add], blank, or_map.apply_delta)
  let assert Ok(forward) =
    list.try_fold([add, remove], blank, or_map.apply_delta)
  let assert Ok(full) = or_map.merge(blank, removed)
  reverse
  |> fn(assertion_actual) {
    let assert True = assertion_actual == forward
  }
  reverse
  |> fn(assertion_actual) {
    let assert True = assertion_actual == full
  }
  let #(concurrent, _) = increment(or_map.bind(a, rid("B")), 1)
  let assert Ok(merged) = or_map.merge(reverse, concurrent)
  count(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 6
  }
}

pub fn outer_reset_allocates_fresh_nested_sequence_ids_test() {
  let old = fixture.nested("A", [1, 2])
  let #(fresh, delta) = fixture.append(or_map.remove(old, "doc"), 9)
  fixture.sequence(fresh)
  |> sequence.values
  |> fn(assertion_actual) {
    let assert True = assertion_actual == [9]
  }
  sequence.merge(fixture.sequence(old), fixture.sequence(fresh), rid("C"))
  |> sequence.length
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 3
  }
  let assert Ok(merged) = or_map.merge(fresh, old)
  fixture.sequence(merged)
  |> sequence.values
  |> fn(assertion_actual) {
    let assert True = assertion_actual == [9]
  }
  let assert Ok(applied) = or_map.apply_delta(old, delta)
  applied
  |> fn(assertion_actual) {
    let assert True = assertion_actual == fresh
  }
}

pub fn scoped_key_names_do_not_collide_test() {
  let map: or_map.ORMap(Int) = or_map.new(rid("A"), crdt.SequenceSpec)
  let add = fn(value) {
    let assert crdt.CrdtSequence(value) = value
    let assert Ok(value) = sequence.insert(value, 0, 1)
    crdt.CrdtSequence(value)
  }
  let assert Ok(map) = or_map.update(map, "a:1:b", add)
  let assert Ok(map) = or_map.update(map, "a", add)
  let assert Ok(crdt.CrdtSequence(a)) = or_map.get(map, "a:1:b")
  let assert Ok(crdt.CrdtSequence(b)) = or_map.get(map, "a")
  sequence.merge(a, b, rid("R"))
  |> sequence.length
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 2
  }
}

pub fn sparse_callback_failure_and_schema_errors_are_atomic_test() {
  let map = fixture.nested("A", [1])
  or_map.update_delta(map, "missing", fn(_, _) { Error("rejected") })
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(crdt.CallbackError("rejected"))
  }
  or_map.update_delta(map, "doc", fn(_, _) {
    Ok(crdt.NoChange(crdt.OrMapSpec(crdt.TextSpec)))
  })
  |> fn(actual) {
    let assert True =
      actual
      == Error(crdt.CompositionError(crdt.AtKey("doc", crdt.SchemaMismatch)))
  }
  or_map.update(map, "doc", fn(_) {
    crdt.CrdtOrMap(or_map.new(rid("A"), crdt.TextSpec))
  })
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.AtKey("doc", crdt.SchemaMismatch))
  }
  fixture.sequence(map)
  |> sequence.values
  |> fn(assertion_actual) {
    let assert True = assertion_actual == [1]
  }
}

pub fn no_change_delta_refreshes_membership_without_resetting_leaf_test() {
  let #(baseline, _) = increment(or_map.new(rid("A"), crdt.GCounterSpec), 5)
  let removed = or_map.remove(or_map.bind(baseline, rid("B")), "count")
  let assert Ok(#(updated, delta)) =
    or_map.update_delta(baseline, "count", fn(_, _) {
      Ok(crdt.NoChange(crdt.GCounterSpec))
    })
  let assert Ok(applied) = or_map.apply_delta(baseline, delta)
  updated
  |> fn(assertion_actual) {
    let assert True = assertion_actual == applied
  }
  let assert Ok(merged) = or_map.merge(removed, updated)
  count(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 5
  }
}

pub fn configured_default_nochange_has_replica_independent_history_test() {
  let before = or_map.new(rid("A"), crdt.LwwRegisterSpec(42))
  let assert Ok(#(updated, delta)) =
    or_map.update_delta(before, "key", fn(_, _) {
      Ok(crdt.NoChange(crdt.LwwRegisterSpec(42)))
    })
  let remote = or_map.new(rid("B"), crdt.LwwRegisterSpec(42))
  let assert Ok(full) = or_map.merge(remote, updated)
  let assert Ok(sparse) = or_map.apply_delta(remote, delta)
  full
  |> fn(assertion_actual) {
    let assert True = assertion_actual == sparse
  }
}

pub fn full_state_update_joins_inside_generation_instead_of_resetting_history_test() {
  let #(map, _) = increment(or_map.new(rid("A"), crdt.GCounterSpec), 5)
  let assert Ok(updated) =
    or_map.update(map, "count", fn(_) {
      crdt.CrdtGCounter(g_counter.new(rid("A")))
    })
  count(updated)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 5
  }
}

pub fn pruned_generation_floor_retains_history_and_readd_uses_fresh_membership_scope_test() {
  let #(old, _) = increment(or_map.new(rid("A"), crdt.GCounterSpec), 50)
  let #(generation, _) = increment(or_map.remove(old, "count"), 1)
  let encoded = or_map.to_json_with(generation, json.int) |> json.to_string
  let assert Ok([membership]) =
    json.parse(encoded, {
      use state <- decode.field("state", {
        use entries <- decode.field(
          "entries",
          decode.list({
            use membership <- decode.field("membership", decode.string)
            decode.success(membership)
          }),
        )
        decode.success(entries)
      })
      decode.success(state)
    })
  let assert Ok(writer) =
    json.parse(membership, {
      use state <- decode.field("state", {
        use writer <- decode.field("replica_id", decode.string)
        decode.success(writer)
      })
      decode.success(state)
    })
  let stable = version_vector.from_dict(dict.from_list([#(rid(writer), 100)]))
  let pruned = generation |> or_map.remove("count") |> or_map.prune(stable)
  let assert Ok(loaded) =
    or_map.from_json_with(
      or_map.to_json_with(pruned, json.int) |> json.to_string,
      decode.int,
    )
  let assert Ok(merged) = or_map.merge(loaded, old)
  or_map.keys(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  or_map.internal_value_count(loaded)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
  let #(fresh, _) = increment(loaded, 7)
  let assert Ok(merged) = or_map.merge(fresh, pruned)
  count(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 7
  }
  let other = or_map.new(rid("A"), crdt.GCounterSpec) |> or_map.prune(stable)
  let #(other, _) = increment(other, 9)
  count(other)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 9
  }
}
