import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_fugue/sequence

fn rid(id: String) {
  replica_id.new(id)
}

fn round_trip(seq: sequence.Sequence(String)) {
  seq
  |> sequence.to_json(json.string)
  |> json.to_string()
  |> sequence.from_json(decode.string)
}

pub fn empty_round_trips_test() {
  let seq = sequence.new(rid("A"))
  round_trip(seq)
  |> fn(actual) {
    assert actual == Ok(seq)
  }
}

pub fn populated_round_trips_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
    |> result.try(sequence.insert(_, 1, "c"))
  round_trip(seq)
  |> fn(actual) {
    assert actual == Ok(seq)
  }
}

pub fn tombstones_round_trip_test() {
  let assert Ok(inserted) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "a")
    |> result.try(sequence.insert(_, 1, "b"))
  let assert Ok(seq) = sequence.delete(inserted, 0)
  round_trip(seq)
  |> fn(actual) {
    assert actual == Ok(seq)
  }
}

pub fn round_trip_preserves_values_test() {
  let assert Ok(seq) =
    sequence.new(rid("A"))
    |> sequence.insert(0, "x")
    |> result.try(sequence.insert(_, 0, "y"))
    |> result.try(sequence.insert(_, 0, "z"))
  let assert Ok(decoded) = round_trip(seq)
  sequence.values(decoded)
  |> fn(actual) {
    assert actual == sequence.values(seq)
  }
}

pub fn decoded_snapshots_unicode_order_and_anchor_test() {
  let assert Ok(bmp) = sequence.new(rid("\u{e000}")) |> sequence.insert(0, "b")
  let assert Ok(supplementary) =
    sequence.new(rid("\u{10000}")) |> sequence.insert(0, "s")
  let assert Ok(anchor) = sequence.anchor_at(bmp, 0, sequence.Before)
  let assert Ok(decoded_bmp) = round_trip(bmp)
  let assert Ok(decoded_supplementary) = round_trip(supplementary)
  let local = rid("local")

  [
    sequence.merge(decoded_bmp, decoded_supplementary, local),
    sequence.merge(decoded_supplementary, decoded_bmp, local),
  ]
  |> list.each(fn(merged) {
    let assert Ok(decoded) = round_trip(merged)
    sequence.values(merged)
    |> fn(actual) {
      assert actual == ["b", "s"]
    }
    sequence.resolve(merged, anchor)
    |> fn(actual) {
      assert actual == Ok(0)
    }
    sequence.values(decoded)
    |> fn(actual) {
      assert actual == ["b", "s"]
    }
    sequence.resolve(decoded, anchor)
    |> fn(actual) {
      assert actual == Ok(0)
    }
  })
}

pub fn wrong_type_tag_fails_test() {
  let result =
    "{\"type\":\"sequence\",\"v\":1,\"state\":{}}"
    |> sequence.from_json(decode.string)
  let _ = {
    let assert Error(error) = result
    error
  }
  Nil
}

pub fn wrong_version_fails_test() {
  let assert Ok(seq) = sequence.new(rid("A")) |> sequence.insert(0, "a")
  let bad =
    seq
    |> sequence.to_json(json.string)
    |> json.to_string()
    |> string.replace("\"v\":2", "\"v\":99")
  let _ = {
    let assert Error(error) = sequence.from_json(bad, decode.string)
    error
  }
  Nil
}

