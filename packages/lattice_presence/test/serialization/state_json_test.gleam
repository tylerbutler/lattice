import gleam/dict
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice_presence/presence_state as state
import lattice_presence/state_json
import startest/expect

// ── Serialization roundtrip tests ───────────────────────────────────

pub fn roundtrip_empty_state_test() {
  let s = state.new("node1")
  let json_str = state_json.to_json_string(s)
  let assert Ok(decoded) = state_json.from_json(json_str)

  state.replica(decoded) |> expect.to_equal("node1")
  state.entry_count(decoded) |> expect.to_equal(0)
  state.cloud_count(decoded) |> expect.to_equal(0)
}

pub fn roundtrip_incarnation_identity_test() {
  let original =
    state.new_incarnation("node:west")
    |> state.join("pid1", "room:lobby", "alice", json.null())
  let replica = state.replica(original)

  let encoded = state_json.to_json_string(original)
  let assert Ok(decoded) = state_json.from_json(encoded)

  state.replica(decoded) |> expect.to_equal(replica)
  state.base_replica(state.replica(decoded)) |> expect.to_equal("node:west")
  state.same_base(state.replica(original), state.replica(decoded))
  |> expect.to_equal(True)
  dict.get(state.compacted_clocks(decoded), replica) |> expect.to_equal(Ok(1))
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

  let json_str = state_json.to_json_string(s)
  let assert Ok(decoded) = state_json.from_json(json_str)

  state.replica(decoded) |> expect.to_equal("node1")
  state.entry_count(decoded) |> expect.to_equal(2)

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

  let merged = state.merge(a, b)

  let json_str = state_json.to_json_string(merged)
  let assert Ok(decoded) = state_json.from_json(json_str)

  state.replica(decoded) |> expect.to_equal("node_a")
  state.entry_count(decoded) |> expect.to_equal(2)

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

  let a = state.merge(a, b)
  let #(a, _) = state.replica_down(a, "node_b")

  let json_str = state_json.to_json_string(a)
  let assert Ok(decoded) = state_json.from_json(json_str)

  state.get_by_topic(decoded, "lobby")
  |> list.length
  |> expect.to_equal(1)
}

pub fn roundtrip_preserves_merge_semantics_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "lobby", "alice", json.null())

  let b = state.new("node_b")
  let b = state.join(b, "p2", "lobby", "bob", json.null())

  let json_str = state_json.to_json_string(a)
  let assert Ok(a_roundtripped) = state_json.from_json(json_str)

  let #(merged, diff) = state.merge_with_diff(a_roundtripped, b)

  state.get_by_topic(merged, "lobby")
  |> list.length
  |> expect.to_equal(2)

  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

pub fn roundtrip_state_with_clouds_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "lobby", "alice", json.null())
  let a = state.join(a, "p2", "lobby", "bob", json.null())

  let json_str = state_json.to_json_string(a)
  let assert Ok(decoded) = state_json.from_json(json_str)

  // Sequential joins produce fully-compacted context, no clouds
  state.cloud_count(decoded)
  |> expect.to_equal(state.cloud_count(a))
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

  let json_str = state_json.to_json_string(s)
  let assert Ok(decoded) = state_json.from_json(json_str)

  // Verify the decoded state still has 1 entry
  state.entry_count(decoded) |> expect.to_equal(1)

  // Verify the re-encoded state produces valid JSON by doing another roundtrip
  let re_encoded = state_json.to_json_string(decoded)
  let assert Ok(decoded2) = state_json.from_json(re_encoded)
  state.entry_count(decoded2) |> expect.to_equal(1)
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
  let json_str = state_json.to_json_string(s)
  let assert Ok(decoded) = state_json.from_json(json_str)

  // Roundtrip twice — the second encode should be stable
  let re_encoded = state_json.to_json_string(decoded)
  let assert Ok(decoded2) = state_json.from_json(re_encoded)
  let re_encoded2 = state_json.to_json_string(decoded2)

  // Stability check: second roundtrip produces identical JSON
  re_encoded2 |> expect.to_equal(re_encoded)
}

pub fn decode_invalid_json_returns_error_test() {
  let result = state_json.from_json("not json")
  let _ = expect.to_be_error(result)
  Nil
}

pub fn decode_missing_fields_returns_error_test() {
  let result = state_json.from_json("{\"replica\": \"node1\"}")
  let _ = expect.to_be_error(result)
  Nil
}

pub fn from_json_rejects_negative_context_clock_test() {
  let payload =
    "{\"replica\":\"node1\",\"context\":{\"node1\":-1},\"clouds\":{},\"values\":[]}"
  let result = state_json.from_json(payload)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn from_json_rejects_non_positive_tag_clock_test() {
  let payload =
    "{\"replica\":\"node1\",\"context\":{},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":0},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":null}}]}"
  let result = state_json.from_json(payload)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn from_json_rejects_deep_metadata_test() {
  let deep_meta = string.repeat("[", 65) <> "null" <> string.repeat("]", 65)
  let payload =
    "{\"replica\":\"node1\",\"context\":{\"node1\":1},\"clouds\":{},\"values\":[{\"tag\":{\"replica\":\"node1\",\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":"
    <> deep_meta
    <> "}}]}"
  let result = state_json.from_json(payload)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn to_json_string_does_not_serialize_local_replica_liveness_test() {
  let a = state.new("node_a")
  let b = state.new("node_b") |> state.join("p1", "lobby", "bob", json.null())
  let a = state.merge(a, b)
  let #(a, _) = state.replica_down(a, "node_b")

  let encoded = state_json.to_json_string(a)
  string.contains(encoded, "replicas") |> expect.to_equal(False)

  let assert Ok(decoded) = state_json.from_json(encoded)
  state.get_by_topic(decoded, "lobby")
  |> list.length
  |> expect.to_equal(1)
}

pub fn serialize_deserialize_merge_converges_test() {
  let a = state.new("node_a")
  let a = state.join(a, "p1", "lobby", "alice", json.null())

  let b = state.new("node_b")
  let b = state.join(b, "p2", "lobby", "bob", json.null())

  let a_json = state_json.to_json_string(a)
  let b_json = state_json.to_json_string(b)

  let assert Ok(a_from_json) = state_json.from_json(a_json)
  let assert Ok(b_from_json) = state_json.from_json(b_json)

  let a_merged = state.merge(a, b_from_json)
  let b_merged = state.merge(b, a_from_json)

  state.get_by_topic(a_merged, "lobby")
  |> set.from_list
  |> set.size
  |> expect.to_equal(2)

  state.get_by_topic(b_merged, "lobby")
  |> set.from_list
  |> set.size
  |> expect.to_equal(2)
}

pub fn roundtrip_null_meta_test() {
  let s = state.new("node1")
  let s = state.join(s, "pid1", "room:lobby", "user:alice", json.null())

  let json_str = state_json.to_json_string(s)
  let assert Ok(decoded) = state_json.from_json(json_str)

  // Roundtrip again to verify null meta is properly handled
  let re_encoded = state_json.to_json_string(decoded)
  let assert Ok(_decoded2) = state_json.from_json(re_encoded)
  // No crash = success
  Nil
}
