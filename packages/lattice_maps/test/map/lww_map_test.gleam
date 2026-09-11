import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register
import lattice_text/text
import support/lww_fixture as fixture

fn new(writer) {
  lww_map.new(replica_id.new(writer), crdt.LwwRegisterSpec(""))
}

fn child(value) {
  crdt.CrdtLwwRegister(lww_register.new(
    value,
    1,
    replica_id.new("historical-author"),
  ))
}

pub fn empty_lww_map_queries_test() {
  let map = new("A")
  lww_map.keys(map)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  lww_map.values(map)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  lww_map.get(map, "missing")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
  lww_map.tombstone_count(map)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 0
  }
  lww_map.pruned_timestamp(map)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 0
  }
}

pub fn modern_lww_lower_timestamp_and_schema_errors_test() {
  let assert Ok(map) = lww_map.set(new("A"), "key", child("value"), 10)
  list.each([0, 5], fn(timestamp) {
    lww_map.set(map, "key", child("other"), timestamp)
    |> fn(actual) {
      let assert True =
        actual == Error(crdt.TimestampNotAdvanced("key", timestamp, 10))
    }
    lww_map.remove(map, "key", timestamp)
    |> fn(actual) {
      let assert True =
        actual == Error(crdt.TimestampNotAdvanced("key", timestamp, 10))
    }
  })
  lww_map.set(
    map,
    "other",
    crdt.default_crdt(crdt.TextSpec, replica_id.new("A")),
    11,
  )
  |> fn(actual) {
    let assert True =
      actual
      == Error(crdt.AtKey("other", crdt.TypeMismatch("lww_register", "text")))
  }
  let assert Ok(map) = lww_map.set(map, "key", child("later"), 11)
  lww_map.get(map, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(child("later"))
  }
}

pub fn modern_lww_equal_time_local_remove_matches_merge_test() {
  let assert Ok(active) = lww_map.set(new("A"), "key", child("alive"), 10)
  let assert Ok(local) = lww_map.remove(active, "key", 10)
  let assert Ok(tombstone) = lww_map.remove(new("A"), "key", 10)
  let assert Ok(merged) = lww_map.merge(active, tombstone)

  local
  |> fn(assertion_actual) {
    let assert True = assertion_actual == merged
  }
  lww_map.get(local, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
  lww_map.tombstone_count(local)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
}

pub fn modern_lww_equal_time_local_set_cannot_revive_tombstone_test() {
  let assert Ok(tombstone) = lww_map.remove(new("A"), "key", 10)
  let assert Ok(same_writer) = lww_map.set(tombstone, "key", child("same"), 10)
  let assert Ok(greater_writer) =
    tombstone
    |> lww_map.bind(replica_id.new("Z"))
    |> lww_map.set("key", child("greater"), 10)

  list.each([same_writer, greater_writer], fn(map) {
    lww_map.get(map, "key")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Error(Nil)
    }
    lww_map.tombstone_count(map)
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 1
    }
  })
}

pub fn modern_lww_equal_time_local_sets_use_writer_not_payload_order_test() {
  list.each(["", "prefix:", "\u{10000}:"], fn(prefix) {
    let lesser_writer = prefix <> "\u{e000}"
    let greater_writer = prefix <> "\u{10000}"
    let assert Ok(lesser) =
      lww_map.set(new(lesser_writer), "key", child("zzz"), 10)
    let assert Ok(greater) =
      lww_map.set(new(greater_writer), "key", child("aaa"), 10)

    let assert Ok(local_greater) =
      lesser
      |> lww_map.bind(replica_id.new(greater_writer))
      |> lww_map.set("key", child("aaa"), 10)
    let assert Ok(local_lesser) =
      greater
      |> lww_map.bind(replica_id.new(lesser_writer))
      |> lww_map.set("key", child("zzz"), 10)
    let assert Ok(merged) =
      lww_map.merge_as(lesser, greater, replica_id.new(greater_writer))

    local_greater
    |> fn(assertion_actual) {
      let assert True = assertion_actual == merged
    }
    lww_map.get(local_greater, "key")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == lww_map.get(merged, "key")
    }
    lww_map.get(local_greater, "key")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Ok(child("aaa"))
    }
    lww_map.get(local_lesser, "key")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Ok(child("aaa"))
    }
  })
}

pub fn modern_lww_equal_time_same_live_stamp_is_idempotent_or_conflicting_test() {
  let assert Ok(map) = lww_map.set(new("A"), "key", child("one"), 10)
  lww_map.set(map, "key", child("one"), 10)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(map)
  }
  lww_map.set(map, "key", child("two"), 10)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.ConflictingWrite("key", 10))
  }
}

