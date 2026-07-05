//// A non-interleaving sequence CRDT implementing plain Fugue.
////
//// Fugue (Weidner & Kleppmann, "The Art of the Fugue: Minimizing Interleaving
//// in Collaborative Text Editing", arXiv:2305.00583) orders concurrent
//// insertions so that runs of insertions performed concurrently at the same
//// position end up as separate subtrees, and a depth-first traversal keeps
//// each run contiguous instead of interleaving it with a concurrent run. This
//// is the ordering guarantee that YATA-style CRDTs (like `lattice_sequence`)
//// do not provide: they converge, but concurrent runs can interleave.
////
//// This module reshapes the paper's operation-based tree as a **state-based**
//// CRDT. Each node stores only immutable structural facts — its `parent` and
//// `side` are decided once at creation and never recomputed — so the tree is a
//// pure function of the node set and `merge` is a plain union keyed by node
//// ID. Deletes tombstone a node's value; the node itself is retained because
//// it may be an ancestor of live nodes.
////
//// The public editing API exposes index-based insert and delete while
//// resolving internal node identifiers, so callers never construct node IDs.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_fugue/sequence
////
//// let list =
////   sequence.new(replica_id.new("node-a"))
////   |> sequence.insert(0, "hello")
////   |> sequence.insert(1, "world")
////
//// sequence.values(list)  // -> ["hello", "world"]
//// ```

import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import lattice_core/replica_id.{type ReplicaId}

/// The internal identity of a tree node.
///
/// Opaque: nothing in this package's scope exposes node identity outside the
/// package. A `NodeId` pairs the minting replica with a per-replica counter,
/// which together are globally unique.
pub opaque type NodeId {
  NodeId(replica_id: ReplicaId, counter: Int)
}

/// Which side of its parent a node attaches to.
pub type Side {
  Left
  Right
}

type Node(a) {
  Node(id: NodeId, value: Option(a), parent: Option(NodeId), side: Side)
}

/// A non-interleaving sequence CRDT value.
pub opaque type Sequence(a) {
  Sequence(replica_id: ReplicaId, counter: Int, nodes: Dict(NodeId, Node(a)))
}

/// An error returned when an insert cannot be applied.
pub type InsertError {
  IndexOutOfBounds(index: Int, length: Int)
}

/// An error returned when a delete cannot be applied.
pub type DeleteError {
  DeleteIndexOutOfBounds(index: Int, length: Int)
}

/// Create an empty sequence for a replica.
pub fn new(replica_id: ReplicaId) -> Sequence(a) {
  Sequence(replica_id: replica_id, counter: 0, nodes: dict.new())
}

// ---------------------------------------------------------------------------
// Traversal
// ---------------------------------------------------------------------------

/// Children of a given parent on a given side, sorted deterministically.
///
/// The paper notes same-side sibling order (by ID) does not affect
/// correctness, only determinism; we sort by `(counter, replica_id)` to match
/// the rest of the library's Lamport ordering convention.
fn children(
  nodes: Dict(NodeId, Node(a)),
  parent: Option(NodeId),
  side: Side,
) -> List(NodeId) {
  nodes
  |> dict.values()
  |> list.filter(fn(node) { node.parent == parent && node.side == side })
  |> list.map(fn(node) { node.id })
  |> list.sort(compare_node_ids)
}

/// Depth-first in-order walk of the whole tree, tombstones included.
///
/// For each node: its left children (recursively), the node itself, then its
/// right children (recursively). Starting parent is `None` (the virtual root).
fn full_order(nodes: Dict(NodeId, Node(a))) -> List(NodeId) {
  traverse(nodes, None)
}

fn traverse(
  nodes: Dict(NodeId, Node(a)),
  parent: Option(NodeId),
) -> List(NodeId) {
  let lefts =
    children(nodes, parent, Left)
    |> list.flat_map(fn(id) { traverse(nodes, Some(id)) })
  let rights =
    children(nodes, parent, Right)
    |> list.flat_map(fn(id) { traverse(nodes, Some(id)) })
  case parent {
    None -> list.append(lefts, rights)
    Some(id) -> list.append(lefts, [id, ..rights])
  }
}

