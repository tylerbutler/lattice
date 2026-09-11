import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice_presence/presence_state as state

// ── Serialization roundtrip tests ───────────────────────────────────

pub fn roundtrip_empty_state_test() {
  let s = state.new("node1")
  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  state.replica(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }("node1")
  state.entry_count(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(0)
  state.cloud_count(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(0)
}

pub fn roundtrip_incarnation_identity_test() {
  let original =
    state.new_incarnation("node:west")
    |> state.join("pid1", "room:lobby", "alice", json.null())
  let replica = state.replica(original)

  let encoded = state.to_json_string(original)
  let assert Ok(decoded) = state.from_json(encoded)

  state.replica(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(replica)
  state.base_replica(state.replica(decoded))
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }("node:west")
  state.same_base(state.replica(original), state.replica(decoded))
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(True)
  dict.get(state.compacted_clocks(decoded), replica)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(1))
}

pub fn supersede_roundtrip_retains_sparse_high_water_against_stale_replay_test() {
  let old_replica = "lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAQ==:node"
  let assert Ok(old) =
    state.from_json(
      "{\"replica\":\"stale-peer\",\"context\":{
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAQ==:node\":1
      },\"clouds\":{
        \"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAQ==:node\":[5]
      },\"values\":[
        {\"tag\":{\"replica\":\"lattice-presence:v1:AAAAAAAAQACAAAAAAAAAAQ==:node\",\"clock\":5},\"entry\":{\"topic\":\"lobby\",\"key\":\"old-key\",\"pid\":\"old-pid\",\"meta\":null}}
      ]}",
    )
  let current =
    state.new_incarnation("node")
    |> state.join("current-pid", "lobby", "current-key", json.null())
  let assert Ok(stale) = state.merge(state.new("cleaner"), old)
  let assert Ok(stale) = state.merge(stale, current)
  let #(local, _) = state.replica_down(stale, state.replica(current))
  let assert Ok(#(cleaned, _)) = state.supersede(local, state.replica(current))
  state.online_list(cleaned)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }([])

  let encoded = state.to_json_string(cleaned)
  let assert Ok(decoded) = state.from_json(encoded)

  state.replica(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }("cleaner")
  state.compacted_clocks(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(
    dict.from_list([
      #(old_replica, 5),
      #(state.replica(current), 1),
    ]),
  )
  state.internal_clouds(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(dict.new())
  state.entry_count(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(1)
  string.contains(encoded, "replicas")
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(False)
  state.get_by_topic(decoded, "lobby")
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }([#("current-pid", "current-key", json.null())])
  state.supersede(decoded, state.replica(current))
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(#(decoded, state.Diff(joins: dict.new(), leaves: dict.new()))))

  let assert Ok(observer) = state.merge(state.new("observer"), stale)
  let assert Ok(observer) = state.merge(observer, decoded)
  let assert Ok(#(observer, diff)) = state.merge_with_diff(observer, stale)
  state.get_by_topic(observer, "lobby")
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }([#("current-pid", "current-key", json.null())])
  state.entry_count(observer)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(1)
  dict.get(state.compacted_clocks(observer), old_replica)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(5))
  state.cloud_count(observer)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(0)
  diff
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(state.Diff(joins: dict.new(), leaves: dict.new()))
}

pub fn roundtrip_state_with_entries_test() {
  let s = state.new("node1")
  let s =
    state.join(
      s,
      "pid1",
      "room:lobby",
      "user:alice",
      json.object([#("status", json.string("online"))]),
    )
  let s =
    state.join(
      s,
      "pid2",
      "room:lobby",
      "user:bob",
      json.object([#("device", json.string("mobile"))]),
    )

  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  state.replica(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }("node1")
  state.entry_count(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(2)

  case dict.get(state.compacted_clocks(decoded), "node1") {
    Ok(2) -> Nil
    _ -> panic as "expected failure"
  }
}

pub fn roundtrip_state_with_multiple_replicas_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "lobby", "alice", json.null())

  let b = state.new("node_b")
  let b = state.join(b, "p2", "lobby", "bob", json.null())

  let assert Ok(merged) = state.merge(a, b)

  let json_str = state.to_json_string(merged)
  let assert Ok(decoded) = state.from_json(json_str)

  state.replica(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }("node_a")
  state.entry_count(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(2)

  case dict.get(state.compacted_clocks(decoded), "node_a") {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }
  case dict.get(state.compacted_clocks(decoded), "node_b") {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }
}

pub fn roundtrip_state_with_replica_down_test() {
  let a = state.new("node_a")
  let b = state.new("node_b")
  let b = state.join(b, "p1", "lobby", "bob", json.null())

  let assert Ok(a) = state.merge(a, b)
  let #(a, _) = state.replica_down(a, "node_b")

  let json_str = state.to_json_string(a)
  let assert Ok(decoded) = state.from_json(json_str)

  state.get_by_topic(decoded, "lobby")
  |> list.length
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(1)
}

pub fn roundtrip_preserves_merge_semantics_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "lobby", "alice", json.null())

  let b = state.new("node_b")
  let b = state.join(b, "p2", "lobby", "bob", json.null())

  let json_str = state.to_json_string(a)
  let assert Ok(a_roundtripped) = state.from_json(json_str)

  let assert Ok(#(merged, diff)) = state.merge_with_diff(a_roundtripped, b)

  state.get_by_topic(merged, "lobby")
  |> list.length
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(2)

  case dict.get(diff.joins, "lobby") {
    Ok(joins) ->
      list.length(joins)
      |> fn(actual, expected) {
        let assert True = actual == expected
        Nil
      }(1)
    Error(_) -> panic as "expected failure"
  }
}

pub fn roundtrip_state_with_clouds_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "lobby", "alice", json.null())
  let a = state.join(a, "p2", "lobby", "bob", json.null())

  let json_str = state.to_json_string(a)
  let assert Ok(decoded) = state.from_json(json_str)

  // Sequential joins produce fully-compacted context, no clouds
  state.cloud_count(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(state.cloud_count(a))
}

pub fn roundtrip_with_json_meta_test() {
  // Test that metadata survives roundtrip (key ordering may differ)
  let meta =
    json.object([
      #("name", json.string("Alice")),
      #("age", json.int(30)),
      #("active", json.bool(True)),
    ])

  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "user:alice", meta)

  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  // Verify the decoded state still has 1 entry
  state.entry_count(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(1)

  // Verify the re-encoded state produces valid JSON by doing another roundtrip
  let re_encoded = state.to_json_string(decoded)
  let assert Ok(decoded2) = state.from_json(re_encoded)
  state.entry_count(decoded2)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(1)
}

pub fn roundtrip_preserves_metadata_values_test() {
  let meta =
    json.object([
      #("name", json.string("Alice")),
      #("age", json.int(30)),
      #("pi", json.float(3.14)),
      #("active", json.bool(True)),
      #("tags", json.array(["admin", "user"], json.string)),
      #("nested", json.object([#("inner", json.string("value"))])),
    ])

  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "user:alice", meta)

  // Roundtrip once
  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  // Roundtrip twice — the second encode should be stable
  let re_encoded = state.to_json_string(decoded)
  let assert Ok(decoded2) = state.from_json(re_encoded)
  let re_encoded2 = state.to_json_string(decoded2)

  // Stability check: second roundtrip produces identical JSON
  re_encoded2
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(re_encoded)
}

pub fn decode_invalid_json_returns_error_test() {
  let result = state.from_json("not json")
  let _ =
    fn(actual) {
      let assert Error(_) = actual
      Nil
    }(result)
  Nil
}

pub fn decode_missing_fields_returns_error_test() {
  let result = state.from_json("{\"replica\": \"node1\"}")
  let _ =
    fn(actual) {
      let assert Error(_) = actual
      Nil
    }(result)
  Nil
}

pub fn from_json_rejects_negative_context_clock_test() {
  let payload =
    "{\"replica\":\"node1\",\"context\":{\"node1\":-1},\"clouds\":{},\"values\":[]}"
  let result = state.from_json(payload)
  let _ =
    fn(actual) {
      let assert Error(_) = actual
      Nil
    }(result)
  Nil
}

pub fn from_json_rejects_non_positive_tag_clock_test() {
  let payload =
    "{\"replica\":\"node1\",\"context\":{},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":0},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":null}}]}"
  let result = state.from_json(payload)
  let _ =
    fn(actual) {
      let assert Error(_) = actual
      Nil
    }(result)
  Nil
}

pub fn from_json_rejects_deep_metadata_test() {
  let deep_meta = string.repeat("[", 65) <> "null" <> string.repeat("]", 65)
  let payload =
    "{\"replica\":\"node1\",\"context\":{\"node1\":1},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":"
    <> deep_meta
    <> "}}]}"
  let result = state.from_json(payload)
  let _ =
    fn(actual) {
      let assert Error(_) = actual
      Nil
    }(result)
  Nil
}

pub fn to_json_string_does_not_serialize_local_replica_liveness_test() {
  let a = state.new("node_a")
  let b = state.new("node_b") |> state.join("p1", "lobby", "bob", json.null())
  let assert Ok(a) = state.merge(a, b)
  let #(a, _) = state.replica_down(a, "node_b")

  let encoded = state.to_json_string(a)
  string.contains(encoded, "replicas")
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(False)

  let assert Ok(decoded) = state.from_json(encoded)
  state.get_by_topic(decoded, "lobby")
  |> list.length
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(1)
}

pub fn serialize_deserialize_merge_converges_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "lobby", "alice", json.null())

  let b = state.new("node_b")
  let b = state.join(b, "p2", "lobby", "bob", json.null())

  let a_json = state.to_json_string(a)
  let b_json = state.to_json_string(b)

  let assert Ok(a_from_json) = state.from_json(a_json)
  let assert Ok(b_from_json) = state.from_json(b_json)

  let assert Ok(a_merged) = state.merge(a, b_from_json)
  let assert Ok(b_merged) = state.merge(b, a_from_json)

  state.get_by_topic(a_merged, "lobby")
  |> set.from_list
  |> set.size
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(2)

  state.get_by_topic(b_merged, "lobby")
  |> set.from_list
  |> set.size
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(2)
}

pub fn roundtrip_null_meta_test() {
  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "user:alice", json.null())

  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  // Roundtrip again to verify null meta is properly handled
  let re_encoded = state.to_json_string(decoded)
  let assert Ok(_decoded2) = state.from_json(re_encoded)
  // No crash = success
  Nil
}

pub fn to_json_preserves_wire_shape_test() {
  let original =
    state.new("node1")
    |> state.join("pid1", "room", "alice", json.null())

  state.to_json(original)
  |> json.to_string
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(
    "{\"replica\":\"node1\",\"context\":{\"node1\":1},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":null}}]}",
  )
}

