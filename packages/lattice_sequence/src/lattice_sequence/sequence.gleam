//// A generic sequence CRDT using stable item IDs and YATA-style origins.
////
//// Each item is stored with a stable internal ID plus left and right origins
//// for deterministic ordering. Deletes are represented as tombstones; `values`
//// returns only non-deleted items.
////
//// The public editing API exposes index-based insert, delete, and move
//// operations while resolving stable item IDs internally, so callers do not
//// need to construct or manage item identifiers. Moves preserve item identity
//// and converge with single-winner semantics for concurrent moves of the same
//// item.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_sequence/sequence
////
//// let list =
////   sequence.new(replica_id.new("node-a"))
////   |> sequence.insert(0, "hello")
////   |> sequence.insert(1, "world")
////   |> sequence.move(0, 1)
////
//// sequence.values(list)  // -> ["world", "hello"]
//// ```

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import lattice_core/replica_id.{type ReplicaId}

pub opaque type ItemId {
  ItemId(replica_id: ReplicaId, counter: Int)
}

type OpId {
  OpId(replica_id: ReplicaId, counter: Int)
}

type Move {
  Move(op_id: OpId, origin_left: Option(ItemId), origin_right: Option(ItemId))
}

type Item(a) {
  Item(
    id: ItemId,
    origin_left: Option(ItemId),
    origin_right: Option(ItemId),
    value: a,
    deleted: Bool,
    move: Option(Move),
  )
}

pub opaque type Sequence(a) {
  Sequence(replica_id: ReplicaId, counter: Int, items: List(Item(a)))
}

/// An error returned when an insert cannot be applied.
pub type InsertError {
  IndexOutOfBounds(index: Int, length: Int)
}

/// An error returned when a delete cannot be applied.
pub type DeleteError {
  DeleteIndexOutOfBounds(index: Int, length: Int)
}

/// An error returned when a move cannot be applied.
pub type MoveError {
  MoveFromIndexOutOfBounds(index: Int, length: Int)
  MoveToIndexOutOfBounds(index: Int, length_after_removal: Int)
}

/// Create an empty sequence for a replica.
pub fn new(replica_id: ReplicaId) -> Sequence(a) {
  Sequence(replica_id: replica_id, counter: 0, items: [])
}

/// Insert a value at the visible item index.
pub fn insert(sequence: Sequence(a), index: Int, value: a) -> Sequence(a) {
  let assert Ok(updated) = try_insert(sequence, index, value)
  updated
}