/// Return all visible values in sequence order.
pub fn values(sequence: Sequence(a)) -> List(a) {
  full_order(sequence.nodes)
  |> list.filter_map(fn(id) {
    case dict.get(sequence.nodes, id) {
      Ok(node) ->
        case node.value {
          Some(value) -> Ok(value)
          None -> Error(Nil)
        }
      Error(Nil) -> Error(Nil)
    }
  })
}

/// Return the count of visible values.
pub fn length(sequence: Sequence(a)) -> Int {
  dict.fold(sequence.nodes, 0, fn(count, _id, node) {
    case node.value {
      Some(_) -> count + 1
      None -> count
    }
  })
}

/// The list of node IDs whose value is visible, in traversal order.
fn visible_ids(nodes: Dict(NodeId, Node(a))) -> List(NodeId) {
  full_order(nodes)
  |> list.filter(fn(id) {
    case dict.get(nodes, id) {
      Ok(node) ->
        case node.value {
          Some(_) -> True
          None -> False
        }
      Error(Nil) -> False
    }
  })
}

// ---------------------------------------------------------------------------
// Insert
// ---------------------------------------------------------------------------

/// Insert a value at the visible item index.
///
/// Panics with `IndexOutOfBounds` when `index` is outside `[0, length]`. Use
/// `try_insert_with_delta` to handle an untrusted index without crashing.
pub fn insert(sequence: Sequence(a), index: Int, value: a) -> Sequence(a) {
  let assert Ok(#(updated, _delta)) =
    try_insert_with_delta(sequence, index, value)
  updated
}

/// Insert a value and return both the updated sequence and insertion delta.
///
/// Panics with `IndexOutOfBounds` when `index` is outside `[0, length]`. Use
/// `try_insert_with_delta` to handle an untrusted index without crashing.
pub fn insert_with_delta(
  sequence: Sequence(a),
  index: Int,
  value: a,
) -> #(Sequence(a), Sequence(a)) {
  let assert Ok(result) = try_insert_with_delta(sequence, index, value)
  result
}

