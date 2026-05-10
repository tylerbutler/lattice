//// A plain-text CRDT using stable item IDs and YATA-style origins.
////
//// Each character or text segment is stored as an item with a stable internal
//// ID plus left and right origins for deterministic ordering. Deletes are
//// represented as tombstones; `value` returns only non-deleted items.
////
//// The public editing API will expose index-based insert and delete operations
//// while resolving stable item IDs internally, so callers do not need to
//// construct or manage item identifiers.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_text/text
////
//// let doc = text.new(replica_id.new("node-a"))
//// text.value(doc)  // -> ""
//// ```

import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/string
import lattice_core/replica_id.{type ReplicaId}

pub opaque type ItemId {
  ItemId(replica_id: ReplicaId, counter: Int)
}

type Item {
  Item(
    id: ItemId,
    origin_left: Option(ItemId),
    origin_right: Option(ItemId),
    value: String,
    deleted: Bool,
  )
}

pub opaque type Text {
  Text(replica_id: ReplicaId, counter: Int, items: List(Item))
}

/// An error returned when an insert cannot be applied.
pub type InsertError {
  IndexOutOfBounds(index: Int, length: Int)
}

/// An error returned when a delete cannot be applied.
pub type DeleteError {
  DeleteIndexOutOfBounds(index: Int, length: Int)
}

pub fn new(replica_id: ReplicaId) -> Text {
  Text(replica_id: replica_id, counter: 0, items: [])
}

/// Insert a value at the visible character index.
pub fn insert(text: Text, index: Int, value: String) -> Text {
  let assert Ok(updated) = try_insert(text, index, value)
  updated
}

/// Safely insert a value at the visible character index.
pub fn try_insert(
  text: Text,
  index: Int,
  value: String,
) -> Result(Text, InsertError) {
  case try_insert_with_delta(text, index, value) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Insert a value and return both the updated text and insertion delta.
pub fn insert_with_delta(
  text: Text,
  index: Int,
  value: String,
) -> #(Text, Text) {
  let assert Ok(result) = try_insert_with_delta(text, index, value)
  result
}

/// Safely insert a value and return both the updated text and insertion delta.
pub fn try_insert_with_delta(
  text: Text,
  index: Int,
  value: String,
) -> Result(#(Text, Text), InsertError) {
  let Text(replica_id, counter, items) = text
  let length = visible_length(items)

  case index < 0 || index > length {
    True -> Error(IndexOutOfBounds(index: index, length: length))
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
        )
      let updated =
        Text(
          replica_id: replica_id,
          counter: next_counter,
          items: insert_item(items, origin_right, item),
        )
      let delta =
        Text(replica_id: replica_id, counter: next_counter, items: [item])

      Ok(#(updated, delta))
    }
  }
}

/// Delete the value at the visible character index.
pub fn delete(text: Text, index: Int) -> Text {
  let assert Ok(updated) = try_delete(text, index)
  updated
}

/// Safely delete the value at the visible character index.
pub fn try_delete(text: Text, index: Int) -> Result(Text, DeleteError) {
  case try_delete_with_delta(text, index) {
    Ok(#(updated, _delta)) -> Ok(updated)
    Error(error) -> Error(error)
  }
}

/// Delete a value and return both the updated text and deletion delta.
pub fn delete_with_delta(text: Text, index: Int) -> #(Text, Text) {
  let assert Ok(result) = try_delete_with_delta(text, index)
  result
}

/// Safely delete a value and return both the updated text and deletion delta.
pub fn try_delete_with_delta(
  text: Text,
  index: Int,
) -> Result(#(Text, Text), DeleteError) {
  let Text(replica_id, counter, items) = text
  let length = visible_length(items)

  case index < 0 || index >= length {
    True -> Error(DeleteIndexOutOfBounds(index: index, length: length))
    False -> {
      let assert Some(#(updated_items, deleted_item)) =
        delete_visible_item_at(items, index, 0)
      let updated =
        Text(replica_id: replica_id, counter: counter, items: updated_items)
      let delta =
        Text(replica_id: replica_id, counter: counter, items: [deleted_item])

      Ok(#(updated, delta))
    }
  }
}

pub fn values(text: Text) -> List(String) {
  let Text(_, _, items) = text
  items
  |> list.filter(fn(item) { !item.deleted })
  |> list.map(fn(item) { item.value })
}

pub fn value(text: Text) -> String {
  text
  |> values()
  |> string.concat()
}

/// Merge two text CRDT states.
///
/// Items are joined by their stable IDs. Concurrent deletes are preserved by
/// OR-ing tombstones, and the merged item set is deterministically reordered
/// using each item's left and right origins.
pub fn merge(a: Text, b: Text) -> Text {
  let Text(replica_id, a_counter, a_items) = a
  let Text(_, b_counter, b_items) = b

  Text(
    replica_id: replica_id,
    counter: int.max(a_counter, b_counter),
    items: merge_items(a_items, b_items) |> order_items(),
  )
}

/// Encode a text CRDT as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`. The
/// state includes this replica ID, local counter, and every item including
/// tombstones.
pub fn to_json(text: Text) -> json.Json {
  let Text(replica_id, counter, items) = text

  json.object([
    #("type", json.string("text")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("self_id", replica_id.to_json(replica_id)),
        #("counter", json.int(counter)),
        #("items", json.array(items, encode_item)),
      ]),
    ),
  ])
}