/// Safely insert a value at the visible item index.
pub fn try_insert(
  sequence: Sequence(a),
  index: Int,
  value: a,
) -> Result(Sequence(a), InsertError) {
  case try_insert_with_delta(sequence, index, value) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Insert a value and return both the updated sequence and insertion delta.
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
pub fn try_insert_with_delta(
  sequence: Sequence(a),
  index: Int,
  value: a,
) -> Result(#(Sequence(a), Sequence(a)), InsertError) {
  let Sequence(replica_id, counter, items) = sequence
  let size = visible_length(items)

  case index < 0 || index > size {
    True -> Error(IndexOutOfBounds(index: index, length: size))
    False -> {
      let next_counter = counter + 1
      let id = ItemId(replica_id: replica_id, counter: next_counter)
      let origin_left = case index {
        0 -> None
        _ -> visible_item_id_at(items, index - 1)
      }
      let origin_right = visible_item_id_at(items, index)
      let item =
        Item(
          id: id,
          origin_left: origin_left,
          origin_right: origin_right,
          value: value,
          deleted: False,
          move: None,
        )
      let updated =
        Sequence(
          replica_id: replica_id,
          counter: next_counter,
          items: insert_item(items, origin_right, item),
        )
      let delta =
        Sequence(replica_id: replica_id, counter: next_counter, items: [item])

      Ok(#(updated, delta))
    }
  }
}

/// Delete the value at the visible item index.
pub fn delete(sequence: Sequence(a), index: Int) -> Sequence(a) {
  let assert Ok(updated) = try_delete(sequence, index)
  updated
}

/// Safely delete the value at the visible item index.
pub fn try_delete(
  sequence: Sequence(a),
  index: Int,
) -> Result(Sequence(a), DeleteError) {
  case try_delete_with_delta(sequence, index) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Delete a value and return both the updated sequence and deletion delta.
pub fn delete_with_delta(
  sequence: Sequence(a),
  index: Int,
) -> #(Sequence(a), Sequence(a)) {
  let assert Ok(result) = try_delete_with_delta(sequence, index)
  result
}

/// Safely delete a value and return both the updated sequence and deletion
/// delta.
pub fn try_delete_with_delta(
  sequence: Sequence(a),
  index: Int,
) -> Result(#(Sequence(a), Sequence(a)), DeleteError) {
  let Sequence(replica_id, counter, items) = sequence
  let size = visible_length(items)

  case index < 0 || index >= size {
    True -> Error(DeleteIndexOutOfBounds(index: index, length: size))
    False -> {
      let assert Some(#(updated_items, deleted_item)) =
        delete_visible_item_at(items, index, 0)
      let updated =
        Sequence(replica_id: replica_id, counter: counter, items: updated_items)
      let delta =
        Sequence(replica_id: replica_id, counter: counter, items: [deleted_item])

      Ok(#(updated, delta))
    }
  }
}

/// Move a visible item to another visible index.
///
/// The `to_index` is interpreted after removing the item from `from_index`.
pub fn move(
  sequence: Sequence(a),
  from_index: Int,
  to_index: Int,
) -> Sequence(a) {
  let assert Ok(updated) = try_move(sequence, from_index, to_index)
  updated
}

/// Safely move a visible item to another visible index.
///
/// The `to_index` is interpreted after removing the item from `from_index`.
pub fn try_move(
  sequence: Sequence(a),
  from_index: Int,
  to_index: Int,
) -> Result(Sequence(a), MoveError) {
  case try_move_with_delta(sequence, from_index, to_index) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Move a visible item and return both the updated sequence and move delta.
pub fn move_with_delta(
  sequence: Sequence(a),
  from_index: Int,
  to_index: Int,
) -> #(Sequence(a), Sequence(a)) {
  let assert Ok(result) = try_move_with_delta(sequence, from_index, to_index)
  result
}

/// Safely move a visible item and return both the updated sequence and move
/// delta.
pub fn try_move_with_delta(
  sequence: Sequence(a),
  from_index: Int,
  to_index: Int,
) -> Result(#(Sequence(a), Sequence(a)), MoveError) {
  let Sequence(replica_id, counter, items) = sequence
  let size = visible_length(items)

  case from_index < 0 || from_index >= size {
    True -> Error(MoveFromIndexOutOfBounds(index: from_index, length: size))
    False -> {
      let length_after_removal = size - 1
      case to_index < 0 || to_index > length_after_removal {
        True ->
          Error(MoveToIndexOutOfBounds(
            index: to_index,
            length_after_removal: length_after_removal,
          ))
        False -> {
          let assert Some(item) = visible_item_at(items, from_index)
          let visible_without_item = visible_items_except_id(items, item.id)
          let origin_left = case to_index {
            0 -> None
            _ -> visible_item_id_in_list(visible_without_item, to_index - 1)
          }
          let origin_right =
            visible_item_id_in_list(visible_without_item, to_index)
          let next_counter = counter + 1
          let moved_item =
            Item(
              id: item.id,
              origin_left: item.origin_left,
              origin_right: item.origin_right,
              value: item.value,
              deleted: item.deleted,
              move: Some(Move(
                op_id: OpId(replica_id: replica_id, counter: next_counter),
                origin_left: origin_left,
                origin_right: origin_right,
              )),
            )
          let updated =
            Sequence(
              replica_id: replica_id,
              counter: next_counter,
              items: replace_item(items, moved_item) |> order_items(),
            )
          let delta =
            Sequence(replica_id: replica_id, counter: next_counter, items: [
              moved_item,
            ])

          Ok(#(updated, delta))
        }
      }
    }
  }
}

/// Return all visible values in sequence order.
pub fn values(sequence: Sequence(a)) -> List(a) {
  let Sequence(_, _, items) = sequence
  items
  |> list.filter(fn(item) { !item.deleted })
  |> list.map(fn(item) { item.value })
}

/// Return the count of visible values.
pub fn length(sequence: Sequence(a)) -> Int {
  let Sequence(_, _, items) = sequence
  visible_length(items)
}

/// Merge two sequence CRDT states.
///
/// Items are joined by their stable IDs. Concurrent deletes are preserved by
/// OR-ing tombstones, and the merged item set is deterministically reordered
/// using each item's left and right origins.
pub fn merge(a: Sequence(a), b: Sequence(a)) -> Sequence(a) {
  let Sequence(replica_id, a_counter, a_items) = a
  let Sequence(_, b_counter, b_items) = b

  Sequence(
    replica_id: replica_id,
    counter: int.max(a_counter, b_counter),
    items: merge_items(a_items, b_items) |> order_items(),
  )
}

/// Encode a sequence CRDT as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`. The
/// state includes this replica ID, local counter, and every item including
/// tombstones.
pub fn to_json(
  sequence: Sequence(a),
  encode_value: fn(a) -> json.Json,
) -> json.Json {
  let Sequence(replica_id, counter, items) = sequence

  json.object([
    #("type", json.string("sequence")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("self_id", replica_id.to_json(replica_id)),
        #("counter", json.int(counter)),
        #("items", json.array(items, encode_item(_, encode_value))),
      ]),
    ),
  ])
}

/// Decode a sequence CRDT from a JSON string produced by `to_json`.
///
/// Returns `Ok(Sequence)` on success, or `Error(json.DecodeError)` if the input
/// is not a valid sequence JSON envelope. Items are reordered deterministically
/// from their stable origins before the `Sequence` is returned.
pub fn from_json(
  json_string: String,
  value_decoder: decode.Decoder(a),
) -> Result(Sequence(a), json.DecodeError) {
  let non_negative_int =
    decode.int
    |> decode.then(fn(val) {
      case val >= 0 {
        True -> decode.success(val)
        False -> decode.failure(val, "a non-negative integer")
      }
    })
  let item_id_decoder = {
    use rid <- decode.field("replica_id", replica_id.decoder())
    use counter <- decode.field("counter", non_negative_int)
    decode.success(ItemId(replica_id: rid, counter: counter))
  }
  let item_decoder = {
    use id <- decode.field("id", item_id_decoder)
    use origin_left <- decode.field(
      "origin_left",
      decode.optional(item_id_decoder),
    )
    use origin_right <- decode.field(
      "origin_right",
      decode.optional(item_id_decoder),
    )
    use value <- decode.field("value", value_decoder)
    use deleted <- decode.field("deleted", decode.bool)
    use move <- decode.optional_field(
      "move",
      None,
      decode.optional(move_decoder(item_id_decoder, non_negative_int)),
    )
    decode.success(Item(
      id: id,
      origin_left: origin_left,
      origin_right: origin_right,
      value: value,
      deleted: deleted,
      move: move,
    ))
  }
  let state_decoder = {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", replica_id.decoder())
      use counter <- decode.field("counter", non_negative_int)
      use items <- decode.field("items", decode.list(item_decoder))
      decode.success(Sequence(
        replica_id: self_id,
        counter: counter,
        items: order_items(items),
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
      case type_tag == "sequence" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=sequence and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

fn move_decoder(
  item_id_decoder: decode.Decoder(ItemId),
  non_negative_int: decode.Decoder(Int),
) -> decode.Decoder(Move) {
  let op_id_decoder = {
    use rid <- decode.field("replica_id", replica_id.decoder())
    use counter <- decode.field("counter", non_negative_int)
    decode.success(OpId(replica_id: rid, counter: counter))
  }

  {
    use op_id <- decode.field("op_id", op_id_decoder)
    use origin_left <- decode.field(
      "origin_left",
      decode.optional(item_id_decoder),
    )
    use origin_right <- decode.field(
      "origin_right",
      decode.optional(item_id_decoder),
    )
    decode.success(Move(
      op_id: op_id,
      origin_left: origin_left,
      origin_right: origin_right,
    ))
  }
}

fn encode_item(item: Item(a), encode_value: fn(a) -> json.Json) -> json.Json {
  json.object([
    #("id", encode_item_id(item.id)),
    #("origin_left", encode_optional_item_id(item.origin_left)),
    #("origin_right", encode_optional_item_id(item.origin_right)),
    #("value", encode_value(item.value)),
    #("deleted", json.bool(item.deleted)),
    #("move", encode_optional_move(item.move)),
  ])
}

fn encode_optional_move(move: Option(Move)) -> json.Json {
  case move {
    None -> json.null()
    Some(Move(op_id, origin_left, origin_right)) ->
      json.object([
        #("op_id", encode_op_id(op_id)),
        #("origin_left", encode_optional_item_id(origin_left)),
        #("origin_right", encode_optional_item_id(origin_right)),
      ])
  }
}

fn encode_op_id(id: OpId) -> json.Json {
  let OpId(rid, counter) = id

  json.object([
    #("replica_id", json.string(replica_id.to_string(rid))),
    #("counter", json.int(counter)),
  ])
}

fn encode_optional_item_id(item_id: Option(ItemId)) -> json.Json {
  case item_id {
    Some(id) -> encode_item_id(id)
    None -> json.null()
  }
}

fn encode_item_id(id: ItemId) -> json.Json {
  let ItemId(rid, counter) = id

  json.object([
    #("replica_id", json.string(replica_id.to_string(rid))),
    #("counter", json.int(counter)),
  ])
}

fn visible_length(items: List(Item(a))) -> Int {
  items
  |> list.filter(fn(item) { !item.deleted })
  |> list.length()
}

fn visible_item_id_at(items: List(Item(a)), index: Int) -> Option(ItemId) {
  visible_item_at(items, index)
  |> option.map(fn(item) { item.id })
}

fn visible_item_at(items: List(Item(a)), index: Int) -> Option(Item(a)) {
  visible_item_at_loop(items, index, 0)
}

fn visible_item_at_loop(
  items: List(Item(a)),
  target: Int,
  current: Int,
) -> Option(Item(a)) {
  case items {
    [] -> None
    [Item(_, _, _, _, True, _), ..rest] ->
      visible_item_at_loop(rest, target, current)
    [item, ..rest] ->
      case current == target {
        True -> Some(item)
        False -> visible_item_at_loop(rest, target, current + 1)
      }
  }
}

fn visible_items_except_id(items: List(Item(a)), id: ItemId) -> List(Item(a)) {
  items
  |> list.filter(fn(item) { !item.deleted && item.id != id })
}

fn visible_item_id_in_list(items: List(Item(a)), index: Int) -> Option(ItemId) {
  case items {
    [] -> None
    [item, ..rest] ->
      case index == 0 {
        True -> Some(item.id)
        False -> visible_item_id_in_list(rest, index - 1)
      }
  }
}

fn delete_visible_item_at(
  items: List(Item(a)),
  target: Int,
  current: Int,
) -> Option(#(List(Item(a)), Item(a))) {
  case items {
    [] -> None
    [item, ..rest] -> {
      let Item(id, origin_left, origin_right, value, deleted, move) = item
      case deleted {
        True -> {
          case delete_visible_item_at(rest, target, current) {
            Some(#(updated_rest, deleted_item)) ->
              Some(#([item, ..updated_rest], deleted_item))
            None -> None
          }
        }
        False -> {
          case current == target {
            True -> {
              let deleted_item =
                Item(
                  id: id,
                  origin_left: origin_left,
                  origin_right: origin_right,
                  value: value,
                  deleted: True,
                  move: move,
                )

              Some(#([deleted_item, ..rest], deleted_item))
            }
            False -> {
              case delete_visible_item_at(rest, target, current + 1) {
                Some(#(updated_rest, deleted_item)) ->
                  Some(#([item, ..updated_rest], deleted_item))
                None -> None
              }
            }
          }
        }
      }
    }
  }
}

fn insert_item(
  items: List(Item(a)),
  origin_right: Option(ItemId),
  item: Item(a),
) -> List(Item(a)) {
  case origin_right {
    None -> list.append(items, [item])
    Some(right) -> insert_before_id(items, right, item)
  }
}

fn insert_before_id(
  items: List(Item(a)),
  right: ItemId,
  item: Item(a),
) -> List(Item(a)) {
  case items {
    [] -> [item]
    [first, ..rest] -> {
      let Item(id, _, _, _, _, _) = first
      case id == right {
        True -> [item, first, ..rest]
        False -> [first, ..insert_before_id(rest, right, item)]
      }
    }
  }
}

fn merge_items(
  a_items: List(Item(a)),
  b_items: List(Item(a)),
) -> List(Item(a)) {
  list.fold(b_items, a_items, fn(items, item) { upsert_item(items, item) })
}

fn upsert_item(items: List(Item(a)), item: Item(a)) -> List(Item(a)) {
  case items {
    [] -> [item]
    [first, ..rest] -> {
      let Item(first_id, _, _, _, _, _) = first
      let Item(item_id, _, _, _, _, _) = item

      case first_id == item_id {
        True -> [merge_item(first, item), ..rest]
        False -> [first, ..upsert_item(rest, item)]
      }
    }
  }
}

fn replace_item(items: List(Item(a)), item: Item(a)) -> List(Item(a)) {
  case items {
    [] -> [item]
    [first, ..rest] ->
      case first.id == item.id {
        True -> [item, ..rest]
        False -> [first, ..replace_item(rest, item)]
      }
  }
}

fn merge_item(a: Item(a), b: Item(a)) -> Item(a) {
  let Item(id, origin_left, origin_right, value, a_deleted, a_move) = a
  let Item(_, _, _, _, b_deleted, b_move) = b

  Item(
    id: id,
    origin_left: origin_left,
    origin_right: origin_right,
    value: value,
    deleted: a_deleted || b_deleted,
    move: merge_move(a_move, b_move),
  )
}

fn merge_move(a: Option(Move), b: Option(Move)) -> Option(Move) {
  case a, b {
    None, None -> None
    Some(move), None -> Some(move)
    None, Some(move) -> Some(move)
    Some(a_move), Some(b_move) ->
      case compare_moves(a_move, b_move) {
        order.Lt -> Some(b_move)
        order.Eq -> Some(a_move)
        order.Gt -> Some(a_move)
      }
  }
}

fn compare_moves(a: Move, b: Move) -> order.Order {
  let Move(a_op_id, _, _) = a
  let Move(b_op_id, _, _) = b
  compare_op_ids(a_op_id, b_op_id)
}

fn compare_op_ids(a: OpId, b: OpId) -> order.Order {
  let OpId(a_replica, a_counter) = a
  let OpId(b_replica, b_counter) = b

  case int.compare(a_counter, b_counter) {
    order.Eq -> replica_id.compare(a_replica, b_replica)
    other -> other
  }
}

fn order_items(items: List(Item(a))) -> List(Item(a)) {
  let base_order = order_after(items, None)

  items
  |> list.filter(has_move)
  |> list.sort(compare_item_moves)
  |> list.fold(base_order, apply_move_to_order)
}

fn has_move(item: Item(a)) -> Bool {
  option.is_some(item.move)
}

fn compare_item_moves(a: Item(a), b: Item(a)) -> order.Order {
  case a.move, b.move {
    Some(a_move), Some(b_move) ->
      case compare_moves(a_move, b_move) {
        order.Eq -> compare_item_ids(a.id, b.id)
        other -> other
      }
    Some(_), None -> order.Gt
    None, Some(_) -> order.Lt
    None, None -> compare_item_ids(a.id, b.id)
  }
}

fn apply_move_to_order(
  ordered: List(Item(a)),
  moved_item: Item(a),
) -> List(Item(a)) {
  let without_item = remove_item_by_id(ordered, moved_item.id)

  case moved_item.move {
    None -> ordered
    Some(Move(_, origin_left, origin_right)) ->
      case origin_right {
        Some(right_id) ->
          case contains_item_id(without_item, right_id) {
            True -> insert_before_id(without_item, right_id, moved_item)
            False ->
              insert_after_left_anchor(without_item, origin_left, moved_item)
          }
        None -> insert_after_left_anchor(without_item, origin_left, moved_item)
      }
  }
}

fn remove_item_by_id(items: List(Item(a)), id: ItemId) -> List(Item(a)) {
  case items {
    [] -> []
    [item, ..rest] ->
      case item.id == id {
        True -> rest
        False -> [item, ..remove_item_by_id(rest, id)]
      }
  }
}

fn insert_after_left_anchor(
  items: List(Item(a)),
  origin_left: Option(ItemId),
  item: Item(a),
) -> List(Item(a)) {
  case origin_left {
    None -> [item, ..items]
    Some(left_id) ->
      case contains_item_id(items, left_id) {
        True -> insert_after_id(items, left_id, item)
        False -> list.append(items, [item])
      }
  }
}

fn insert_after_id(
  items: List(Item(a)),
  left: ItemId,
  item: Item(a),
) -> List(Item(a)) {
  case items {
    [] -> [item]
    [first, ..rest] ->
      case first.id == left {
        True -> [first, item, ..rest]
        False -> [first, ..insert_after_id(rest, left, item)]
      }
  }
}

fn order_after(
  items: List(Item(a)),
  origin_left: Option(ItemId),
) -> List(Item(a)) {
  items
  |> list.filter(fn(item) { is_child_of(items, item, origin_left) })
  |> list.sort(compare_siblings)
  |> list.fold([], fn(ordered, item) {
    list.append(ordered, [item, ..order_after(items, Some(item.id))])
  })
}

fn is_child_of(
  items: List(Item(a)),
  item: Item(a),
  origin_left: Option(ItemId),
) -> Bool {
  case origin_left {
    Some(_) -> item.origin_left == origin_left
    None ->
      case item.origin_left {
        None -> True
        Some(left_id) -> !contains_item_id(items, left_id)
      }
  }
}

fn contains_item_id(items: List(Item(a)), id: ItemId) -> Bool {
  list.any(items, fn(item) { item.id == id })
}

fn compare_siblings(a: Item(a), b: Item(a)) -> order.Order {
  case a.id == b.id {
    True -> order.Eq
    False ->
      case a.origin_right == Some(b.id), b.origin_right == Some(a.id) {
        True, True -> compare_item_ids(a.id, b.id)
        True, False -> order.Lt
        False, True -> order.Gt
        False, False -> compare_unanchored_siblings(a, b)
      }
  }
}

fn compare_unanchored_siblings(a: Item(a), b: Item(a)) -> order.Order {
  case a.origin_right == b.origin_right {
    True -> compare_item_ids(a.id, b.id)
    False -> compare_origin_right(a.origin_right, b.origin_right)
  }
}

fn compare_origin_right(a: Option(ItemId), b: Option(ItemId)) -> order.Order {
  case a, b {
    Some(a_id), Some(b_id) -> compare_item_ids(a_id, b_id)
    Some(_), None -> order.Lt
    None, Some(_) -> order.Gt
    None, None -> order.Eq
  }
}

fn compare_item_ids(a: ItemId, b: ItemId) -> order.Order {
  let ItemId(a_replica, a_counter) = a
  let ItemId(b_replica, b_counter) = b

  case replica_id.compare(a_replica, b_replica) {
    order.Eq -> int.compare(a_counter, b_counter)
    other -> other
  }
}
