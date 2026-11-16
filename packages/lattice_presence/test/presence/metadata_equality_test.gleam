import gleam/dict
import gleam/json
import gleam/list
import lattice_presence/presence_state as state

fn snapshot(meta: json.Json) -> state.State {
  state.new("node_a")
  |> state.join("pid", "room", "user", meta)
}

fn expect_unchanged(local: state.State, remote: state.State) {
  let assert Ok(merged) = state.merge(local, remote)
  let assert True = merged == local
  let assert Ok(#(merged, diff)) = state.merge_with_diff(local, remote)
  let assert True = merged == local
  let assert True = diff == state.Diff(joins: dict.new(), leaves: dict.new())
}

pub fn same_replica_metadata_roundtrip_test() {
  list.each(
    [
      json.object([#("z", json.int(1)), #("a", json.int(2))]),
      json.preprocessed_array([
        json.string("line\n\"quoted\""),
        json.float(3.14),
        json.bool(False),
        json.null(),
      ]),
      json.string("plain metadata"),
      json.int(42),
      json.float(3.14),
      json.bool(True),
      json.null(),
    ],
    fn(meta) {
      let original = snapshot(meta)
      let assert Ok(decoded) =
        original |> state.to_json_string |> state.from_json

      expect_unchanged(original, original)
      expect_unchanged(original, decoded)
      expect_unchanged(decoded, original)
    },
  )
}

pub fn same_replica_nested_metadata_key_order_test() {
  let first = json.object([#("z", json.int(1)), #("a", json.int(2))])
  let reordered = json.object([#("a", json.int(2)), #("z", json.int(1))])
  let original =
    snapshot(
      json.object([
        #("z", json.preprocessed_array([first, json.null(), json.bool(True)])),
        #("a", json.object([#("child", first)])),
      ]),
    )
  let equivalent =
    snapshot(
      json.object([
        #("a", json.object([#("child", reordered)])),
        #(
          "z",
          json.preprocessed_array([reordered, json.null(), json.bool(True)]),
        ),
      ]),
    )
  let assert Ok(decoded) = equivalent |> state.to_json_string |> state.from_json

  expect_unchanged(original, equivalent)
  expect_unchanged(original, decoded)
  expect_unchanged(equivalent, original)
}

pub fn same_replica_different_metadata_conflicts_test() {
  let original =
    snapshot(
      json.object([
        #("nested", json.object([#("value", json.int(1))])),
        #("array", json.array([1, 2], json.int)),
      ]),
    )
  let different = [
    json.object([
      #("nested", json.object([#("value", json.int(2))])),
      #("array", json.array([1, 2], json.int)),
    ]),
    json.object([
      #("nested", json.object([#("value", json.int(1))])),
      #("array", json.array([2, 1], json.int)),
    ]),
    json.object([
      #("nested", json.object([#("value", json.string("1"))])),
      #("array", json.array([1, 2], json.int)),
    ]),
    json.object([
      #("nested", json.object([#("value", json.int(1))])),
      #("array", json.array([1], json.int)),
    ]),
    json.object([#("array", json.array([1, 2], json.int))]),
  ]

  list.each(different, fn(meta) {
    let remote = snapshot(meta)
    let assert Ok(decoded) = remote |> state.to_json_string |> state.from_json
    list.each([remote, decoded], fn(remote) {
      let assert Error(state.SameReplica("node_a")) =
        state.merge(original, remote)
      let assert Error(state.SameReplica("node_a")) =
        state.merge_with_diff(original, remote)
    })
  })
}

pub fn same_replica_semantic_metadata_keeps_local_liveness_test() {
  let peer =
    state.new("node_b") |> state.join("peer", "room", "user", json.null())
  let original =
    snapshot(json.object([#("z", json.int(1)), #("a", json.int(2))]))
  let assert Ok(local) = state.merge(original, peer)
  let #(local, _) = state.replica_down(local, "node_b")
  let assert Ok(decoded) = local |> state.to_json_string |> state.from_json

  expect_unchanged(local, decoded)
}

pub fn same_replica_metadata_equality_keeps_entry_identity_test() {
  let meta = json.object([#("z", json.int(1)), #("a", json.int(2))])
  let original = snapshot(meta)
  list.each(
    [
      state.join(state.new("node_a"), "other-pid", "room", "user", meta),
      state.join(state.new("node_a"), "pid", "other-room", "user", meta),
      state.join(state.new("node_a"), "pid", "room", "other-user", meta),
      state.leave(original, "pid", "room", "user"),
    ],
    fn(remote) {
      let assert Error(state.SameReplica("node_a")) =
        state.merge(original, remote)
      let assert Error(state.SameReplica("node_a")) =
        state.merge(remote, original)
    },
  )
}

pub fn same_replica_constructed_deep_metadata_test() {
  let wrap = fn(meta, _) { json.preprocessed_array([meta]) }
  let original =
    list.repeat(Nil, 65)
    |> list.fold(json.null(), wrap)
    |> snapshot
  let different =
    list.repeat(Nil, 65)
    |> list.fold(json.bool(False), wrap)
    |> snapshot

  expect_unchanged(original, original)
  let assert Error(_) = original |> state.to_json_string |> state.from_json
  let assert Error(_) = different |> state.to_json_string |> state.from_json
  let assert Error(state.SameReplica("node_a")) =
    state.merge(original, different)
  let assert Error(state.SameReplica("node_a")) =
    state.merge_with_diff(original, different)
}
