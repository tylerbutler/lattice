import gleam/dict
import gleam/json
import gleam/list
import gleam/set
import gleam/string
import lattice_presence/presence_state as state
import startest/expect

fn join_ok(
  state_: state.State,
  pid: String,
  topic: String,
  key: String,
  meta: json.Json,
) -> state.State {
  let assert Ok(joined) = state.join(state_, pid, topic, key, meta)
  joined
}

fn r(base: String) -> state.Replica {
  let assert Ok(replica) = state.new_replica(base, "test-incarnation")
  replica
}

fn merge_ok(a: state.State, b: state.State) -> state.State {
  let assert Ok(merged) = state.merge(a, b)
  merged
}

fn merge_diff_ok(a: state.State, b: state.State) -> #(state.State, state.Diff) {
  let assert Ok(merged) = state.merge_with_diff(a, b)
  merged
}

// ── Serialization roundtrip tests ───────────────────────────────────

pub fn roundtrip_empty_state_test() {
  let s = state.new(r("node1"))
  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  state.replica(decoded) |> expect.to_equal(r("node1"))
  state.entry_count(decoded) |> expect.to_equal(0)
  state.cloud_count(decoded) |> expect.to_equal(0)
}

pub fn roundtrip_state_with_entries_test() {
  let s = state.new(r("node1"))
  let s =
    join_ok(
      s,
      "pid1",
      "room:lobby",
      "user:alice",
      json.object([#("status", json.string("online"))]),
    )
  let s =
    join_ok(
      s,
      "pid2",
      "room:lobby",
      "user:bob",
      json.object([#("device", json.string("mobile"))]),
    )

  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  state.replica(decoded) |> expect.to_equal(r("node1"))
  state.entry_count(decoded) |> expect.to_equal(2)

  case dict.get(state.compacted_clocks(decoded), r("node1")) {
    Ok(2) -> Nil
    _ -> panic as "expected failure"
  }
}

pub fn roundtrip_state_with_multiple_replicas_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "lobby", "alice", json.null())

  let b = state.new(r("node_b"))
  let b = join_ok(b, "p2", "lobby", "bob", json.null())

  let merged = merge_ok(a, b)

  let json_str = state.to_json_string(merged)
  let assert Ok(decoded) = state.from_json(json_str)

  state.replica(decoded) |> expect.to_equal(r("node_a"))
  state.entry_count(decoded) |> expect.to_equal(2)

  case dict.get(state.compacted_clocks(decoded), r("node_a")) {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }
  case dict.get(state.compacted_clocks(decoded), r("node_b")) {
    Ok(1) -> Nil
    _ -> panic as "expected failure"
  }
}

pub fn roundtrip_state_with_replica_down_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b"))
  let b = join_ok(b, "p1", "lobby", "bob", json.null())

  let a = merge_ok(a, b)
  let #(a, _) = state.replica_down(a, r("node_b"))

  let json_str = state.to_json_string(a)
  let assert Ok(decoded) = state.from_json(json_str)

  state.get_by_topic(decoded, "lobby")
  |> list.length
  |> expect.to_equal(1)
}

pub fn roundtrip_preserves_merge_semantics_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "lobby", "alice", json.null())

  let b = state.new(r("node_b"))
  let b = join_ok(b, "p2", "lobby", "bob", json.null())

  let json_str = state.to_json_string(a)
  let assert Ok(a_roundtripped) = state.from_json(json_str)

  let #(merged, diff) = merge_diff_ok(a_roundtripped, b)

  state.get_by_topic(merged, "lobby")
  |> list.length
  |> expect.to_equal(2)

  case dict.get(diff.joins, "lobby") {
    Ok(joins) -> list.length(joins) |> expect.to_equal(1)
    Error(_) -> panic as "expected failure"
  }
}