/// Decode a text CRDT from a JSON string produced by `to_json`.
///
/// Returns `Ok(Text)` on success, or `Error(json.DecodeError)` if the input is
/// not a valid text JSON envelope. Items are reordered deterministically from
/// their stable origins before the `Text` is returned.
pub fn from_json(json_string: String) -> Result(Text, json.DecodeError) {
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
    use value <- decode.field("value", decode.string)
    use deleted <- decode.field("deleted", decode.bool)
    decode.success(Item(
      id: id,
      origin_left: origin_left,
      origin_right: origin_right,
      value: value,
      deleted: deleted,
    ))
  }
  let state_decoder = {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", replica_id.decoder())
      use counter <- decode.field("counter", non_negative_int)
      use items <- decode.field("items", decode.list(item_decoder))
      decode.success(Text(
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
      case type_tag == "text" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=text and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

fn encode_item(item: Item) -> json.Json {
  json.object([
    #("id", encode_item_id(item.id)),
    #("origin_left", encode_optional_item_id(item.origin_left)),
    #("origin_right", encode_optional_item_id(item.origin_right)),
    #("value", json.string(item.value)),
    #("deleted", json.bool(item.deleted)),
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

fn visible_length(items: List(Item)) -> Int {
  items
  |> list.filter(fn(item) { !item.deleted })
  |> list.length()
}

fn visible_item_id_at(items: List(Item), index: Int) -> Option(ItemId) {
  visible_item_id_at_loop(items, index, 0)
}

fn visible_item_id_at_loop(
  items: List(Item),
  target: Int,
  current: Int,
) -> Option(ItemId) {
  case items {
    [] -> None
    [Item(_, _, _, _, True), ..rest] ->
      visible_item_id_at_loop(rest, target, current)
    [Item(id, _, _, _, False), ..rest] ->
      case current == target {
        True -> Some(id)
        False -> visible_item_id_at_loop(rest, target, current + 1)
      }
  }
}

fn delete_visible_item_at(
  items: List(Item),
  target: Int,
  current: Int,
) -> Option(#(List(Item), Item)) {
  case items {
    [] -> None
    [item, ..rest] -> {
      let Item(id, origin_left, origin_right, value, deleted) = item
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
  items: List(Item),
  origin_right: Option(ItemId),
  item: Item,
) -> List(Item) {
  case origin_right {
    None -> list.append(items, [item])
    Some(right) -> insert_before_id(items, right, item)
  }
}

fn insert_before_id(
  items: List(Item),
  right: ItemId,
  item: Item,
) -> List(Item) {
  case items {
    [] -> [item]
    [first, ..rest] -> {
      let Item(id, _, _, _, _) = first
      case id == right {
        True -> [item, first, ..rest]
        False -> [first, ..insert_before_id(rest, right, item)]
      }
    }
  }
}

fn merge_items(a_items: List(Item), b_items: List(Item)) -> List(Item) {
  list.fold(b_items, a_items, fn(items, item) { upsert_item(items, item) })
}

fn upsert_item(items: List(Item), item: Item) -> List(Item) {
  case items {
    [] -> [item]
    [first, ..rest] -> {
      let Item(first_id, _, _, _, _) = first
      let Item(item_id, _, _, _, _) = item

      case first_id == item_id {
        True -> [merge_item(first, item), ..rest]
        False -> [first, ..upsert_item(rest, item)]
      }
    }
  }
}

fn merge_item(a: Item, b: Item) -> Item {
  let Item(id, origin_left, origin_right, value, a_deleted) = a
  let Item(_, _, _, _, b_deleted) = b

  Item(
    id: id,
    origin_left: origin_left,
    origin_right: origin_right,
    value: value,
    deleted: a_deleted || b_deleted,
  )
}

fn order_items(items: List(Item)) -> List(Item) {
  order_after(items, None)
}

fn order_after(items: List(Item), origin_left: Option(ItemId)) -> List(Item) {
  items
  |> list.filter(fn(item) { is_child_of(items, item, origin_left) })
  |> list.sort(compare_siblings)
  |> list.fold([], fn(ordered, item) {
    list.append(ordered, [item, ..order_after(items, Some(item.id))])
  })
}

fn is_child_of(
  items: List(Item),
  item: Item,
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

fn contains_item_id(items: List(Item), id: ItemId) -> Bool {
  list.any(items, fn(item) { item.id == id })
}

fn compare_siblings(a: Item, b: Item) -> order.Order {
  case a.id == b.id {
    True -> order.Eq
    False ->
      case a.origin_right == Some(b.id), b.origin_right == Some(a.id) {
        True, _ -> order.Lt
        _, True -> order.Gt
        False, False -> compare_unanchored_siblings(a, b)
      }
  }
}

fn compare_unanchored_siblings(a: Item, b: Item) -> order.Order {
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
