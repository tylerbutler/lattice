import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_fugue/sequence

fn node_id(counter: Int) -> json.Json {
  json.object([
    #("replica_id", json.string("A")),
    #("counter", json.int(counter)),
  ])
}

fn chain(size: Int, side: sequence.Side) -> sequence.Sequence(Int) {
  let nodes =
    counters(size)
    |> list.map(fn(counter) {
      let parent = case counter {
        1 -> json.null()
        _ -> node_id(counter - 1)
      }
      let side = case counter {
        1 -> sequence.Right
        _ -> side
      }
      node(node_id(counter), parent, side, counter)
    })
  snapshot(nodes, size)
}

fn node(
  id: json.Json,
  parent: json.Json,
  side: sequence.Side,
  value: Int,
) -> json.Json {
  json.object([
    #("id", id),
    #("deleted", json.bool(False)),
    #("value", json.int(value)),
    #("parent", parent),
    #(
      "side",
      json.string(case side {
        sequence.Left -> "left"
        sequence.Right -> "right"
      }),
    ),
  ])
}

fn snapshot(nodes: List(json.Json), counter: Int) -> sequence.Sequence(Int) {
  let encoded =
    json.object([
      #("type", json.string("fugue")),
      #("v", json.int(2)),
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
  let assert Ok(decoded) = sequence.from_json(encoded, decode.int)
  decoded
}

pub fn decoded_chains_match_incremental_insertion_test() -> Nil {
  list.each([sequence.Left, sequence.Right], fn(side) {
    let typed =
      counters(40)
      |> list.fold(sequence.new(replica_id.new("A")), fn(document, value) {
        let index = case side {
          sequence.Left -> 0
          sequence.Right -> value - 1
        }
        let assert Ok(updated) = sequence.insert(document, index, value)
        updated
      })
    assert chain(40, side) == typed
  })
}

pub fn deep_chains_support_queries_edits_and_anchors_test() -> Nil {
  list.each([sequence.Right, sequence.Left], fn(side) {
    let document = chain(20_000, side)
    let expected = case side {
      sequence.Right -> counters(20_000)
      sequence.Left -> counters(20_000) |> list.reverse()
    }
    assert sequence.values(document) == expected
    let assert Ok(before) =
      sequence.anchor_at(document, 10_000, sequence.Before)
    let assert Ok(after) = sequence.anchor_at(document, 10_001, sequence.After)
    let assert Ok(appended) = sequence.insert(document, 20_000, 20_001)
    assert sequence.values(appended) == list.append(expected, [20_001])
    let assert Ok(deleted) = sequence.delete(appended, 10_000)
    let remaining =
      list.append(list.take(expected, 10_000), list.drop(expected, 10_001))
      |> list.append([20_001])
    assert sequence.values(deleted) == remaining
    assert sequence.resolve(deleted, before) == Ok(10_000)
    assert sequence.resolve(deleted, after) == Ok(10_000)
    assert sequence.resolve(deleted, sequence.end_anchor()) == Ok(20_000)

    let local = replica_id.new("peer")
    let merged = sequence.merge(sequence.new(local), deleted, local)
    assert sequence.values(merged) == remaining
    let encoded = sequence.to_json(merged, json.int) |> json.to_string()
    let assert Ok(decoded) = sequence.from_json(encoded, decode.int)
    assert decoded == merged
    assert sequence.values(decoded) == remaining
    assert sequence.resolve(decoded, before) == Ok(10_000)
    let assert Ok(prepended) = sequence.insert(deleted, 0, 0)
    assert sequence.values(prepended) == [0, ..remaining]
  })
}

pub fn siblings_keep_counter_then_replica_order_on_both_sides_test() -> Nil {
  let peer_id =
    json.object([
      #("replica_id", json.string("B")),
      #("counter", json.int(2)),
    ])
  let nodes = [
    node(node_id(1), json.null(), sequence.Right, 10),
    node(peer_id, node_id(1), sequence.Left, 22),
    node(node_id(2), node_id(1), sequence.Left, 21),
    node(node_id(3), node_id(1), sequence.Left, 30),
    node(node_id(4), node_id(1), sequence.Right, 40),
    node(node_id(5), json.null(), sequence.Left, 50),
    node(node_id(6), json.null(), sequence.Right, 60),
  ]
  list.each([nodes, list.reverse(nodes)], fn(nodes) {
    let document = snapshot(nodes, 6)
    assert sequence.values(document) == [50, 21, 22, 30, 10, 40, 60]
  })
}

pub fn deep_sparse_chain_attaches_only_when_ancestor_arrives_test() -> Nil {
  let document = chain(20_000, sequence.Right)
  let assert Ok(#(updated, delta)) =
    sequence.insert_with_delta(document, 20_000, 20_001)
  let local = replica_id.new("peer")
  let sparse = sequence.merge(sequence.new(local), delta, local)
  assert sequence.values(sparse) == []
  let encoded = sequence.to_json(sparse, json.int) |> json.to_string()
  let assert Ok(decoded) = sequence.from_json(encoded, decode.int)
  assert decoded == sparse
  list.each(
    [
      sequence.merge(decoded, document, local),
      sequence.merge(document, decoded, local),
    ],
    fn(merged) {
      assert sequence.values(merged) == sequence.values(updated)
    },
  )
}

fn counters(size: Int) -> List(Int) {
  int.range(1, size + 1, [], fn(items, counter) { [counter, ..items] })
  |> list.reverse()
}