/// Safely insert a value and return both the updated sequence and insertion
/// delta.
///
/// A Fugue delta is always exactly one node, since parent/side never change
/// after creation.
pub fn try_insert_with_delta(
  sequence: Sequence(a),
  index: Int,
  value: a,
) -> Result(#(Sequence(a), Sequence(a)), InsertError) {
  let visible = visible_ids(sequence.nodes)
  let size = list.length(visible)

  case index < 0 || index > size {
    True -> Error(IndexOutOfBounds(index: index, length: size))
    False -> {
      let next_counter = sequence.counter + 1
      let id = NodeId(replica_id: sequence.replica_id, counter: next_counter)

      // left_origin is the visible node just before the insertion point, or
      // None (the virtual root) when inserting at the front.
      let left_origin = case index {
        0 -> None
        _ -> nth(visible, index - 1)
      }

      let node = case has_right_children(sequence.nodes, left_origin) {
        False ->
          Node(id: id, value: Some(value), parent: left_origin, side: Right)
        True -> {
          // left_origin has right children, so per Theorem 1's proof its
          // right-origin exists in full order, is a descendant of left_origin
          // with no left children, and is safe to attach a new left child to.
          let right_origin =
            successor_in_full_order(sequence.nodes, left_origin)
          Node(id: id, value: Some(value), parent: right_origin, side: Left)
        }
      }

      let nodes = dict.insert(sequence.nodes, id, node)
      let updated = Sequence(..sequence, counter: next_counter, nodes: nodes)
      Ok(#(updated, delta_sequence(sequence.replica_id, next_counter, node)))
    }
  }
}

/// Whether `parent` has any right children in the tree. A `None` parent means
/// the virtual root, which can gain right children like any other node.
fn has_right_children(
  nodes: Dict(NodeId, Node(a)),
  parent: Option(NodeId),
) -> Bool {
  case children(nodes, parent, Right) {
    [] -> False
    _ -> True
  }
}

/// The node that immediately follows `origin` in the full (tombstone-included)
/// traversal order. Only called when `origin` is known to have a successor.
fn successor_in_full_order(
  nodes: Dict(NodeId, Node(a)),
  origin: Option(NodeId),
) -> Option(NodeId) {
  let order = full_order(nodes)
  case origin {
    // A None origin means "before everything"; its successor is the first node.
    None -> list.first(order) |> option.from_result()
    Some(origin_id) -> successor_after(order, origin_id)
  }
}

fn successor_after(order: List(NodeId), target: NodeId) -> Option(NodeId) {
  case order {
    [] -> None
    [head, ..rest] ->
      case head == target {
        True -> list.first(rest) |> option.from_result()
        False -> successor_after(rest, target)
      }
  }
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

/// Delete the value at the visible item index.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
/// Use `try_delete_with_delta` to handle an untrusted index without crashing.
pub fn delete(sequence: Sequence(a), index: Int) -> Sequence(a) {
  let assert Ok(#(updated, _delta)) = try_delete_with_delta(sequence, index)
  updated
}

/// Delete a value and return both the updated sequence and deletion delta.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside `[0, length)`.
/// Use `try_delete_with_delta` to handle an untrusted index without crashing.
pub fn delete_with_delta(
  sequence: Sequence(a),
  index: Int,
) -> #(Sequence(a), Sequence(a)) {
  let assert Ok(result) = try_delete_with_delta(sequence, index)
  result
}

/// Safely delete a value and return both the updated sequence and deletion
/// delta.
///
/// Deletes tombstone the node by setting its value to `None`; the node's
/// identity/parent/side are retained because it may be an ancestor of live
/// (including concurrently-inserted) nodes. The local counter is bumped for
/// parity with the rest of the library's delete-dot convention.
pub fn try_delete_with_delta(
  sequence: Sequence(a),
  index: Int,
) -> Result(#(Sequence(a), Sequence(a)), DeleteError) {
  let visible = visible_ids(sequence.nodes)
  let size = list.length(visible)

  case index < 0 || index >= size {
    True -> Error(DeleteIndexOutOfBounds(index: index, length: size))
    False ->
      case nth(visible, index) {
        None -> Error(DeleteIndexOutOfBounds(index: index, length: size))
        Some(target_id) -> {
          let assert Ok(target) = dict.get(sequence.nodes, target_id)
          let tombstoned = Node(..target, value: None)
          let nodes = dict.insert(sequence.nodes, target_id, tombstoned)
          let next_counter = sequence.counter + 1
          let updated =
            Sequence(..sequence, counter: next_counter, nodes: nodes)
          let delta =
            delta_sequence(sequence.replica_id, next_counter, tombstoned)
          Ok(#(updated, delta))
        }
      }
  }
}

// ---------------------------------------------------------------------------
// Merge
// ---------------------------------------------------------------------------

/// Merge two sequence CRDT states.
///
/// Because a node's `parent`/`side` are creation-time invariants and never
/// recomputed, merge is a plain union keyed by node ID. Nodes present on one
/// side only are kept as is; nodes present on both sides have identical
/// structure by invariant, and their value joins as "tombstone wins": `None`
/// if either side is `None`, else the (necessarily equal) `Some(value)`.
///
/// Sibling order and traversal order are pure functions of the resulting node
/// set, so no re-integration pass is needed and convergence is immediate.
pub fn merge(a: Sequence(a), b: Sequence(a)) -> Sequence(a) {
  let nodes =
    dict.fold(b.nodes, a.nodes, fn(acc, id, b_node) {
      case dict.get(acc, id) {
        Error(Nil) -> dict.insert(acc, id, b_node)
        Ok(a_node) -> dict.insert(acc, id, merge_node(a_node, b_node))
      }
    })
  Sequence(
    replica_id: a.replica_id,
    counter: int.max(a.counter, b.counter),
    nodes: nodes,
  )
}

fn merge_node(a: Node(a), b: Node(a)) -> Node(a) {
  // parent/side are identical by invariant; tombstone wins on value.
  let value = case a.value, b.value {
    None, _ -> None
    _, None -> None
    Some(v), Some(_) -> Some(v)
  }
  Node(..a, value: value)
}

// ---------------------------------------------------------------------------
// JSON serialization
// ---------------------------------------------------------------------------

/// Encode a sequence CRDT as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`. The
/// state includes this replica ID, local counter, and a flat array of nodes
/// (`id`, `value` (nullable), `parent` (nullable), `side`), tombstones
/// included.
pub fn to_json(
  sequence: Sequence(a),
  encode_value: fn(a) -> json.Json,
) -> json.Json {
  json.object([
    #("type", json.string("fugue")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("self_id", replica_id.to_json(sequence.replica_id)),
        #("counter", json.int(sequence.counter)),
        #(
          "nodes",
          json.array(dict.values(sequence.nodes), encode_node(_, encode_value)),
        ),
      ]),
    ),
  ])
}