pub fn live_null_round_trips_test() {
  let assert Ok(original) = sequence.insert(sequence.new(rid("A")), 0, Nil)
  let encoded =
    sequence.to_json(original, fn(_) { json.null() })
    |> json.to_string()
  let assert Ok(decoded) = sequence.from_json(encoded, decode.success(Nil))

  assert decoded == original
  assert sequence.values(decoded) == [Nil]
  assert sequence.length(decoded) == 1
  assert sequence.merge(original, decoded, rid("A")) == original
  assert sequence.merge(decoded, original, rid("A")) == original
  let assert Ok(#(2, [False])) =
    json.parse(encoded, {
      use version <- decode.field("v", decode.int)
      use deleted <- decode.field(
        "state",
        decode.at(["nodes"], decode.list(decode.at(["deleted"], decode.bool))),
      )
      decode.success(#(version, deleted))
    })
}

pub fn v2_validates_structure_and_repairs_counter_with_live_null_test() {
  let live_null = node("A", 7, json.null(), json.null())
  let encode = fn(nodes) {
    snapshot(0, nodes)
    |> string.replace("\"v\":1", "\"v\":2")
    |> string.replace("\"value\":", "\"deleted\":false,\"value\":")
  }

  [
    [live_null, live_null],
    [node("A", 7, json.null(), node_id("A", 7))],
    [
      node("A", 7, json.null(), node_id("B", 8)),
      node("B", 8, json.null(), node_id("A", 7)),
    ],
  ]
  |> list.each(fn(nodes) {
    let assert Error(json.UnableToDecode(_)) =
      encode(nodes)
      |> sequence.from_json(decode.success(Nil))
  })

  let assert Ok(decoded) =
    encode([live_null])
    |> sequence.from_json(decode.success(Nil))
  assert sequence.values(decoded) == [Nil]
  let assert Ok(updated) = sequence.insert(decoded, 0, Nil)
  assert sequence.values(updated) == [Nil, Nil]
  assert sequence.length(updated) == 2
  let encoded =
    sequence.to_json(updated, fn(_) { json.null() })
    |> json.to_string()
  let assert Ok(8) =
    json.parse(encoded, decode.at(["state", "counter"], decode.int))
  assert sequence.from_json(encoded, decode.success(Nil)) == Ok(updated)
}

pub fn optional_payload_snapshots_and_deltas_round_trip_test() {
  let empty = sequence.new(rid("A"))
  let assert Ok(#(null_state, null_delta)) =
    sequence.insert_with_delta(empty, 0, None)
  let assert Ok(#(populated, nonnull_delta)) =
    sequence.insert_with_delta(null_state, 1, Some("kept"))
  let assert Ok(#(deleted, delete_delta)) =
    sequence.delete_with_delta(populated, 0)
  let decoder = decode.optional(decode.string)
  let encode = fn(value) { json.nullable(value, json.string) }

  [
    #(null_state, null_delta, empty),
    #(populated, nonnull_delta, null_state),
    #(deleted, delete_delta, populated),
  ]
  |> list.each(fn(pair) {
    let #(state, delta, previous) = pair
    let assert Ok(snapshot) =
      sequence.to_json(state, encode)
      |> json.to_string()
      |> sequence.from_json(decoder)
    let assert Ok(decoded_delta) =
      sequence.to_json(delta, encode)
      |> json.to_string()
      |> sequence.from_json(decoder)

    assert snapshot == state
    assert decoded_delta == delta
    assert sequence.merge(state, snapshot, rid("A")) == state
    assert sequence.merge(snapshot, state, rid("A")) == state
    assert sequence.merge(previous, decoded_delta, rid("A")) == state
    assert sequence.merge(decoded_delta, previous, rid("A")) == state
  })
  assert sequence.values(populated) == [None, Some("kept")]
  assert sequence.values(deleted) == [Some("kept")]
}

pub fn legacy_v1_retains_null_as_tombstone_test() {
  let legacy =
    "{\"type\":\"fugue\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counter\":2,\"nodes\":[{\"id\":{\"replica_id\":\"A\",\"counter\":1},\"value\":null,\"parent\":null,\"side\":\"right\"},{\"id\":{\"replica_id\":\"A\",\"counter\":2},\"value\":\"kept\",\"parent\":{\"replica_id\":\"A\",\"counter\":1},\"side\":\"right\"}]}}"
  let assert Ok(decoded) =
    sequence.from_json(legacy, decode.optional(decode.string))
  assert sequence.values(decoded) == [Some("kept")]
  assert sequence.length(decoded) == 1
  let assert Ok(upgraded) =
    sequence.to_json(decoded, json.nullable(_, json.string))
    |> json.to_string()
    |> sequence.from_json(decode.optional(decode.string))
  assert upgraded == decoded

  let assert Ok(null_payloads) = sequence.from_json(legacy, decode.success(Nil))
  assert sequence.values(null_payloads) == [Nil]
}

pub fn v2_requires_explicit_deletion_and_valid_payload_test() {
  let live =
    "{\"type\":\"fugue\",\"v\":2,\"state\":{\"self_id\":\"A\",\"counter\":1,\"nodes\":[{\"id\":{\"replica_id\":\"A\",\"counter\":1},\"deleted\":false,\"value\":\"kept\",\"parent\":null,\"side\":\"right\"}]}}"
  [
    string.replace(live, "\"deleted\":false,", ""),
    string.replace(live, "\"deleted\":false", "\"deleted\":null"),
    string.replace(live, "\"deleted\":false", "\"deleted\":\"false\""),
    string.replace(live, "\"deleted\":false", "\"deleted\":true"),
    string.replace(live, "\"value\":\"kept\"", "\"value\":null"),
  ]
  |> list.each(fn(invalid) {
    let assert Error(_) = sequence.from_json(invalid, decode.string)
  })
}

fn node(
  replica: String,
  counter: Int,
  value: json.Json,
  parent: json.Json,
) -> json.Json {
  json.object([
    #("id", node_id(replica, counter)),
    #("value", value),
    #("parent", parent),
    #("side", json.string("right")),
  ])
}

fn node_id(replica: String, counter: Int) -> json.Json {
  json.object([
    #("replica_id", json.string(replica)),
    #("counter", json.int(counter)),
  ])
}

fn snapshot(counter: Int, nodes: List(json.Json)) -> String {
  json.object([
    #("type", json.string("fugue")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("self_id", json.string("A")),
        #("counter", json.int(counter)),
        #("nodes", json.array(nodes, fn(node) { node })),
      ]),
    ),
  ])
  |> json.to_string()
}

fn counter(seq: sequence.Sequence(String)) -> Int {
  let assert Ok(counter) =
    seq
    |> sequence.to_json(json.string)
    |> json.to_string()
    |> json.parse({
      use counter <- decode.subfield(["state", "counter"], decode.int)
      decode.success(counter)
    })
  counter
}

pub fn decoded_counter_covers_retained_ids_and_preserves_higher_counter_test() {
  [0, 20]
  |> list.each(fn(encoded_counter) {
    let assert Ok(decoded) =
      snapshot(encoded_counter, [
        node("A", 1, json.string("old"), json.null()),
      ])
      |> sequence.from_json(decode.string)
    let assert Ok(updated) = sequence.insert(decoded, 0, "new")
    assert sequence.values(updated) == ["new", "old"]
    assert sequence.length(updated) == 2
    assert counter(updated) > encoded_counter
    assert counter(updated) > 1
  })
}

pub fn decoded_counter_covers_other_identities_and_tombstones_test() {
  let assert Ok(decoded) =
    snapshot(0, [
      node("B", 8, json.null(), json.null()),
      node("A", 1, json.string("old"), node_id("B", 8)),
    ])
    |> sequence.from_json(decode.string)

  [
    sequence.merge(decoded, sequence.new(rid("B")), rid("B")),
    sequence.merge(sequence.new(rid("B")), decoded, rid("B")),
    sequence.merge_as(sequence.new(rid("B")), decoded, rid("B")),
  ]
  |> list.each(fn(rebound) {
    let assert Ok(updated) = sequence.insert(rebound, 0, "new")
    assert sequence.values(updated) == ["new", "old"]
    assert counter(updated) == 9
    assert round_trip(updated) == Ok(updated)
  })
}

pub fn decoded_sparse_parent_reserves_id_until_parent_arrives_test() {
  let assert Ok(sparse) =
    snapshot(0, [
      node("A", 2, json.string("child"), node_id("B", 40)),
    ])
    |> sequence.from_json(decode.string)
  assert sequence.values(sparse) == []
  assert round_trip(sparse) == Ok(sparse)
  let rebound = sequence.merge_as(sequence.new(rid("B")), sparse, rid("B"))
  let assert Ok(updated) = sequence.insert(rebound, 0, "new")
  assert counter(updated) == 41

  let assert Ok(parent) =
    snapshot(0, [node("B", 40, json.string("parent"), json.null())])
    |> sequence.from_json(decode.string)
  let merged = sequence.merge(updated, parent, rid("B"))
  assert sequence.values(merged) == ["parent", "child", "new"]
  assert sequence.length(merged) == 3
}

pub fn duplicate_node_ids_are_rejected_test() {
  let first = node("A", 1, json.string("first"), json.null())
  [first, node("A", 1, json.string("conflict"), json.null())]
  |> list.each(fn(duplicate) {
    let assert Error(json.UnableToDecode(_)) =
      snapshot(1, [first, duplicate])
      |> sequence.from_json(decode.string)
  })
}

pub fn retained_parent_cycles_are_rejected_test() {
  [
    [node("A", 1, json.string("self"), node_id("A", 1))],
    [
      node("A", 1, json.string("a"), node_id("B", 2)),
      node("B", 2, json.string("b"), node_id("A", 1)),
    ],
    [
      node("A", 1, json.string("root"), json.null()),
      node("A", 2, json.string("tail"), node_id("B", 3)),
      node("B", 3, json.null(), node_id("C", 4)),
      node("C", 4, json.string("c"), node_id("B", 3)),
    ],
  ]
  |> list.each(fn(nodes) {
    let assert Error(json.UnableToDecode(_)) =
      snapshot(4, nodes)
      |> sequence.from_json(decode.string)
  })
}

pub fn decoded_siblings_can_share_validated_parent_paths_test() {
  let assert Ok(decoded) =
    snapshot(0, [
      node("A", 1, json.string("root"), json.null()),
      node("A", 2, json.string("a"), node_id("A", 1)),
      node("A", 3, json.string("b"), node_id("A", 1)),
      node("A", 4, json.string("c"), node_id("A", 2)),
    ])
    |> sequence.from_json(decode.string)
  assert sequence.values(decoded) == ["root", "a", "c", "b"]
}