pub fn roundtrip_state_with_clouds_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "lobby", "alice", json.null())
  let a = join_ok(a, "p2", "lobby", "bob", json.null())

  let json_str = state.to_json_string(a)
  let assert Ok(decoded) = state.from_json(json_str)

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

  let s = state.new(r("node1"))
  let s = join_ok(s, "pid1", "room:lobby", "user:alice", meta)

  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  // Verify the decoded state still has 1 entry
  state.entry_count(decoded) |> expect.to_equal(1)

  // Verify the re-encoded state produces valid JSON by doing another roundtrip
  let re_encoded = state.to_json_string(decoded)
  let assert Ok(decoded2) = state.from_json(re_encoded)
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

  let s = state.new(r("node1"))
  let s = join_ok(s, "pid1", "room:lobby", "user:alice", meta)

  // Roundtrip once
  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  // Roundtrip twice — the second encode should be stable
  let re_encoded = state.to_json_string(decoded)
  let assert Ok(decoded2) = state.from_json(re_encoded)
  let re_encoded2 = state.to_json_string(decoded2)

  // Stability check: second roundtrip produces identical JSON
  re_encoded2 |> expect.to_equal(re_encoded)
}

pub fn decode_invalid_json_returns_error_test() {
  let result = state.from_json("not json")
  let _ = expect.to_be_error(result)
  Nil
}

pub fn decode_missing_fields_returns_error_test() {
  let result = state.from_json("{\"replica\": \"node1\"}")
  let _ = expect.to_be_error(result)
  Nil
}

pub fn from_json_rejects_negative_context_clock_test() {
  let payload =
    "{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"context\":[{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"clock\":-1}],\"clouds\":[],\"retired\":[],\"values\":[]}"
  let result = state.from_json(payload)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn from_json_rejects_non_positive_tag_clock_test() {
  let payload =
    "{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"context\":[],\"clouds\":[],\"retired\":[],\"values\":[{\"tag\":{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"clock\":0},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":null}}]}"
  let result = state.from_json(payload)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn from_json_rejects_non_positive_cloud_clock_test() {
  let payload =
    "{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"context\":[],\"clouds\":[{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"clocks\":[0]}],\"retired\":[],\"values\":[]}"
  let _ = state.from_json(payload) |> expect.to_be_error
  Nil
}

pub fn from_json_rejects_deep_metadata_test() {
  let deep_meta = string.repeat("[", 65) <> "null" <> string.repeat("]", 65)
  let payload =
    "{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"context\":[{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"clock\":1}],\"clouds\":[],\"retired\":[],\"values\":[{\"tag\":{\"replica\":{\"base\":\"node1\",\"incarnation\":\"test-incarnation\"},\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"pid1\",\"meta\":"
    <> deep_meta
    <> "}}]}"
  let result = state.from_json(payload)
  let _ = expect.to_be_error(result)
  Nil
}

pub fn structured_replica_json_shape_test() {
  let encoded = state.new(r("node")) |> state.to_json_string
  string.contains(
    encoded,
    "\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"}",
  )
  |> expect.to_be_true
  string.contains(encoded, "\"context\":[]") |> expect.to_be_true
}

pub fn from_json_rejects_empty_replica_component_test() {
  let payload =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"\"},\"context\":[],\"clouds\":[],\"retired\":[],\"values\":[]}"
  let _ = state.from_json(payload) |> expect.to_be_error
  Nil
}

pub fn from_json_rejects_duplicate_context_replica_test() {
  let identity = "{\"base\":\"node\",\"incarnation\":\"i\"}"
  let payload =
    "{\"replica\":"
    <> identity
    <> ",\"context\":[{\"replica\":"
    <> identity
    <> ",\"clock\":1},{\"replica\":"
    <> identity
    <> ",\"clock\":2}],\"clouds\":[],\"retired\":[],\"values\":[]}"
  let _ = state.from_json(payload) |> expect.to_be_error
  Nil
}

