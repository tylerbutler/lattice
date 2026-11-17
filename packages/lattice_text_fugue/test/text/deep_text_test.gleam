import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_fugue/sequence
import lattice_text_fugue/text

fn node_id(counter: Int) -> json.Json {
  json.object([
    #("replica_id", json.string("A")),
    #("counter", json.int(counter)),
  ])
}

fn decoded_text(size: Int) -> text.Text {
  let nodes =
    int.range(1, size + 1, [], fn(nodes, counter) {
      let parent = case counter {
        1 -> json.null()
        _ -> node_id(counter - 1)
      }
      let node =
        json.object([
          #("id", node_id(counter)),
          #("deleted", json.bool(False)),
          #("value", json.string("x")),
          #("parent", parent),
          #("side", json.string("right")),
        ])
      [node, ..nodes]
    })
  let encoded =
    json.object([
      #("type", json.string("fugue")),
      #("v", json.int(2)),
      #(
        "state",
        json.object([
          #("self_id", json.string("A")),
          #("counter", json.int(size)),
          #("nodes", json.array(nodes, fn(node) { node })),
        ]),
      ),
    ])
    |> json.to_string()
  let assert Ok(document) = text.from_json(encoded)
  document
}

pub fn deep_fixture_matches_public_typing_test() -> Nil {
  let typed =
    list.repeat("x", 40)
    |> list.fold(text.new(replica_id.new("A")), fn(document, value) {
      let assert Ok(updated) = text.append(document, value)
      updated
    })
  assert decoded_text(40) == typed
}

pub fn deep_text_supports_read_append_delete_merge_and_anchors_test() -> Nil {
  let document = decoded_text(20_000)
  let expected = string.repeat("x", 20_000)
  assert text.value(document) == expected
  assert text.values(document) == list.repeat("x", 20_000)
  let assert Ok(anchor) = text.anchor_at(document, 19_999, sequence.Before)
  let assert Ok(appended) = text.append(document, "!")
  assert text.value(appended) == expected <> "!"
  let assert Ok(deleted) = text.delete(appended, 19_999)
  let remaining = string.repeat("x", 19_999) <> "!"
  assert text.value(deleted) == remaining
  assert text.resolve_anchor(deleted, anchor) == Ok(19_999)
  let local = replica_id.new("peer")
  let merged = text.merge(text.new(local), deleted, local)
  let assert Ok(decoded) =
    text.to_json(merged) |> json.to_string() |> text.from_json()
  assert decoded == merged
  assert text.value(decoded) == remaining
  assert text.resolve_anchor(decoded, anchor) == Ok(19_999)
}