/// Decode a sequence CRDT from a JSON string produced by `to_json`.
///
/// Returns `Ok(Sequence)` on success, or `Error(json.DecodeError)` if the
/// input is not a valid Fugue JSON envelope.
pub fn from_json(
  json_string: String,
  value_decoder: decode.Decoder(a),
) -> Result(Sequence(a), json.DecodeError) {
  let state_decoder = {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", replica_id.decoder())
      use counter <- decode.field("counter", non_negative_int_decoder())
      use nodes <- decode.field(
        "nodes",
        decode.list(node_decoder(value_decoder)),
      )
      let node_dict =
        list.fold(nodes, dict.new(), fn(acc, node) {
          dict.insert(acc, node.id, node)
        })
      decode.success(Sequence(
        replica_id: self_id,
        counter: counter,
        nodes: node_dict,
      ))
    })
    decode.success(state)
  }
  let envelope_decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(type_tag, version))
  }

  case json.parse(from: json_string, using: envelope_decoder) {
    Error(e) -> Error(e)
    Ok(#(type_tag, version)) ->
      case type_tag == "fugue" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=fugue and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

fn encode_node(node: Node(a), encode_value: fn(a) -> json.Json) -> json.Json {
  json.object([
    #("id", encode_node_id(node.id)),
    #("value", encode_optional_value(node.value, encode_value)),
    #("parent", encode_optional_node_id(node.parent)),
    #("side", encode_side(node.side)),
  ])
}

fn encode_optional_value(
  value: Option(a),
  encode_value: fn(a) -> json.Json,
) -> json.Json {
  case value {
    Some(v) -> encode_value(v)
    None -> json.null()
  }
}

fn encode_optional_node_id(id: Option(NodeId)) -> json.Json {
  case id {
    Some(node_id) -> encode_node_id(node_id)
    None -> json.null()
  }
}

fn encode_node_id(id: NodeId) -> json.Json {
  let NodeId(rid, counter) = id
  json.object([
    #("replica_id", json.string(replica_id.to_string(rid))),
    #("counter", json.int(counter)),
  ])
}

fn encode_side(side: Side) -> json.Json {
  case side {
    Left -> json.string("left")
    Right -> json.string("right")
  }
}

fn node_decoder(value_decoder: decode.Decoder(a)) -> decode.Decoder(Node(a)) {
  use id <- decode.field("id", node_id_decoder())
  use value <- decode.field("value", decode.optional(value_decoder))
  use parent <- decode.field("parent", decode.optional(node_id_decoder()))
  use side <- decode.field("side", side_decoder())
  decode.success(Node(id: id, value: value, parent: parent, side: side))
}

fn node_id_decoder() -> decode.Decoder(NodeId) {
  use rid <- decode.field("replica_id", replica_id.decoder())
  use counter <- decode.field("counter", non_negative_int_decoder())
  decode.success(NodeId(replica_id: rid, counter: counter))
}

fn side_decoder() -> decode.Decoder(Side) {
  use tag <- decode.then(decode.string)
  case tag {
    "left" -> decode.success(Left)
    "right" -> decode.success(Right)
    other ->
      decode.failure(Left, "a side (\"left\" or \"right\"), got " <> other)
  }
}

fn non_negative_int_decoder() -> decode.Decoder(Int) {
  decode.int
  |> decode.then(fn(val) {
    case val >= 0 {
      True -> decode.success(val)
      False -> decode.failure(val, "a non-negative integer")
    }
  })
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn delta_sequence(
  replica_id: ReplicaId,
  counter: Int,
  node: Node(a),
) -> Sequence(a) {
  Sequence(
    replica_id: replica_id,
    counter: counter,
    nodes: dict.from_list([#(node.id, node)]),
  )
}

fn compare_node_ids(a: NodeId, b: NodeId) -> order.Order {
  let NodeId(a_rid, a_counter) = a
  let NodeId(b_rid, b_counter) = b
  case int.compare(a_counter, b_counter) {
    order.Eq -> replica_id.compare(a_rid, b_rid)
    other -> other
  }
}

fn nth(items: List(a), index: Int) -> Option(a) {
  items |> list.drop(index) |> list.first() |> option.from_result()
}
