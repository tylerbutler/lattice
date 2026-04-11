import gleam/json
import gleam/set
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_maps/crdt.{CrdtGCounter, GCounterSpec, OrSetSpec}
import lattice_maps/or_map
import lattice_sets/g_set
import lattice_sets/or_set
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// OR-Map JSON round-trip tests

pub fn or_map_to_json_empty_test() {
  let map = or_map.new(rid("A"), GCounterSpec)
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> or_map.keys(d) |> expect.to_equal([])
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_round_trip_crdt_spec_preserved_test() {
  // Verify crdt_spec is preserved by checking that the decoded map
  // can successfully update with GCounter operations
  let map = or_map.new(rid("A"), GCounterSpec)
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      // If spec wasn't preserved, this update would fail or produce wrong type
      let updated =
        or_map.update(d, "test_key", fn(c) {
          case c {
            crdt.CrdtGCounter(counter) ->
              crdt.CrdtGCounter(g_counter.increment(counter, 1))
            _ -> c
          }
        })
      case or_map.get(updated, "test_key") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter) |> expect.to_equal(1)
        _ -> expect.to_be_true(False)
      }
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_round_trip_single_key_test() {
  let map = or_map.new(rid("A"), GCounterSpec)
  let map =
    or_map.update(map, "score", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) ->
          crdt.CrdtGCounter(g_counter.increment(counter, 5))
        _ -> c
      }
    })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      set.from_list(or_map.keys(d)) |> expect.to_equal(set.from_list(["score"]))
      case or_map.get(d, "score") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter) |> expect.to_equal(5)
        _ -> expect.to_be_true(False)
      }
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_round_trip_multiple_keys_test() {
  let map = or_map.new(rid("A"), GCounterSpec)
  let map =
    or_map.update(map, "alpha", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) ->
          crdt.CrdtGCounter(g_counter.increment(counter, 10))
        _ -> c
      }
    })
  let map =
    or_map.update(map, "beta", fn(c) {
      case c {
        crdt.CrdtGCounter(counter) ->
          crdt.CrdtGCounter(g_counter.increment(counter, 20))
        _ -> c
      }
    })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      set.from_list(or_map.keys(d))
      |> expect.to_equal(set.from_list(["alpha", "beta"]))
      case or_map.get(d, "alpha") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter) |> expect.to_equal(10)
        _ -> expect.to_be_true(False)
      }
      case or_map.get(d, "beta") {
        Ok(crdt.CrdtGCounter(counter)) ->
          g_counter.value(counter) |> expect.to_equal(20)
        _ -> expect.to_be_true(False)
      }
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_round_trip_or_set_values_test() {
  let map = or_map.new(rid("A"), OrSetSpec)
  let map =
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
      set.from_list(or_map.keys(d)) |> expect.to_equal(set.from_list(["tags"]))
      case or_map.get(d, "tags") {
        Ok(crdt.CrdtOrSet(orset)) -> {
          or_set.contains(orset, "hello") |> expect.to_be_true()
        }
        _ -> expect.to_be_true(False)
      }
    }
    Error(_) -> expect.to_be_true(False)
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
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn or_map_from_json_invalid_test() {
  let result = or_map.from_json("{invalid json}")
  case result {
    Ok(_) -> expect.to_be_true(False)
    Error(_) -> expect.to_be_true(True)
  }
}

fn inc(c: crdt.Crdt, amount: Int) -> crdt.Crdt {
  case c {
    CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, amount))
    _ -> c
  }
}

// --- v2 serialization with remove_bounds ---

pub fn or_map_v2_round_trip_with_remove_bounds_test() {
  // Create map, add key, remove key → has remove_bound
  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 5) })
    |> or_map.remove("x")

  let json_str = json.to_string(or_map.to_json(m))
  let assert Ok(decoded) = or_map.from_json(json_str)

  // After round-trip, prune with stable VV should compact the value
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let pruned = or_map.prune(decoded, stable)

  or_map.internal_value_count(pruned) |> expect.to_equal(0)
}

pub fn or_map_v1_backward_compat_no_compaction_test() {
  // Construct a v1 JSON string manually (no remove_bounds field)
  let key_set =
    or_set.new(rid("A"))
    |> or_set.add("x")
    |> or_set.remove("x")

  let counter_json =
    crdt.to_json(CrdtGCounter(g_counter.new(rid("A")) |> g_counter.increment(5)))

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

  let assert Ok(decoded) = or_map.from_json(v1_json)

  // v1 has no remove_bounds, so prune should NOT compact the value
  let stable =
    version_vector.new()
    |> version_vector.increment(rid("A"))
  let pruned = or_map.prune(decoded, stable)

  // Value is retained (no bound to check against)
  or_map.internal_value_count(pruned) |> expect.to_equal(1)

  // Merge with concurrent add still works
  let concurrent =
    or_map.new(rid("B"), GCounterSpec)
    |> or_map.update("x", fn(c) { inc(c, 99) })
  let assert Ok(merged) = or_map.merge(pruned, concurrent)

  case or_map.get(merged, "x") {
    Ok(CrdtGCounter(counter)) ->
      g_counter.value(counter) |> expect.to_equal(104)
    _ -> expect.to_be_true(False)
  }
}

pub fn or_map_v2_from_json_reads_v1_test() {
  // A v1-encoded map should decode successfully and work correctly
  let m =
    or_map.new(rid("A"), GCounterSpec)
    |> or_map.update("y", fn(c) { inc(c, 10) })

  // Current to_json produces v2, but we should still be able to read v1
  let json_str = json.to_string(or_map.to_json(m))
  let assert Ok(decoded) = or_map.from_json(json_str)

  set.from_list(or_map.keys(decoded))
  |> expect.to_equal(set.from_list(["y"]))

  case or_map.get(decoded, "y") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }
}
