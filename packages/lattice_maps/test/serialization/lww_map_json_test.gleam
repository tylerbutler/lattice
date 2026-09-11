import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_maps/crdt
import lattice_maps/lww_map as lww_map_module
import support/lww_fixture as lww_map

// LWW-Map JSON round-trip tests

fn round_trip(map: crdt.LWWMap(String)) -> crdt.LWWMap(String) {
  let assert Ok(decoded) =
    map |> lww_map.to_json |> json.to_string |> lww_map.from_json
  decoded
}

pub fn lww_map_to_json_empty_test() {
  let map = lww_map.new()
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) ->
      lww_map.keys(d)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == []
      }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn lww_map_round_trip_active_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.set("age", "30", 2)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      lww_map.get(d, "name")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok("Alice")
      }
      lww_map.get(d, "age")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok("30")
      }
    }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn lww_map_round_trip_tombstone_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.remove("name", 5)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) ->
      lww_map.get(d, "name")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Error(Nil)
      }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn lww_map_round_trip_mixed_active_and_tombstoned_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.set("age", "30", 2)
    |> lww_map.remove("age", 10)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      lww_map.get(d, "name")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok("Alice")
      }
      lww_map.get(d, "age")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Error(Nil)
      }
    }
    Error(_) -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn lww_map_round_trip_v3_with_pruned_timestamp_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.remove("old", 5)
    |> lww_map.prune(5)
  let json_str = json.to_string(lww_map.to_json(map))
  let assert Ok(decoded) = lww_map.from_json(json_str)

  // Active entry survives
  lww_map.get(decoded, "name")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok("Alice")
  }
  // Tombstone was pruned
  lww_map.tombstone_count(decoded)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 0
  }
  // pruned_timestamp survives round-trip
  lww_map.pruned_timestamp(decoded)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 5
  }

  // Zombie rejected after round-trip
  let zombie = lww_map.new() |> lww_map.set("old", "zombie", 3)
  let merged = lww_map.merge(decoded, zombie)
  lww_map.get(merged, "old")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
}

pub fn lww_map_v1_explicit_import_test() {
  // v1 JSON (no pruned_timestamp) should decode with pruned_timestamp=0
  let v1_json =
    "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[{\"key\":\"a\",\"value\":\"1\",\"timestamp\":5}]}}"
  let assert Ok(decoded) = lww_map.import_legacy(v1_json)
  lww_map.get(decoded, "a")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok("1")
  }
  lww_map.pruned_timestamp(decoded)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 0
  }
}

pub fn lww_map_unicode_order_v1_merge_round_trip_test() {
  let assert Ok(a) =
    lww_map.import_legacy(
      "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":\"\u{e000}\",\"timestamp\":10}]}}",
    )
  let assert Ok(b) =
    lww_map.import_legacy(
      "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":\"\u{10000}\",\"timestamp\":10}]}}",
    )

  list.each(
    [
      lww_map.merge(a, b),
      lww_map.merge(b, a),
      lww_map.merge(round_trip(a), round_trip(b)),
      lww_map.merge(round_trip(b), round_trip(a)),
    ],
    fn(merged) {
      lww_map.get(merged, "key")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok("\u{10000}")
      }
      let decoded = round_trip(merged)
      lww_map.get(decoded, "key")
      |> fn(assertion_actual) {
        let assert True = assertion_actual == Ok("\u{10000}")
      }
      lww_map.pruned_timestamp(decoded)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 0
      }
      lww_map.tombstone_count(decoded)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 0
      }
    },
  )
}

pub fn lww_map_unicode_order_v2_merge_round_trip_preserves_pruning_test() {
  let assert Ok(a) =
    lww_map.import_legacy(
      "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":\"\u{e000}\",\"timestamp\":10},{\"key\":\"deleted\",\"value\":null,\"timestamp\":15}],\"pruned_timestamp\":5}}",
    )
  let assert Ok(b) =
    lww_map.import_legacy(
      "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":\"\u{10000}\",\"timestamp\":10}],\"pruned_timestamp\":7}}",
    )
  let zombie = lww_map.new() |> lww_map.set("old", "stale", 7)

  list.each([lww_map.merge(a, b), lww_map.merge(b, a)], fn(merged) {
    lww_map.get(merged, "key")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Ok("\u{10000}")
    }
    let decoded = round_trip(merged)
    lww_map.get(decoded, "key")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Ok("\u{10000}")
    }
    lww_map.get(decoded, "deleted")
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Error(Nil)
    }
    lww_map.pruned_timestamp(decoded)
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 7
    }
    lww_map.tombstone_count(decoded)
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 1
    }

    list.each(
      [lww_map.merge(decoded, zombie), lww_map.merge(zombie, decoded)],
      fn(restored) {
        lww_map.get(restored, "old")
        |> fn(assertion_actual) {
          let assert True = assertion_actual == Error(Nil)
        }
        lww_map.get(restored, "key")
        |> fn(assertion_actual) {
          let assert True = assertion_actual == Ok("\u{10000}")
        }
        lww_map.pruned_timestamp(restored)
        |> fn(assertion_actual) {
          let assert True = assertion_actual == 7
        }
        lww_map.tombstone_count(restored)
        |> fn(assertion_actual) {
          let assert True = assertion_actual == 1
        }
      },
    )
  })
}

pub fn lww_map_rejects_nested_v2_register_without_replica_id_test() {
  let child =
    "{\"type\":\"lww_register\",\"v\":2,\"state\":{\"value\":\"hello\",\"timestamp\":42}}"
  let input =
    json.object([
      #("type", json.string("lww_map")),
      #("v", json.int(3)),
      #(
        "state",
        json.object([
          #("replica_id", json.string("map")),
          #(
            "spec",
            json.string(
              crdt.spec_to_json_with(crdt.LwwRegisterSpec(""), json.string)
              |> json.to_string,
            ),
          ),
          #("pruned_timestamp", json.int(0)),
          #(
            "entries",
            json.array(
              [
                json.object([
                  #("key", json.string("title")),
                  #("timestamp", json.int(42)),
                  #(
                    "provenance",
                    json.object([
                      #("kind", json.string("modern")),
                      #("writer", json.string("map")),
                    ]),
                  ),
                  #("value", json.string(child)),
                ]),
              ],
              fn(entry) { entry },
            ),
          ),
        ]),
      ),
    ])
    |> json.to_string

  lww_map_module.from_json_with(input, decode.string)
  |> fn(actual) {
    let assert True =
      actual
      == Error(
        json.UnableToDecode([
          decode.DecodeError(expected: "Field", found: "Nothing", path: [
            "entries",
            "title",
            "state",
            "replica_id",
          ]),
        ]),
      )
  }
}

pub fn lww_map_from_json_invalid_test() {
  let result = lww_map.from_json("{invalid json}")
  case result {
    Ok(_) -> {
      panic as "Unexpected test branch"
    }
    Error(_) -> {
      Nil
    }
  }
}
