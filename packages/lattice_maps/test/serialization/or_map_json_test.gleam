import gleam/dynamic/decode
import gleam/json
import gleam/set
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_maps/crdt.{CrdtGCounter, GCounterSpec, OrSetSpec}
import lattice_maps/or_map
import lattice_sets/g_set
import lattice_sets/or_set

fn rid(id: String) {
  replica_id.new(id)
}

// OR-Map JSON round-trip tests

pub fn or_map_to_json_empty_test() {
  let map = or_map.new(rid("A"), GCounterSpec)
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) ->
      or_map.keys(d)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == []
      }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn or_map_round_trip_crdt_spec_preserved_test() {
  // Verify crdt_spec is preserved by checking that the decoded map
  // can successfully update with GCounter operations
  let map = or_map.new(rid("A"), GCounterSpec)
  let json_str = json.to_string(or_map.to_json(map))
  let assert Ok(decoded) = or_map.from_json(json_str)
  let assert Ok(updated) =
    or_map.update(decoded, "test_key", fn(c) {
      let assert crdt.CrdtGCounter(counter) = c
      let assert Ok(counter) = g_counter.increment(counter, 1)
      crdt.CrdtGCounter(counter)
    })
  let assert Ok(crdt.CrdtGCounter(counter)) = or_map.get(updated, "test_key")
  g_counter.value(counter)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
}

pub fn or_map_round_trip_single_key_test() {
  let map = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(map) =
    or_map.update(map, "score", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 5)
          crdt.CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      set.from_list(or_map.keys(d))
      |> fn(assertion_actual) {
        let assert True = assertion_actual == set.from_list(["score"])
      }
      case or_map.get(d, "score") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter)
          |> fn(assertion_actual) {
            let assert True = assertion_actual == 5
          }
        _ -> {
          panic as "Unexpected test branch"
        }
      }
    }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn or_map_round_trip_multiple_keys_test() {
  let map = or_map.new(rid("A"), GCounterSpec)
  let assert Ok(map) =
    or_map.update(map, "alpha", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 10)
          crdt.CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let assert Ok(map) =
    or_map.update(map, "beta", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) -> {
          let assert Ok(counter) = g_counter.increment(counter, 20)
          crdt.CrdtGCounter(counter)
        }
        _ -> c
      }
    })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      set.from_list(or_map.keys(d))
      |> fn(assertion_actual) {
        let assert True = assertion_actual == set.from_list(["alpha", "beta"])
      }
      case or_map.get(d, "alpha") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter)
          |> fn(assertion_actual) {
            let assert True = assertion_actual == 10
          }
        _ -> {
          panic as "Unexpected test branch"
        }
      }
      case or_map.get(d, "beta") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter)
          |> fn(assertion_actual) {
            let assert True = assertion_actual == 20
          }
        _ -> {
          panic as "Unexpected test branch"
        }
      }
    }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn or_map_round_trip_or_set_values_test() {
  let map = or_map.new(rid("A"), OrSetSpec)
  let assert Ok(map) =
    or_map.update(map, "tags", fn(c) {
      case c {
        crdt.CrdtOrSet(orset) ->
          crdt.CrdtOrSet(
            orset
            |> or_set.add("hello"),
          )
        _ -> c
      }
    })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      set.from_list(or_map.keys(d))
      |> fn(assertion_actual) {
        let assert True = assertion_actual == set.from_list(["tags"])
      }
      case or_map.get(d, "tags") {
        Ok(crdt.CrdtOrSet(orset)) -> {
          or_set.contains(orset, "hello")
          |> fn(value) {
            let assert True = value
          }
        }
        _ -> {
          panic as "Unexpected test branch"
        }
      }
    }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn or_map_from_json_rejects_values_that_do_not_match_spec_test() {
  let invalid =
    json.to_string(
      json.object([
        #("type", json.string("or_map")),
        #("v", json.int(1)),
        #(
          "state",
          json.object([
            #("replica_id", json.string("A")),
            #("crdt_spec", json.string("g_counter")),
            #(
              "key_set",
              json.string(
                json.to_string(or_set.to_json(
                  or_set.new(rid("A")) |> or_set.add("x"),
                )),
              ),
            ),
            #(
              "values",
              json.array(
                [
                  json.object([
                    #("key", json.string("x")),
                    #(
                      "crdt",
                      json.string(
                        json.to_string(
                          crdt.to_json(crdt.CrdtGSet(
                            g_set.new() |> g_set.add("bad"),
                          )),
                        ),
                      ),
                    ),
                  ]),
                ],
                fn(entry) { entry },
              ),
            ),
          ]),
        ),
      ]),
    )

  case or_map.from_json(invalid) {
    Error(_) -> {
      Nil
    }
    Ok(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn or_map_from_json_invalid_test() {
  let result = or_map.from_json("{invalid json}")
  case result {
    Ok(_) -> {
      panic as "Unexpected test branch"
    }
    Error(_) -> {
      Nil
    }
  }
}

fn inc(c: crdt.Crdt(String), amount: Int) -> crdt.Crdt(String) {
  case c {
    CrdtGCounter(counter) -> {
      let assert Ok(counter) = g_counter.increment(counter, amount)
      CrdtGCounter(counter)
    }
    _ -> c
  }
}

// --- Versioned snapshots and explicit legacy baseline imports ---

pub fn or_map_v3_round_trip_preserves_inactive_generation_history_test() {
  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
  let m = or_map.remove(m, "x")

  let json_str = json.to_string(or_map.to_json(m))
  let assert Ok(decoded) = or_map.from_json(json_str)

  // Prune membership only; the current generation's baseline must survive.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let pruned = or_map.prune(decoded, stable)

  or_map.internal_value_count(pruned)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
}

pub fn or_map_v1_explicit_import_retains_history_test() {
  // Construct a v1 JSON string manually (no remove_bounds field)
  let key_set =
    or_set.new(rid("A"))
    |> or_set.add("x")
    |> or_set.remove("x")

  let assert Ok(counter) = g_counter.new(rid("A")) |> g_counter.increment(5)
  let counter_json = crdt.to_json(CrdtGCounter(counter))

  let v1_json =
    json.to_string(
      json.object([
        #("type", json.string("or_map")),
        #("v", json.int(1)),
        #(
          "state",
          json.object([
            #("replica_id", json.string("A")),
            #("crdt_spec", json.string("g_counter")),
            #("key_set", json.string(json.to_string(or_set.to_json(key_set)))),
            #(
              "values",
              json.array(
                [
                  json.object([
                    #("key", json.string("x")),
                    #("crdt", json.string(json.to_string(counter_json))),
                  ]),
                ],
                fn(entry) { entry },
              ),
            ),
          ]),
        ),
      ]),
    )

  let assert Ok(decoded) =
    or_map.import_legacy(v1_json, GCounterSpec, decode.string, rid("A"))

  // Membership stability does not authorize current-generation compaction.
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let pruned = or_map.prune(decoded, stable)

  or_map.internal_value_count(pruned)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }

  // Merge with concurrent add still works
  let assert Ok(concurrent) =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })
  let assert Ok(merged) = or_map.merge(pruned, concurrent)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 104
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn or_map_v3_counter_snapshot_round_trip_test() {
  let assert Ok(m) =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("y", fn(c) { inc(c, 10) })

  let json_str = json.to_string(or_map.to_json(m))
  let assert Ok(decoded) = or_map.from_json(json_str)

  set.from_list(or_map.keys(decoded))
  |> fn(assertion_actual) {
    let assert True = assertion_actual == set.from_list(["y"])
  }

  case or_map.get(decoded, "y") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 10
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}