pub fn retired_incarnations_roundtrip_test() {
  let local = state.new(r("local"))
  let remote =
    state.new(r("remote")) |> join_ok("p", "room", "remote", json.null())
  let local = merge_ok(local, remote)
  let #(local, _) = state.replica_down(local, r("remote"))
  let assert Ok(#(local, _)) = state.remove_down_replica(local, r("remote"))
  let assert Ok(decoded) = state.from_json(state.to_json_string(local))

  state.retired_replicas(decoded)
  |> expect.to_equal(set.from_list([r("remote")]))
}

pub fn from_json_rejects_uncovered_value_test() {
  let payload =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"context\":[],\"clouds\":[],\"retired\":[],\"values\":[{\"tag\":{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"alice\",\"pid\":\"p\",\"meta\":null}}]}"
  let _ = state.from_json(payload) |> expect.to_be_error
  Nil
}

pub fn from_json_rejects_duplicate_cloud_clock_test() {
  let payload =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"context\":[],\"clouds\":[{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clocks\":[2,2]}],\"retired\":[],\"values\":[]}"
  let _ = state.from_json(payload) |> expect.to_be_error
  Nil
}

pub fn from_json_rejects_contiguous_next_cloud_clock_test() {
  let payload =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"context\":[{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clock\":1}],\"clouds\":[{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clocks\":[2]}],\"retired\":[],\"values\":[]}"
  let _ = state.from_json(payload) |> expect.to_be_error
  Nil
}

pub fn join_after_gapped_cloud_roundtrips_test() {
  let payload =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"context\":[{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clock\":1}],\"clouds\":[{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"clocks\":[3]}],\"retired\":[],\"values\":[]}"
  let assert Ok(decoded) = state.from_json(payload)
  let joined = join_ok(decoded, "p", "room", "alice", json.null())
  let assert Ok(roundtripped) = state.from_json(state.to_json_string(joined))

  state.entry_count(roundtripped) |> expect.to_equal(1)
}

pub fn from_json_rejects_retired_value_or_cloud_test() {
  let identity = "{\"base\":\"old\",\"incarnation\":\"test-incarnation\"}"
  let retired_cloud =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"context\":[],\"clouds\":[{\"replica\":"
    <> identity
    <> ",\"clocks\":[1]}],\"retired\":["
    <> identity
    <> "],\"values\":[]}"
  let retired_value =
    "{\"replica\":{\"base\":\"node\",\"incarnation\":\"test-incarnation\"},\"context\":[{\"replica\":"
    <> identity
    <> ",\"clock\":1}],\"clouds\":[],\"retired\":["
    <> identity
    <> "],\"values\":[{\"tag\":{\"replica\":"
    <> identity
    <> ",\"clock\":1},\"entry\":{\"topic\":\"room\",\"key\":\"old\",\"pid\":\"p\",\"meta\":null}}]}"

  let _ = state.from_json(retired_cloud) |> expect.to_be_error
  let _ = state.from_json(retired_value) |> expect.to_be_error
  Nil
}

pub fn to_json_string_does_not_serialize_local_replica_liveness_test() {
  let a = state.new(r("node_a"))
  let b = state.new(r("node_b")) |> join_ok("p1", "lobby", "bob", json.null())
  let a = merge_ok(a, b)
  let #(a, _) = state.replica_down(a, r("node_b"))

  let encoded = state.to_json_string(a)
  string.contains(encoded, "replicas") |> expect.to_equal(False)

  let assert Ok(decoded) = state.from_json(encoded)
  state.get_by_topic(decoded, "lobby")
  |> list.length
  |> expect.to_equal(1)
}

pub fn serialize_deserialize_merge_converges_test() {
  let a = state.new(r("node_a"))
  let a = join_ok(a, "p1", "lobby", "alice", json.null())

  let b = state.new(r("node_b"))
  let b = join_ok(b, "p2", "lobby", "bob", json.null())

  let a_json = state.to_json_string(a)
  let b_json = state.to_json_string(b)

  let assert Ok(a_from_json) = state.from_json(a_json)
  let assert Ok(b_from_json) = state.from_json(b_json)

  let a_merged = merge_ok(a, b_from_json)
  let b_merged = merge_ok(b, a_from_json)

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
  let s = state.new(r("node1"))
  let s = join_ok(s, "pid1", "room:lobby", "user:alice", json.null())

  let json_str = state.to_json_string(s)
  let assert Ok(decoded) = state.from_json(json_str)

  // Roundtrip again to verify null meta is properly handled
  let re_encoded = state.to_json_string(decoded)
  let assert Ok(_decoded2) = state.from_json(re_encoded)
  // No crash = success
  Nil
}
