import gleam/json
import gleam/list
import lattice_maps/lww_map
import startest/expect

// LWW-Map JSON round-trip tests

fn round_trip(map: lww_map.LWWMap) -> lww_map.LWWMap {
  let assert Ok(decoded) =
    map |> lww_map.to_json |> json.to_string |> lww_map.from_json
  decoded
}

pub fn lww_map_to_json_empty_test() {
  let map = lww_map.new()
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> lww_map.keys(d) |> expect.to_equal([])
    Error(_) -> expect.to_be_true(False)
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
      lww_map.get(d, "name") |> expect.to_equal(Ok("Alice"))
      lww_map.get(d, "age") |> expect.to_equal(Ok("30"))
    }
    Error(_) -> expect.to_be_true(False)
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
    Ok(d) -> lww_map.get(d, "name") |> expect.to_equal(Error(Nil))
    Error(_) -> expect.to_be_true(False)
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
      lww_map.get(d, "name") |> expect.to_equal(Ok("Alice"))
      lww_map.get(d, "age") |> expect.to_equal(Error(Nil))
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn lww_map_round_trip_v2_with_pruned_timestamp_test() {
  let map =
    lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.remove("old", 5)
    |> lww_map.prune(5)
  let json_str = json.to_string(lww_map.to_json(map))
  let assert Ok(decoded) = lww_map.from_json(json_str)

  // Active entry survives
  lww_map.get(decoded, "name") |> expect.to_equal(Ok("Alice"))
  // Tombstone was pruned
  lww_map.tombstone_count(decoded) |> expect.to_equal(0)
  // pruned_timestamp survives round-trip
  lww_map.pruned_timestamp(decoded) |> expect.to_equal(5)

  // Zombie rejected after round-trip
  let zombie = lww_map.new() |> lww_map.set("old", "zombie", 3)
  let merged = lww_map.merge(decoded, zombie)
  lww_map.get(merged, "old") |> expect.to_equal(Error(Nil))
}

pub fn lww_map_from_json_v1_backward_compatible_test() {
  // v1 JSON (no pruned_timestamp) should decode with pruned_timestamp=0
  let v1_json =
    "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[{\"key\":\"a\",\"value\":\"1\",\"timestamp\":5}]}}"
  let assert Ok(decoded) = lww_map.from_json(v1_json)
  lww_map.get(decoded, "a") |> expect.to_equal(Ok("1"))
  lww_map.pruned_timestamp(decoded) |> expect.to_equal(0)
}

pub fn lww_map_unicode_order_v1_merge_round_trip_test() {
  let assert Ok(a) =
    lww_map.from_json(
      "{\"type\":\"lww_map\",\"v\":1,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":\"\u{e000}\",\"timestamp\":10}]}}",
    )
  let assert Ok(b) =
    lww_map.from_json(
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
      lww_map.get(merged, "key") |> expect.to_equal(Ok("\u{10000}"))
      let decoded = round_trip(merged)
      lww_map.get(decoded, "key") |> expect.to_equal(Ok("\u{10000}"))
      lww_map.pruned_timestamp(decoded) |> expect.to_equal(0)
      lww_map.tombstone_count(decoded) |> expect.to_equal(0)
    },
  )
}

pub fn lww_map_unicode_order_v2_merge_round_trip_preserves_pruning_test() {
  let assert Ok(a) =
    lww_map.from_json(
      "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":\"\u{e000}\",\"timestamp\":10},{\"key\":\"deleted\",\"value\":null,\"timestamp\":15}],\"pruned_timestamp\":5}}",
    )
  let assert Ok(b) =
    lww_map.from_json(
      "{\"type\":\"lww_map\",\"v\":2,\"state\":{\"entries\":[{\"key\":\"key\",\"value\":\"\u{10000}\",\"timestamp\":10}],\"pruned_timestamp\":7}}",
    )
  let zombie = lww_map.new() |> lww_map.set("old", "stale", 7)

  list.each([lww_map.merge(a, b), lww_map.merge(b, a)], fn(merged) {
    lww_map.get(merged, "key") |> expect.to_equal(Ok("\u{10000}"))
    let decoded = round_trip(merged)
    lww_map.get(decoded, "key") |> expect.to_equal(Ok("\u{10000}"))
    lww_map.get(decoded, "deleted") |> expect.to_equal(Error(Nil))
    lww_map.pruned_timestamp(decoded) |> expect.to_equal(7)
    lww_map.tombstone_count(decoded) |> expect.to_equal(1)

    list.each(
      [lww_map.merge(decoded, zombie), lww_map.merge(zombie, decoded)],
      fn(restored) {
        lww_map.get(restored, "old") |> expect.to_equal(Error(Nil))
        lww_map.get(restored, "key") |> expect.to_equal(Ok("\u{10000}"))
        lww_map.pruned_timestamp(restored) |> expect.to_equal(7)
        lww_map.tombstone_count(restored) |> expect.to_equal(1)
      },
    )
  })
}

pub fn lww_map_from_json_invalid_test() {
  let result = lww_map.from_json("{invalid json}")
  case result {
    Ok(_) -> expect.to_be_true(False)
    Error(_) -> expect.to_be_true(True)
  }
}