pub fn modern_lww_writer_ties_are_atomic_and_preserve_authors_test() {
  let assert Ok(a) = lww_map.set(new("A"), "key", child("zzz"), 10)
  let assert Ok(b) = lww_map.set(new("B"), "key", child("aaa"), 10)
  let assert Ok(ab) = lww_map.merge_as(a, b, replica_id.new("C"))
  let assert Ok(ba) = lww_map.merge_as(b, a, replica_id.new("C"))
  ab
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ba
  }
  lww_map.get(ab, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(child("aaa"))
  }
}

pub fn modern_lww_conflicting_same_write_is_error_test() {
  let assert Ok(a) = lww_map.set(new("A"), "key", child("one"), 10)
  let assert Ok(b) = lww_map.set(new("A"), "key", child("two"), 10)
  lww_map.merge(a, b)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.ConflictingWrite("key", 10))
  }
  lww_map.merge(b, a)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.ConflictingWrite("key", 10))
  }
  lww_map.merge(a, a)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(a)
  }
}

pub fn modern_lww_tombstone_precedes_writer_test() {
  let assert Ok(a) = lww_map.set(new("Z"), "key", child("alive"), 10)
  let assert Ok(b) = lww_map.remove(new("A"), "key", 10)
  let assert Ok(ab) = lww_map.merge(a, b)
  let assert Ok(ba) = lww_map.merge(b, a)
  lww_map.get(ab, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
  lww_map.get(ba, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
  lww_map.tombstone_count(ab)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
}

pub fn modern_lww_pruning_prevents_zombies_and_rejects_stale_new_keys_test() {
  let assert Ok(old) = lww_map.set(new("B"), "key", child("old"), 5)
  let assert Ok(removed) = lww_map.remove(new("A"), "key", 10)
  let pruned = lww_map.prune(removed, 10) |> lww_map.prune(2)
  let active_below_floor = lww_map.prune(old, 10)
  lww_map.pruned_timestamp(pruned)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 10
  }
  lww_map.tombstone_count(pruned)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 0
  }
  lww_map.set(pruned, "new", child("stale"), 9)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.TimestampNotAdvanced("new", 9, 10))
  }
  lww_map.set(pruned, "new", child("at-floor"), 10)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.TimestampNotAdvanced("new", 10, 10))
  }
  lww_map.remove(pruned, "new", 10)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.TimestampNotAdvanced("new", 10, 10))
  }
  lww_map.set(active_below_floor, "key", child("equal"), 5)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.TimestampNotAdvanced("key", 5, 10))
  }
  lww_map.remove(active_below_floor, "key", 5)
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == Error(crdt.TimestampNotAdvanced("key", 5, 10))
  }
  let assert Ok(merged) = lww_map.merge(pruned, old)
  let assert Ok(reverse) = lww_map.merge(old, pruned)
  lww_map.keys(merged)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  lww_map.keys(reverse)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  let assert Ok(fresh) = lww_map.set(pruned, "key", child("fresh"), 11)
  lww_map.get(fresh, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(child("fresh"))
  }
}

pub fn modern_lww_prune_preserves_active_children_test() {
  let assert Ok(map) = lww_map.set(new("A"), "active", child("value"), 1)
  let assert Ok(map) = lww_map.remove(map, "removed", 2)
  let map = lww_map.prune(map, 3)
  lww_map.values(map)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == [child("value")]
  }
  lww_map.keys(map)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ["active"]
  }
}

pub fn lww_assignment_context_prevents_fresh_text_id_reuse_test() {
  let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
  let replace = fn(_, context: crdt.EditContext) {
    let assert Ok(value) = text.append(text.new(context.replica_id), "fresh")
    Ok(crdt.CrdtText(value))
  }
  let assert Ok(first) = lww_map.update(map, "doc", 1, replace)
  let assert Ok(second) = lww_map.update(first, "doc", 2, replace)
  let assert Ok(crdt.CrdtText(a)) = lww_map.get(first, "doc")
  let assert Ok(crdt.CrdtText(b)) = lww_map.get(second, "doc")
  text.length(text.merge(a, b, replica_id.new("C")))
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 10
  }
  let assert Ok(merged) = lww_map.merge(first, second)
  let assert Ok(crdt.CrdtText(value)) = lww_map.get(merged, "doc")
  text.value(value)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == "fresh"
  }
  let before = lww_map.to_json(second) |> json.to_string
  let _ = lww_map.get(lww_map.bind(second, replica_id.new("B")), "doc")
  lww_map.to_json(second)
  |> json.to_string
  |> fn(assertion_actual) {
    let assert True = assertion_actual == before
  }
}