pub fn decoder_composes_inside_sync_envelope_test() {
  let original =
    state.new("node1")
    |> state.join("pid1", "room", "alice", json.null())
  let payload =
    json.object([
      #("kind", json.string("sync")),
      #("state", state.to_json(original)),
    ])
    |> json.to_string
  let envelope_decoder = {
    use kind <- decode.field("kind", decode.string)
    use snapshot <- decode.field("state", state.decoder())
    decode.success(#(kind, snapshot))
  }

  json.parse(payload, envelope_decoder)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(#("sync", original)))
}

pub fn from_json_resets_liveness_to_only_own_replica_up_test() {
  let a = state.new("node_a")
  let b = state.new("node_b") |> state.join("p1", "lobby", "bob", json.null())
  let assert Ok(original) = state.merge(a, b)
  let #(with_liveness, _) = state.replica_up(original, "node_b")
  let #(with_liveness, _) = state.replica_up(with_liveness, "node_c")
  let #(with_liveness, _) = state.replica_down(with_liveness, "node_a")
  let #(with_liveness, _) = state.replica_down(with_liveness, "node_b")

  with_liveness
  |> state.to_json_string
  |> state.from_json
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(original))
}

pub fn from_json_accepts_zero_context_and_positive_cloud_clocks_test() {
  let assert Ok(decoded) =
    state.from_json(
      "{\"replica\":\"node1\",\"context\":{\"node1\":0},\"clouds\":{\"node1\":[1,3]},\"values\":[]}",
    )

  state.compacted_clocks(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(dict.from_list([#("node1", 0)]))
  state.internal_clouds(decoded)
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(dict.from_list([#("node1", set.from_list([1, 3]))]))

  decoded
  |> state.to_json_string
  |> state.from_json
  |> fn(actual, expected) {
    let assert True = actual == expected
    Nil
  }(Ok(decoded))
}

pub fn from_json_rejects_non_positive_cloud_clocks_test() {
  list.each(["0", "-1"], fn(clock) {
    let payload =
      "{\"replica\":\"node1\",\"context\":{},\"clouds\":{\"node1\":["
      <> clock
      <> "]},\"values\":[]}"
    let _ =
      state.from_json(payload)
      |> fn(actual) {
        let assert Error(_) = actual
        Nil
      }
    Nil
  })
}

pub fn from_json_rejects_negative_tag_clock_test() {
  let payload =
    "{\"replica\":\"node1\",\"context\":{},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":-1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":null}}]}"
  let _ =
    state.from_json(payload)
    |> fn(actual) {
      let assert Error(_) = actual
      Nil
    }
  Nil
}

pub fn from_json_accepts_metadata_at_depth_limit_test() {
  list.each([#("[", "]"), #("{\"nested\":", "}")], fn(delimiters) {
    let meta =
      string.repeat(delimiters.0, 64)
      <> "null"
      <> string.repeat(delimiters.1, 64)
    let payload =
      "{\"replica\":\"node1\",\"context\":{\"node1\":1},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":"
      <> meta
      <> "}}]}"
    let assert Ok(decoded) = state.from_json(payload)
    let assert [#("pid1", decoded_meta)] =
      state.get_by_key(decoded, "room", "alice")

    json.to_string(decoded_meta)
    |> fn(actual, expected) {
      let assert True = actual == expected
      Nil
    }(meta)
  })
}

pub fn from_json_rejects_deep_object_metadata_test() {
  let meta =
    string.repeat("{\"nested\":", 65) <> "null" <> string.repeat("}", 65)
  let payload =
    "{\"replica\":\"node1\",\"context\":{\"node1\":1},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":"
    <> meta
    <> "}}]}"
  let _ =
    state.from_json(payload)
    |> fn(actual) {
      let assert Error(_) = actual
      Nil
    }
  Nil
}

pub fn from_json_rejects_missing_metadata_test() {
  let payload =
    "{\"replica\":\"node1\",\"context\":{\"node1\":1},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\"}}]}"
  let _ =
    state.from_json(payload)
    |> fn(actual) {
      let assert Error(_) = actual
      Nil
    }
  Nil
}