pub fn lww_callback_errors_are_atomic_test() {
  lww_map.update(new("A"), "key", 1, fn(_, _) { Error("rejected") })
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(crdt.CallbackError("rejected"))
  }
}

fn assert_legacy_merge(a, b, expected) {
  list.each([fixture.merge(a, b), fixture.merge(b, a)], fn(merged) {
    fixture.get(merged, "key")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Ok(expected)
    }
  })
}

pub fn merge_unicode_order_equal_timestamp_test() {
  assert_legacy_merge(
    fixture.legacy("\u{e000}", 10),
    fixture.legacy("\u{10000}", 10),
    "\u{10000}",
  )
}

pub fn merge_unicode_order_shared_prefix_test() {
  list.each(["prefix:", "\u{10000}:"], fn(prefix) {
    assert_legacy_merge(
      fixture.legacy(prefix <> "\u{e000}", 10),
      fixture.legacy(prefix <> "\u{10000}", 10),
      prefix <> "\u{10000}",
    )
  })
}

pub fn merge_unicode_order_lexical_controls_test() {
  list.each(
    [
      #("", "", ""),
      #("", "\u{10000}", "\u{10000}"),
      #("\u{10000}", "\u{10000}", "\u{10000}"),
      #("\u{10000}", "\u{10000}a", "\u{10000}a"),
      #("a", "aa", "aa"),
      #("a", "z", "z"),
      #("z", "aa", "z"),
    ],
    fn(values) {
      let #(left, right, expected) = values
      assert_legacy_merge(
        fixture.legacy(left, 10),
        fixture.legacy(right, 10),
        expected,
      )
    },
  )
}

pub fn merge_unicode_order_greater_timestamp_wins_test() {
  assert_legacy_merge(
    fixture.legacy("\u{e000}", 11),
    fixture.legacy("\u{10000}", 10),
    "\u{e000}",
  )
}

pub fn merge_unicode_order_equal_timestamp_tombstone_wins_test() {
  let assert Ok(tombstone) =
    fixture.import_legacy(
      "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":null,\"timestamp\":10}]}}",
    )
  list.each(["\u{e000}", "\u{10000}"], fn(value) {
    let live = fixture.legacy(value, 10)
    list.each(
      [fixture.merge(live, tombstone), fixture.merge(tombstone, live)],
      fn(merged) {
        fixture.get(merged, "key")
        |> fn(assertion_actual) {
          let assert True = assertion_actual == Error(Nil)
        }
        fixture.tombstone_count(merged)
        |> fn(assertion_actual) {
          let assert True = assertion_actual == 1
        }
      },
    )
  })
}

pub fn legacy_equal_time_local_set_uses_modern_writer_provenance_test() {
  let a = fixture.legacy("\u{e000}", 10)
  let b = fixture.legacy("\u{10000}", 10)
  let assert Ok(a) = lww_map.set(a, "key", child("\u{e000}"), 10)
  let assert Ok(b) = lww_map.set(b, "key", child("\u{e000}"), 10)
  fixture.get(a, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok("\u{e000}")
  }
  fixture.get(b, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok("\u{e000}")
  }
  assert_legacy_merge(a, b, "\u{e000}")
}

pub fn modern_lww_unicode_writer_ties_preserve_atomic_payloads_test() {
  list.each(
    [
      #("\u{e000}", "\u{10000}"),
      #("prefix:\u{e000}", "prefix:\u{10000}"),
      #("\u{10000}:\u{e000}", "\u{10000}:\u{10000}"),
      #("aa", "z"),
      #("", "\u{10000}"),
    ],
    fn(writers) {
      let assert Ok(a) = lww_map.set(new(writers.0), "key", child("zzz"), 10)
      let assert Ok(b) = lww_map.set(new(writers.1), "key", child("aaa"), 10)
      let local = replica_id.new("R")
      let assert Ok(merged) = lww_map.merge_as(a, b, local)
      lww_map.merge_as(b, a, local)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok(merged)
      }
      lww_map.get(merged, "key")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok(child("aaa"))
      }
      crdt.merge(crdt.CrdtLwwMap(a), crdt.CrdtLwwMap(b), local)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok(crdt.CrdtLwwMap(merged))
      }
      lww_map.from_json(lww_map.to_json(merged) |> json.to_string)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok(merged)
      }
      let assert Ok(removed) = lww_map.remove(new(writers.0), "key", 10)
      let assert Ok(removed) = lww_map.merge(removed, b)
      lww_map.get(removed, "key")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Error(Nil)
      }
    },
  )
}
