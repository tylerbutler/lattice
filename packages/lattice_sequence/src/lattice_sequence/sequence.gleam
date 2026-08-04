//// A generic sequence CRDT using stable item IDs and YATA-style origins.
////
//// Each live item is stored with a stable internal ID plus left and right
//// origins for deterministic ordering. Deletes are represented as tombstones
//// that record the delete's op ID; `values` returns only non-deleted items.
////
//// The public editing API exposes index-based insert, delete, and move
//// operations while resolving stable item IDs internally, so callers do not
//// need to construct or manage item identifiers. Moves preserve item identity
//// and converge with single-winner semantics for concurrent moves of the same
//// item.
////
//// ## Compaction
////
//// Long-lived sequences never shrink on their own: every delete leaves a
//// tombstone and every item carries origins. `compact` takes a stability
//// frontier — a `VersionVector` meaning "everything causally at or below
//// this is stable; no in-flight or future op references it" — and rewrites
//// the stable region: stable tombstones are dropped, runs of adjacent stable
//// items from the same replica with sequential counters are merged into
//// compact blocks, and origins of stable items are discarded. Items above
//// the frontier keep their full YATA representation.
////
//// Every dropped ID gets a forwarding entry pointing at its retained
//// neighbors, so anchors and rebased operations that still hold the ID can
//// resolve to the gap it left behind. The forwarding map and the applied
//// frontier travel with the state. Deriving a correct frontier is the
//// host's job (e.g. from a global sequencer's acknowledgement floor); the
//// frontier must be a causal cut over the ops applied to the sequence.
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

import gleam/bool
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}

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
    deleted: Option(OpId),
    move: Option(Move),
  )
}

/// Stored representation: compact blocks of stable items interleaved with
/// full YATA items. A block covers implicit sequential IDs starting at
/// `first_id`; block members carry no origins or move slots.
type Segment(a) {
  Block(first_id: ItemId, values: List(a))
  Live(Item(a))
}

/// Internal working representation: one element per stored position. Blocks
/// are expanded to `(id, value)` pairs (never to full items) for passes that
/// need per-position granularity, then re-chunked into segments.
type Element(a) {
  Stable(id: ItemId, value: a)
  LiveEl(Item(a))
}

/// A forwarding records the nearest retained neighbors of a compacted ID at
/// the moment it was dropped.
type Forwarding {
  Forwarding(left: Option(ItemId), right: Option(ItemId))
}

/// The forwarding entries emitted by one `compact` pass.
///
/// Each entry maps a dropped item ID to the gap it left behind. The library
/// keeps the cumulative map inside the sequence for anchor resolution and
/// origin translation; retention is the host's policy — keep the map returned
/// by each `compact` round and expire old rounds with `remove_forwardings`.
pub opaque type ForwardingMap {
  ForwardingMap(entries: Dict(ItemId, Forwarding))
}

pub opaque type Sequence(a) {
  Sequence(
    replica_id: ReplicaId,
    counter: Int,
    segments: List(Segment(a)),
    forwardings: Dict(ItemId, Forwarding),
    frontier: VersionVector,
  )
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

/// An error returned when a delta's origins cannot be translated onto a
/// compacted state.
pub type TranslateError {
  /// An origin references an ID that is neither present nor forwarded —
  /// its forwarding entry has expired. The host must degrade the op (e.g.
  /// re-insert by position) or drop it.
  UnknownOriginTarget
}

/// Which side of its gap an anchor sticks to when content is inserted
/// exactly at the anchor position.
pub type Bias {
  /// Attach to the item after the gap: inserts at the gap push the anchor
  /// right, so it stays glued to its item.
  Before
  /// Attach to the item before the gap: inserts at the gap land after the
  /// anchor, so it stays put.
  After
}

/// A stable position between items (positions `0..length` inclusive).
///
/// Anchors are created from a visible index with `anchor_at` and resolved
/// back to a current index with `resolve` after any sequence of local edits
/// and merges. They live outside the CRDT state: creating and resolving
/// anchors never mutates the sequence.
pub opaque type Anchor {
  Start
  End
  AtItem(id: ItemId, bias: Bias)
}

/// An error returned when an anchor cannot be created or resolved.
pub type AnchorError {
  AnchorIndexOutOfBounds(index: Int, length: Int)
  /// The anchor references an item this replica cannot locate: either it was
  /// created remotely and not merged yet, or it was compacted away and its
  /// forwarding entry has expired. Treat this as "re-anchor".
  UnknownAnchorTarget
}

/// Create an empty sequence for a replica.
pub fn new(replica_id: ReplicaId) -> Sequence(a) {
  Sequence(
    replica_id: replica_id,
    counter: 0,
    segments: [],
    forwardings: dict.new(),
    frontier: version_vector.new(),
  )
}

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
pub fn try_insert_with_delta(
  sequence: Sequence(a),
  index: Int,
  value: a,
) -> Result(#(Sequence(a), Sequence(a)), InsertError) {
  try_insert_many_with_delta(sequence, index, [value])
}

/// Insert several values at consecutive visible indices starting at `index`.
///
/// `values` are placed in order — the first at `index`, the next at
/// `index + 1`, and so on — exactly as looping `insert` would, but the whole
/// run is spliced in a single pass and reported as one delta. Panics with
/// `IndexOutOfBounds` when `index` is outside `[0, length]`. Use
/// `try_insert_many_with_delta` to handle an untrusted index without crashing.
pub fn insert_many(
  sequence: Sequence(a),
  index: Int,
  values: List(a),
) -> Sequence(a) {
  let assert Ok(#(updated, _delta)) =
    try_insert_many_with_delta(sequence, index, values)
  updated
}

/// Insert several values and return both the updated sequence and the merged
/// insertion delta covering every new item.
///
/// Panics with `IndexOutOfBounds` when `index` is outside `[0, length]`. Use
/// `try_insert_many_with_delta` to handle an untrusted index without crashing.
pub fn insert_many_with_delta(
  sequence: Sequence(a),
  index: Int,
  values: List(a),
) -> #(Sequence(a), Sequence(a)) {
  let assert Ok(result) = try_insert_many_with_delta(sequence, index, values)
  result
}

/// Safely insert several values at consecutive visible indices starting at
/// `index`, returning the updated sequence and a single delta of all new
/// items.
///
/// Each new item's left origin is the previous new item (the first pins to the
/// visible left neighbor) and every item shares the same right origin — the
/// left neighbor's canonical successor — so the run integrates contiguously on
/// every replica. When the state holds no live move record, stored order is
/// already the canonical order, so the run is spliced directly in place rather
/// than re-deriving the whole order; otherwise it falls back to a full rebuild.
pub fn try_insert_many_with_delta(
  sequence: Sequence(a),
  index: Int,
  values: List(a),
) -> Result(#(Sequence(a), Sequence(a)), InsertError) {
  let elements = segments_to_elements(sequence.segments)
  let visible = apply_moves(elements, sequence.forwardings)
  let size = visible_length_elements(elements)

  case index < 0 || index > size {
    True -> Error(IndexOutOfBounds(index: index, length: size))
    False ->
      case values {
        [] -> Ok(#(sequence, empty_delta(sequence.replica_id)))
        _ -> {
          // The left origin is the visible left neighbor in the user's (move-
          // applied) view; the right origin is that element's successor in the
          // CANONICAL pre-move order. This makes the conflict window between an
          // item's origins empty in canonical space at creation, so on every
          // replica the window can only ever contain concurrently integrated
          // volatile items — never a compacted element.
          let origin_left = case index {
            0 -> None
            _ -> visible_element_id_at(visible, index - 1)
          }
          // Stored order IS the canonical base, so its stored successor is
          // the canonical successor — no rebuild needed even with moves live.
          let origin_right = canonical_successor(elements, origin_left)
          let #(items, last_counter) =
            build_insert_run(
              sequence.replica_id,
              sequence.counter + 1,
              values,
              origin_left,
              origin_right,
            )
          let new_elements = list.map(items, LiveEl)
          // The run's origins name a gap in the base, so splicing it there is
          // exactly where integration would put it on every replica.
          let updated_elements =
            splice_run_after(elements, origin_left, new_elements)
          let updated =
            Sequence(
              ..sequence,
              counter: last_counter,
              segments: elements_to_segments(updated_elements),
            )
          let delta =
            Sequence(
              replica_id: sequence.replica_id,
              counter: last_counter,
              segments: list.map(items, Live),
              forwardings: dict.new(),
              frontier: version_vector.new(),
            )

          Ok(#(updated, delta))
        }
      }
  }
}

/// Build a contiguous run of new items with chained left origins and a shared
/// right origin, minting consecutive counters from `start_counter`. Returns
/// the items in insertion order and the last counter used.
fn build_insert_run(
  replica_id: ReplicaId,
  start_counter: Int,
  values: List(a),
  origin_left: Option(ItemId),
  origin_right: Option(ItemId),
) -> #(List(Item(a)), Int) {
  let items =
    list.index_map(values, fn(value, offset) {
      // IDs are consecutive, so each item's left origin is simply the
      // previous item's (deterministic) ID; the first pins to origin_left.
      let left = case offset {
        0 -> origin_left
        _ ->
          Some(ItemId(
            replica_id: replica_id,
            counter: start_counter + offset - 1,
          ))
      }
      Item(
        id: ItemId(replica_id: replica_id, counter: start_counter + offset),
        origin_left: left,
        origin_right: origin_right,
        value: value,
        deleted: None,
        move: None,
      )
    })
  #(items, start_counter + list.length(values) - 1)
}

/// Splice a run of elements into the stored order immediately after `after`
/// (or at the head when `after` is `None`), preserving run order.
fn splice_run_after(
  elements: List(Element(a)),
  after: Option(ItemId),
  run: List(Element(a)),
) -> List(Element(a)) {
  case after {
    None -> list.append(run, elements)
    Some(id) -> insert_run_after_id(elements, id, run)
  }
}

fn insert_run_after_id(
  elements: List(Element(a)),
  after: ItemId,
  run: List(Element(a)),
) -> List(Element(a)) {
  case elements {
    [] -> run
    [first, ..rest] ->
      case element_id(first) == after {
        True -> [first, ..list.append(run, rest)]
        False -> [first, ..insert_run_after_id(rest, after, run)]
      }
  }
}

/// Delete the value at the visible item index.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside
/// `[0, length)`. Use `try_delete_with_delta` to handle an untrusted index
/// without crashing.
pub fn delete(sequence: Sequence(a), index: Int) -> Sequence(a) {
  let assert Ok(#(updated, _delta)) = try_delete_with_delta(sequence, index)
  updated
}

/// Delete a value and return both the updated sequence and deletion delta.
///
/// Panics with `DeleteIndexOutOfBounds` when `index` is outside
/// `[0, length)`. Use `try_delete_with_delta` to handle an untrusted index
/// without crashing.
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
/// Deletes mint an op ID (bumping this replica's counter) so a compaction
/// frontier can distinguish acknowledged deletes from in-flight ones.
pub fn try_delete_with_delta(
  sequence: Sequence(a),
  index: Int,
) -> Result(#(Sequence(a), Sequence(a)), DeleteError) {
  let elements = segments_to_elements(sequence.segments)
  let visible = apply_moves(elements, sequence.forwardings)
  let size = visible_length_elements(elements)

  case index < 0 || index >= size {
    True -> Error(DeleteIndexOutOfBounds(index: index, length: size))
    False -> {
      let next_counter = sequence.counter + 1
      let op = OpId(replica_id: sequence.replica_id, counter: next_counter)
      case tombstone_in_base(elements, visible, index, op) {
        Some(#(updated_elements, deleted_item)) -> {
          let updated =
            Sequence(
              ..sequence,
              counter: next_counter,
              segments: elements_to_segments(updated_elements),
            )
          let delta =
            delta_sequence(sequence.replica_id, next_counter, deleted_item)

          Ok(#(updated, delta))
        }
        None -> Error(DeleteIndexOutOfBounds(index: index, length: size))
      }
    }
  }
}

/// Move a visible item to another visible index.
///
/// The `to_index` is interpreted after removing the item from `from_index`.
///
/// Panics with a `MoveError` when either index is out of bounds. Use
/// `try_move_with_delta` to handle untrusted indices without crashing.
pub fn move(
  sequence: Sequence(a),
  from_index: Int,
  to_index: Int,
) -> Sequence(a) {
  let assert Ok(#(updated, _delta)) =
    try_move_with_delta(sequence, from_index, to_index)
  updated
}

/// Move a visible item and return both the updated sequence and move delta.
///
/// The `to_index` is interpreted after removing the item from `from_index`.
///
/// Panics with a `MoveError` when either index is out of bounds. Use
/// `try_move_with_delta` to handle untrusted indices without crashing.
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
  let elements = segments_to_elements(sequence.segments)
  let visible = apply_moves(elements, sequence.forwardings)
  let size = visible_length_elements(elements)
  let length_after_removal = size - 1

  case
    from_index < 0 || from_index >= size,
    to_index < 0 || to_index > length_after_removal
  {
    True, _ -> Error(MoveFromIndexOutOfBounds(index: from_index, length: size))
    _, True ->
      Error(MoveToIndexOutOfBounds(
        index: to_index,
        length_after_removal: length_after_removal,
      ))
    False, False ->
      move_visible_element(sequence, elements, visible, from_index, to_index)
  }
}

fn move_visible_element(
  sequence: Sequence(a),
  elements: List(Element(a)),
  visible: List(Element(a)),
  from_index: Int,
  to_index: Int,
) -> Result(#(Sequence(a), Sequence(a)), MoveError) {
  case base_item_at_visible_index(elements, visible, from_index) {
    None ->
      Error(MoveFromIndexOutOfBounds(
        index: from_index,
        length: visible_length_elements(elements),
      ))
    Some(item) -> {
      let remaining = list.filter(visible, fn(el) { element_id(el) != item.id })
      // Move origins are pure splice anchors (no YATA window), so they
      // reference VISIBLE neighbors: anything visible to the creator of a
      // volatile move cannot have been dropped at the floor the creator
      // acked, so volatile move targets always resolve.
      let origin_left = case to_index {
        0 -> None
        _ -> visible_element_id_at(remaining, to_index - 1)
      }
      let origin_right = visible_element_id_at(remaining, to_index)
      let next_counter = sequence.counter + 1
      let moved_item =
        Item(
          ..item,
          move: Some(Move(
            op_id: OpId(replica_id: sequence.replica_id, counter: next_counter),
            origin_left: origin_left,
            origin_right: origin_right,
          )),
        )
      let updated_elements =
        rebuild(
          swap_in_item(elements, moved_item),
          sequence.forwardings,
          sequence.frontier,
        )
      let updated =
        Sequence(
          ..sequence,
          counter: next_counter,
          segments: elements_to_segments(updated_elements),
        )
      let delta = delta_sequence(sequence.replica_id, next_counter, moved_item)

      Ok(#(updated, delta))
    }
  }
}

/// Create an anchor at the start of the sequence. Always resolves to 0.
pub fn start_anchor() -> Anchor {
  Start
}

/// Create an anchor at the end of the sequence. Always resolves to the
/// current visible length, tracking growth.
pub fn end_anchor() -> Anchor {
  End
}

/// Create an anchor at the gap before the visible item at `index`.
///
/// `Before` bias binds the anchor to the item at `index`; `After` bias binds
/// it to the item at `index - 1`. Boundary positions with no item on the
/// chosen side degrade to the start / end sentinels.
pub fn anchor_at(sequence: Sequence(a), index: Int, bias: Bias) -> Anchor {
  let assert Ok(anchor) = try_anchor_at(sequence, index, bias)
  anchor
}

/// Safely create an anchor at the gap before the visible item at `index`.
///
/// Valid positions are `0 <= index <= length`.
pub fn try_anchor_at(
  sequence: Sequence(a),
  index: Int,
  bias: Bias,
) -> Result(Anchor, AnchorError) {
  let elements = visible_elements(sequence)
  let size = visible_length_elements(elements)

  case index < 0 || index > size {
    True -> Error(AnchorIndexOutOfBounds(index: index, length: size))
    False ->
      case bias {
        Before ->
          case visible_element_id_at(elements, index) {
            Some(id) -> Ok(AtItem(id: id, bias: Before))
            None -> Ok(End)
          }
        After ->
          case visible_element_id_at(elements, index - 1) {
            Some(id) -> Ok(AtItem(id: id, bias: After))
            None -> Ok(Start)
          }
      }
  }
}

/// Resolve an anchor to a current visible index in `[0, length]`.
///
/// Anchors on deleted items still resolve: both biases collapse to the gap
/// where the item used to be. Anchors follow moved items. Panics with
/// `UnknownAnchorTarget` when the target was never merged or was compacted
/// and its forwarding has expired — hosts holding anchors across compaction
/// rounds should use `try_resolve` and treat failure as "re-anchor".
pub fn resolve(sequence: Sequence(a), anchor: Anchor) -> Int {
  let assert Ok(index) = try_resolve(sequence, anchor)
  index
}

/// Safely resolve an anchor to a current visible index in `[0, length]`.
///
/// Anchors to compacted items resolve through the forwarding map to the gap
/// the item left behind — semantically the same as tombstone collapse.
///
/// Returns `Error(UnknownAnchorTarget)` when the anchor references an item
/// this replica has never seen (created remotely and not yet merged), or one
/// that was compacted away and whose forwarding entry has since been removed
/// by the host's retention policy. Either way the anchor is unusable and the
/// holder should re-anchor.
pub fn try_resolve(
  sequence: Sequence(a),
  anchor: Anchor,
) -> Result(Int, AnchorError) {
  let elements = visible_elements(sequence)

  case anchor {
    Start -> Ok(0)
    End -> Ok(visible_length_elements(elements))
    AtItem(id, bias) ->
      case resolve_element_anchor(elements, id, bias, 0) {
        Ok(index) -> Ok(index)
        Error(Nil) ->
          case dict.get(sequence.forwardings, id) {
            Ok(Forwarding(left, _right)) ->
              resolve_forwarded_gap(elements, left)
            Error(Nil) -> Error(UnknownAnchorTarget)
          }
      }
  }
}

fn resolve_element_anchor(
  elements: List(Element(a)),
  id: ItemId,
  bias: Bias,
  visible_before: Int,
) -> Result(Int, Nil) {
  case elements {
    [] -> Error(Nil)
    [el, ..rest] ->
      case element_id(el) == id {
        True ->
          case bias, element_is_visible(el) {
            After, True -> Ok(visible_before + 1)
            _, _ -> Ok(visible_before)
          }
        False ->
          case element_is_visible(el) {
            True -> resolve_element_anchor(rest, id, bias, visible_before + 1)
            False -> resolve_element_anchor(rest, id, bias, visible_before)
          }
      }
  }
}

fn resolve_forwarded_gap(
  elements: List(Element(a)),
  left: Option(ItemId),
) -> Result(Int, AnchorError) {
  case left {
    None -> Ok(0)
    Some(left_id) ->
      case resolve_element_anchor(elements, left_id, After, 0) {
        Ok(index) -> Ok(index)
        Error(Nil) -> Error(UnknownAnchorTarget)
      }
  }
}

/// Encode an anchor as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `anchor`, so
/// anchors can travel between replicas (e.g. shared cursors).
pub fn anchor_to_json(anchor: Anchor) -> json.Json {
  let encoded = case anchor {
    Start -> json.object([#("kind", json.string("start"))])
    End -> json.object([#("kind", json.string("end"))])
    AtItem(id, bias) ->
      json.object([
        #("kind", json.string("item")),
        #("id", encode_item_id(id)),
        #("bias", encode_bias(bias)),
      ])
  }

  json.object([
    #("type", json.string("anchor")),
    #("v", json.int(1)),
    #("anchor", encoded),
  ])
}

/// Decode an anchor from a JSON string produced by `anchor_to_json`.
pub fn anchor_from_json(
  json_string: String,
) -> Result(Anchor, json.DecodeError) {
  let anchor_decoder = {
    use kind <- decode.field("kind", decode.string)
    case kind {
      "start" -> decode.success(Start)
      "end" -> decode.success(End)
      "item" -> {
        use id <- decode.field("id", item_id_decoder())
        use bias <- decode.field("bias", bias_decoder())
        decode.success(AtItem(id: id, bias: bias))
      }
      _ -> decode.failure(Start, "one of start, end, item")
    }
  }
  let envelope_decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(type_tag, version))
  }

  case json.parse(from: json_string, using: envelope_decoder) {
    Error(e) -> Error(e)
    Ok(#(type_tag, version)) ->
      case type_tag == "anchor" && version == 1 {
        True ->
          json.parse(from: json_string, using: {
            use anchor <- decode.field("anchor", anchor_decoder)
            decode.success(anchor)
          })
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=anchor and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

fn encode_bias(bias: Bias) -> json.Json {
  case bias {
    Before -> json.string("before")
    After -> json.string("after")
  }
}

fn bias_decoder() -> decode.Decoder(Bias) {
  decode.string
  |> decode.then(fn(value) {
    case value {
      "before" -> decode.success(Before)
      "after" -> decode.success(After)
      _ -> decode.failure(Before, "before or after")
    }
  })
}

/// Return all visible values in sequence order.
pub fn values(sequence: Sequence(a)) -> List(a) {
  visible_elements(sequence)
  |> list.filter_map(fn(el) {
    case el {
      Stable(_, value) -> Ok(value)
      LiveEl(item) ->
        case item.deleted {
          None -> Ok(item.value)
          Some(_) -> Error(Nil)
        }
    }
  })
}

/// Return the count of visible values.
pub fn length(sequence: Sequence(a)) -> Int {
  sequence.segments
  |> list.fold(0, fn(count, segment) {
    case segment {
      Block(_, values) -> count + list.length(values)
      Live(item) ->
        case item.deleted {
          None -> count + 1
          Some(_) -> count
        }
    }
  })
}

/// The stability frontier this sequence was last compacted at.
///
/// Empty until the first `compact` call. Carried in the state so merging can
/// tell which side is compacted further.
pub fn frontier(sequence: Sequence(a)) -> VersionVector {
  sequence.frontier
}

/// The number of entries in a forwarding map.
pub fn forwarding_size(map: ForwardingMap) -> Int {
  let ForwardingMap(entries) = map
  dict.size(entries)
}

/// Remove previously emitted forwarding entries from the sequence.
///
/// Forwardings are bounded by the host's retention policy: keep the map
/// returned by each `compact` round and expire old rounds by passing them
/// here. Anchors and deltas referencing removed entries hard-fail
/// (`UnknownAnchorTarget` / `UnknownOriginTarget`) and must re-anchor or
/// resync.
pub fn remove_forwardings(
  sequence: Sequence(a),
  map: ForwardingMap,
) -> Sequence(a) {
  let ForwardingMap(entries) = map
  let remaining =
    dict.fold(entries, sequence.forwardings, fn(acc, id, _forwarding) {
      dict.delete(acc, id)
    })
  Sequence(..sequence, forwardings: remaining)
}

/// Merge two sequence CRDT states.
///
/// Items are joined by their stable IDs. Concurrent deletes are preserved by
/// keeping the winning delete op, and the merged item set is deterministically
/// reordered using each item's left and right origins. Stable blocks form a
/// fixed skeleton that live items are ordered around.
///
/// States compacted at different frontiers merge as long as one frontier
/// dominates the other (with a global sequencer, floors are totally ordered
/// so this always holds). An item absent from the further-compacted side and
/// covered by its frontier is treated as compacted away and stays dropped.
pub fn merge(a: Sequence(a), b: Sequence(a)) -> Sequence(a) {
  let forwardings =
    merge_forwarding_entries(a.forwardings, b.forwardings)
    |> normalize_forwardings()
  let frontier = version_vector.merge(a.frontier, b.frontier)

  let a_elements = segments_to_elements(a.segments)
  let b_elements = segments_to_elements(b.segments)
  let a_ids = element_id_dict(a_elements)
  let b_ids = element_id_dict(b_elements)
  let b_lives = live_item_dict(b_elements)
  let b_stables = stable_id_dict(b_elements)

  let dropped = fn(id: ItemId) -> Bool {
    dict.has_key(forwardings, id)
    || { !dict.has_key(a_ids, id) && frontier_covers(a.frontier, id) }
    || { !dict.has_key(b_ids, id) && frontier_covers(b.frontier, id) }
  }

  // Elements at or below the merged frontier are pinned by the rebuild, so
  // their order must come from ONE side, identically for both merge
  // directions: the side whose frontier dominates (it holds the settled
  // below-frontier order; with equal frontiers both sides' covered orders
  // already converged). Everything above the frontier joins a volatile pool
  // and is re-integrated from origins, so its list position is irrelevant.
  let covered_source = case version_vector.compare(a.frontier, b.frontier) {
    version_vector.Before -> b_elements
    version_vector.Concurrent ->
      case frontier_tiebreak(a.frontier, b.frontier) {
        order.Gt -> b_elements
        order.Lt | order.Eq -> a_elements
      }
    version_vector.After | version_vector.Equal -> a_elements
  }
  let #(other_lives, other_stables) = case covered_source == a_elements {
    True -> #(b_lives, b_stables)
    False -> #(live_item_dict(a_elements), stable_id_dict(a_elements))
  }
  let covered_elements =
    covered_source
    |> list.filter(fn(el) {
      is_stable_element(el) || frontier_covers(frontier, element_id(el))
    })
    |> list.filter(fn(el) { !dropped(element_id(el)) })
    |> list.map(reconcile_element(_, other_lives, other_stables, frontier))

  let volatile_pool =
    list.append(live_items_of(a_elements), live_items_of(b_elements))
    |> list.filter(fn(item) {
      !frontier_covers(frontier, item.id) && !dropped(item.id)
    })
    |> list.fold(dict.new(), fn(pool, item) {
      case dict.get(pool, item.id) {
        Ok(existing) -> dict.insert(pool, item.id, merge_item(existing, item))
        Error(Nil) -> dict.insert(pool, item.id, item)
      }
    })
    |> dict.values()
    |> list.map(LiveEl)

  let elements =
    rebuild(list.append(covered_elements, volatile_pool), forwardings, frontier)

  Sequence(
    replica_id: a.replica_id,
    counter: int.max(a.counter, b.counter),
    segments: elements_to_segments(elements),
    forwardings: forwardings,
    frontier: frontier,
  )
}

fn reconcile_element(
  el: Element(a),
  b_lives: Dict(ItemId, Item(a)),
  b_stables: Dict(ItemId, Nil),
  frontier: VersionVector,
) -> Element(a) {
  case el {
    LiveEl(item) ->
      case dict.get(b_lives, item.id) {
        Ok(other) -> LiveEl(merge_item(item, other))
        Error(Nil) ->
          case dict.has_key(b_stables, item.id) {
            True -> stable_or_live(item, frontier)
            False -> el
          }
      }
    Stable(id, _value) ->
      case dict.get(b_lives, id) {
        Ok(other) -> stable_or_live(other, frontier)
        Error(Nil) -> el
      }
  }
}

/// One side has the element compacted into a block, the other still holds a
/// live item for it. A tombstone or a move keeps the item live and supersedes
/// the block slot; only a plain copy collapses to the stable representation.
/// The rule looks only at the live item, so both merge directions agree.
///
/// A moved item is never collapsed into the block skeleton, even if the merged
/// frontier covers its move op: `compact` refuses to stabilize any state that
/// holds a move (see `compact`), so a covered-move block slot cannot legitimately
/// arise, and baking one here would strip the origins a peer's concurrent
/// above-frontier inserts integrate against and break merge commutativity.
fn stable_or_live(item: Item(a), _frontier: VersionVector) -> Element(a) {
  case item.deleted, item.move {
    None, None -> Stable(id: item.id, value: item.value)
    _, _ -> LiveEl(item)
  }
}

/// Deterministically rebuild the element order.
///
/// Everything at or below the frontier — stable elements and old live items
/// alike — is pinned at its stored position: those positions converged on
/// every replica before the frontier passed them, so the pinned skeleton is
/// identical everywhere. Items above the frontier are integrated YATA-style
/// one at a time in Lamport order (a canonical total order), which makes
/// the result a pure function of the element set; finally moves are applied
/// last-writer-wins. Every construction path (local edits and both merge
/// directions) goes through this, so convergence holds by construction.
///
/// Because ops record canonical-adjacent origins, a volatile item's
/// conflict window can only ever contain other volatile items — never a
/// pinned element — so integration never needs the origins compaction
/// stripped.
fn rebuild(
  elements: List(Element(a)),
  forwardings: Dict(ItemId, Forwarding),
  frontier: VersionVector,
) -> List(Element(a)) {
  rebuild_base(elements, forwardings, frontier)
}

/// The user-facing element order: the stored base with every move overlaid.
///
/// Moves are an overlay, not part of the stored order, so every read that
/// depends on position — values, index lookups, anchors — goes through here.
/// Writes go the other way: they compute origins from this view and then
/// update the base.
fn visible_elements(sequence: Sequence(a)) -> List(Element(a)) {
  apply_moves(segments_to_elements(sequence.segments), sequence.forwardings)
}

/// The canonical pre-move order: pinned covered elements in list order with
/// everything else integrated in Lamport order.
///
/// A covered element that carries a still-volatile move record is NOT
/// pinned: its stored position reflects whichever moves this replica has
/// already applied, which differs between replicas. It always carries its
/// origins, so it re-integrates at its settled base position instead (its
/// Lamport position sorts it before every volatile item automatically); the
/// move overlay then re-places it.
fn rebuild_base(
  elements: List(Element(a)),
  forwardings: Dict(ItemId, Forwarding),
  frontier: VersionVector,
) -> List(Element(a)) {
  let pinned =
    list.filter(elements, fn(el) {
      case el {
        Stable(_, _) -> True
        LiveEl(item) -> frontier_covers(frontier, item.id)
      }
    })
  elements
  |> live_items_of()
  |> list.filter(fn(item) { !frontier_covers(frontier, item.id) })
  |> list.sort(compare_lamport)
  |> list.fold(pinned, fn(current, item) {
    integrate_element(current, item, forwardings)
  })
}

/// A deterministic, direction-independent order on version vectors, used
/// only to pick a covered-order source when merging states compacted at
/// concurrent frontiers (which a sequencer host never produces).
fn frontier_tiebreak(a: VersionVector, b: VersionVector) -> order.Order {
  compare_clock_lists(canonical_clocks(a), canonical_clocks(b))
}

fn canonical_clocks(vector: VersionVector) -> List(#(ReplicaId, Int)) {
  version_vector.to_dict(vector)
  |> dict.to_list()
  |> list.sort(fn(x, y) { replica_id.compare(x.0, y.0) })
}

fn compare_clock_lists(
  a: List(#(ReplicaId, Int)),
  b: List(#(ReplicaId, Int)),
) -> order.Order {
  case a, b {
    [], [] -> order.Eq
    [], _ -> order.Lt
    _, [] -> order.Gt
    [#(ra, ca), ..ta], [#(rb, cb), ..tb] ->
      case replica_id.compare(ra, rb) {
        order.Eq ->
          case int.compare(ca, cb) {
            order.Eq -> compare_clock_lists(ta, tb)
            other -> other
          }
        other -> other
      }
  }
}

/// Where a move's target gap resolves in the current element order.
type MoveTarget {
  /// Directly before this element; successive moves to the same target
  /// stack left-to-right in op order naturally.
  BeforeElement(ItemId)
  /// The gap after this element (`None` = document start). Successive moves
  /// into the same gap must also stack left-to-right in op order, which
  /// `apply_moves` tracks per gap.
  AfterGap(Option(ItemId))
  /// The gap collapsed past everything (target compacted away with nothing
  /// retained around it).
  AtEnd
}

/// Re-place every moved item from a canonical base: strip all moved items
/// first, then apply the moves in op order. Both merge directions therefore
/// start from the same non-moved skeleton and converge, regardless of which
/// side had already applied which move. Moves landing in the same gap stack
/// left-to-right in op order, matching how they stack when the gap's right
/// boundary still exists.
fn apply_moves(
  elements: List(Element(a)),
  forwardings: Dict(ItemId, Forwarding),
) -> List(Element(a)) {
  let movers =
    elements
    |> live_items_of()
    |> list.filter(has_move)
    |> list.sort(compare_item_moves)
  let stripped =
    list.fold(movers, elements, fn(current, item) {
      remove_element_by_id(current, item.id)
    })
  let mover_ids =
    list.fold(movers, dict.new(), fn(acc, item) {
      dict.insert(acc, item.id, Nil)
    })
  let #(result, _) =
    list.fold(movers, #(stripped, dict.new()), fn(acc, item) {
      let #(current, last_in_gap) = acc
      case item.move {
        None -> acc
        Some(Move(_, move_left, move_right)) ->
          case
            resolve_move_target(
              current,
              move_left,
              move_right,
              forwardings,
              mover_ids,
            )
          {
            BeforeElement(right_id) -> #(
              insert_element_before_id(current, right_id, LiveEl(item)),
              last_in_gap,
            )
            AtEnd -> #(list.append(current, [LiveEl(item)]), last_in_gap)
            AfterGap(anchor) -> #(
              splice_into_gap(
                current,
                dict.get(last_in_gap, anchor),
                anchor,
                LiveEl(item),
              ),
              dict.insert(last_in_gap, anchor, item.id),
            )
          }
      }
    })
  result
}

fn splice_into_gap(
  elements: List(Element(a)),
  previous_in_gap: Result(ItemId, Nil),
  anchor: Option(ItemId),
  el: Element(a),
) -> List(Element(a)) {
  case previous_in_gap, anchor {
    Ok(previous), _ -> insert_element_after_id(elements, previous, el)
    Error(Nil), None -> [el, ..elements]
    Error(Nil), Some(left_id) -> insert_element_after_id(elements, left_id, el)
  }
}

fn resolve_move_target(
  elements: List(Element(a)),
  move_left: Option(ItemId),
  move_right: Option(ItemId),
  forwardings: Dict(ItemId, Forwarding),
  mover_ids: Dict(ItemId, Nil),
) -> MoveTarget {
  let fuel = dict.size(forwardings) + 1
  let left_gap = case chase_left(move_left, forwardings, fuel) {
    None -> AfterGap(None)
    Some(left_id) ->
      case contains_element_id(elements, left_id) {
        True -> AfterGap(Some(left_id))
        False -> AtEnd
      }
  }
  case move_right {
    None -> left_gap
    Some(raw_right) ->
      case contains_element_id(elements, raw_right) {
        True -> BeforeElement(raw_right)
        // Absent because a compaction pass reclaimed it, or because it is a
        // mover this pass has not spliced back in yet. Only the first has a
        // gap to re-aim at; the second falls back to the move's own left
        // origin.
        False ->
          case dict.has_key(forwardings, raw_right) {
            False -> left_gap
            True ->
              reclaimed_boundary_target(
                elements,
                move_right,
                forwardings,
                mover_ids,
                fuel,
              )
          }
      }
  }
}

/// Where a move lands when its right boundary was reclaimed by a pass.
///
/// Prefer the nearest retained element to the boundary's right, so the move
/// still splices before the same neighbour. A forwarded boundary that is
/// itself being moved in this pass is not a faithful gap edge — a replica
/// that still held the reclaimed target would not anchor on it — so that
/// falls through to the gap's left edge instead.
fn reclaimed_boundary_target(
  elements: List(Element(a)),
  move_right: Option(ItemId),
  forwardings: Dict(ItemId, Forwarding),
  mover_ids: Dict(ItemId, Nil),
  fuel: Int,
) -> MoveTarget {
  case chase_right(move_right, forwardings, fuel) {
    None -> reclaimed_boundary_gap(elements, move_right, forwardings, fuel)
    Some(right_id) ->
      case
        !dict.has_key(mover_ids, right_id)
        && contains_element_id(elements, right_id)
      {
        True -> BeforeElement(right_id)
        False -> reclaimed_boundary_gap(elements, move_right, forwardings, fuel)
      }
  }
}

/// The gap a reclaimed right boundary left behind, named by its left edge.
///
/// The move targeted the gap immediately before that boundary, so once the
/// boundary is gone the same gap is "after whatever was retained to its
/// left". Falling back to the move's own left origin instead would aim at the
/// far edge of the original gap and skip past everything inserted into it
/// since the move was made — which is how a compacted replica and an
/// uncompacted one end up ordering the mover differently.
fn reclaimed_boundary_gap(
  elements: List(Element(a)),
  move_right: Option(ItemId),
  forwardings: Dict(ItemId, Forwarding),
  fuel: Int,
) -> MoveTarget {
  case chase_left(move_right, forwardings, fuel) {
    None -> AfterGap(None)
    Some(left_id) ->
      case contains_element_id(elements, left_id) {
        True -> AfterGap(Some(left_id))
        False -> AtEnd
      }
  }
}

fn compare_lamport(x: Item(a), y: Item(a)) -> order.Order {
  let ItemId(x_rid, x_counter) = x.id
  let ItemId(y_rid, y_counter) = y.id
  case int.compare(x_counter, y_counter) {
    order.Eq -> replica_id.compare(x_rid, y_rid)
    other -> other
  }
}

/// Compact everything at or below a stability frontier.
///
/// `stable` must describe a causal cut the host knows no in-flight or future
/// op can reference (e.g. the version vector accumulated by replaying ops up
/// to a global sequencer's acknowledgement floor). For the stable region the
/// pass drops tombstones, merges runs of adjacent same-replica items with
/// sequential counters into blocks, and strips origins and move slots.
///
/// Returns the compacted sequence and the forwarding entries emitted by this
/// pass (one per dropped ID). The cumulative forwarding map is also carried
/// in the sequence; hosts bound its growth with `remove_forwardings`.
///
/// Compacting at the current frontier, at an older one, or at one concurrent
/// with it is a no-op — frontiers only advance.
///
/// A state holding ANY move record is left unchanged, even when the move op is
/// already covered by `stable`. This guard is load-bearing for convergence, not
/// just conservatism: baking a settled move into the compact skeleton fixes its
/// position from only the compacting replica's items, but a peer's still-live
/// concurrent inserts above the frontier integrate against the moved item's
/// origins — which stabilization strips. The two then order those inserts
/// differently and `merge` stops commuting (see the property test
/// `merge_commutes_with_compaction_for_deltas_above_frontier`). Because move
/// records are never cleared locally, a replica that uses `move` cannot compact
/// until it merges a peer that has already stabilized the item into a block; a
/// safe stabilization path for moves is future work (see issue #98).
pub fn compact(
  sequence: Sequence(a),
  stable: VersionVector,
) -> #(Sequence(a), ForwardingMap) {
  case version_vector.compare(stable, sequence.frontier) {
    version_vector.After -> do_compact(sequence, stable)
    version_vector.Before | version_vector.Concurrent | version_vector.Equal -> #(
      sequence,
      ForwardingMap(dict.new()),
    )
  }
}

type Classified(a) {
  Retained(Element(a))
  Dropped(id: ItemId)
}

fn do_compact(
  sequence: Sequence(a),
  stable: VersionVector,
) -> #(Sequence(a), ForwardingMap) {
  let elements = segments_to_elements(sequence.segments)
  let anchored = move_anchor_ids(elements)
  let classified =
    list.map(elements, fn(el) {
      case el {
        Stable(_, _) -> Retained(el)
        LiveEl(item) ->
          case dict.has_key(anchored, item.id) {
            True -> Retained(el)
            False ->
              case item_stability(item, stable) {
                DropTombstone -> Dropped(item.id)
                ToStable -> Retained(Stable(id: item.id, value: item.value))
                KeepLive -> Retained(el)
              }
          }
      }
    })

  let new_entries = forwarding_entries_for_pass(classified, stable)
  // Dropping and stabilizing happen strictly in place, so the visible order
  // is preserved by construction. Retained items keep their origins as-is;
  // stored order is authoritative and never re-derived from them.
  let kept =
    list.filter_map(classified, fn(entry) {
      case entry {
        Retained(el) -> Ok(el)
        Dropped(_) -> Error(Nil)
      }
    })

  let updated_old =
    dict.map_values(sequence.forwardings, fn(_id, forwarding) {
      let Forwarding(left, right) = forwarding
      Forwarding(
        left: chase_left(left, new_entries, dict.size(new_entries) + 1),
        right: chase_right(right, new_entries, dict.size(new_entries) + 1),
      )
    })
  let all_forwardings =
    dict.fold(new_entries, updated_old, fn(acc, id, forwarding) {
      dict.insert(acc, id, forwarding)
    })

  let compacted =
    Sequence(
      ..sequence,
      segments: elements_to_segments(kept),
      forwardings: all_forwardings,
      frontier: stable,
    )

  #(compacted, ForwardingMap(new_entries))
}

/// Every ID a live move still names as one of its target-gap boundaries.
///
/// Reclaiming one of these would leave the move anchoring on a gap that has
/// to be reconstructed from forwardings, and the reconstruction is not
/// position-identical: a compacted replica and an uncompacted one would
/// splice the mover differently. Retaining them keeps move resolution exactly
/// what it was before the pass, at a cost of at most two extra tombstones per
/// live mover.
fn move_anchor_ids(elements: List(Element(a))) -> Dict(ItemId, Nil) {
  elements
  |> live_items_of()
  |> list.fold(dict.new(), fn(acc, item) {
    case item.move {
      None -> acc
      Some(Move(_, move_left, move_right)) ->
        acc
        |> insert_optional_id(move_left)
        |> insert_optional_id(move_right)
    }
  })
}

fn insert_optional_id(
  acc: Dict(ItemId, Nil),
  id: Option(ItemId),
) -> Dict(ItemId, Nil) {
  case id {
    None -> acc
    Some(id) -> dict.insert(acc, id, Nil)
  }
}

type Stability {
  DropTombstone
  ToStable
  KeepLive
}

fn item_stability(item: Item(a), stable: VersionVector) -> Stability {
  use <- bool.guard(!frontier_covers(stable, item.id), KeepLive)
  case item.deleted {
    Some(op) ->
      case frontier_covers_op(stable, op) {
        True -> DropTombstone
        False -> KeepLive
      }
    None ->
      case item.move {
        None -> ToStable
        // A mover keeps its record and the origins naming its target gap:
        // the overlay is re-applied on every read, so both stay live data.
        Some(_) -> KeepLive
      }
  }
}

/// Forwardings for one pass, naming only settled landmarks.
///
/// A forwarding must resolve identically on every replica, and volatile
/// membership does not: replicas compacting at the same frontier hold
/// different above-frontier items, so a forwarding naming one would point
/// somewhere the other cannot follow.
///
/// Move anchors make this load-bearing: they splice at an exact position
/// rather than searching a window, so the identity of the target decides the
/// result outright.
fn forwarding_entries_for_pass(
  classified: List(Classified(a)),
  stable: VersionVector,
) -> Dict(ItemId, Forwarding) {
  let settled = fn(el: Element(a)) { frontier_covers(stable, element_id(el)) }
  let lefts = left_targets(classified, None, dict.new(), settled)
  let #(rights, _) =
    list.fold_right(classified, #(dict.new(), None), fn(acc, entry) {
      let #(targets, next_retained) = acc
      case entry {
        Retained(el) ->
          case settled(el) {
            True -> #(targets, Some(element_id(el)))
            False -> #(targets, next_retained)
          }
        Dropped(id) -> #(dict.insert(targets, id, next_retained), next_retained)
      }
    })

  dict.fold(lefts, dict.new(), fn(acc, id, left) {
    let right = case dict.get(rights, id) {
      Ok(target) -> target
      Error(Nil) -> None
    }
    dict.insert(acc, id, Forwarding(left: left, right: right))
  })
}

fn left_targets(
  classified: List(Classified(a)),
  last_retained: Option(ItemId),
  acc: Dict(ItemId, Option(ItemId)),
  settled: fn(Element(a)) -> Bool,
) -> Dict(ItemId, Option(ItemId)) {
  case classified {
    [] -> acc
    [Retained(el), ..rest] ->
      case settled(el) {
        True -> left_targets(rest, Some(element_id(el)), acc, settled)
        False -> left_targets(rest, last_retained, acc, settled)
      }
    [Dropped(id), ..rest] ->
      left_targets(
        rest,
        last_retained,
        dict.insert(acc, id, last_retained),
        settled,
      )
  }
}

/// Translate a delta's origins onto a compacted state.
///
/// Rebase support for evicted clients: origins (including move origins)
/// referencing compacted IDs are rewritten through `onto`'s forwarding map to
/// the gap the ID left behind. Items whose own ID was compacted away are
/// dropped from the delta — the op is already settled. Returns
/// `Error(UnknownOriginTarget)` when an origin is neither present, part of
/// the delta itself, nor forwarded (the forwarding expired); the host must
/// degrade the op to a positional edit or discard it.
pub fn translate_origins(
  delta: Sequence(a),
  onto: Sequence(a),
) -> Result(Sequence(a), TranslateError) {
  let onto_ids = element_id_dict(segments_to_elements(onto.segments))
  let delta_elements = segments_to_elements(delta.segments)
  let delta_ids = element_id_dict(delta_elements)
  let known = fn(id: ItemId) {
    dict.has_key(onto_ids, id) || dict.has_key(delta_ids, id)
  }
  let dropped = fn(id: ItemId) {
    dict.has_key(onto.forwardings, id)
    || { !dict.has_key(onto_ids, id) && frontier_covers(onto.frontier, id) }
  }

  let translate = fn(
    origin: Option(ItemId),
    pick: fn(Forwarding) -> Option(ItemId),
  ) -> Result(Option(ItemId), TranslateError) {
    case origin {
      None -> Ok(None)
      Some(id) ->
        case known(id) {
          True -> Ok(origin)
          False ->
            case dict.get(onto.forwardings, id) {
              Ok(forwarding) -> Ok(pick(forwarding))
              Error(Nil) -> Error(UnknownOriginTarget)
            }
        }
    }
  }

  let translated =
    delta_elements
    |> list.filter(fn(el) { !dropped(element_id(el)) })
    |> list.try_map(translate_element(_, translate))

  case translated {
    Ok(elements) ->
      Ok(Sequence(..delta, segments: elements_to_segments(elements)))
    Error(error) -> Error(error)
  }
}

fn translate_element(
  el: Element(a),
  translate: fn(Option(ItemId), fn(Forwarding) -> Option(ItemId)) ->
    Result(Option(ItemId), TranslateError),
) -> Result(Element(a), TranslateError) {
  case el {
    Stable(_, _) -> Ok(el)
    LiveEl(item) -> {
      use origin_left <- result.try(translate(item.origin_left, left_of))
      use origin_right <- result.try(translate(item.origin_right, right_of))
      use move <- result.try(translate_move(item.move, translate))
      Ok(LiveEl(
        Item(
          ..item,
          origin_left: origin_left,
          origin_right: origin_right,
          move: move,
        ),
      ))
    }
  }
}

fn translate_move(
  move: Option(Move),
  translate: fn(Option(ItemId), fn(Forwarding) -> Option(ItemId)) ->
    Result(Option(ItemId), TranslateError),
) -> Result(Option(Move), TranslateError) {
  case move {
    None -> Ok(None)
    Some(Move(op, move_left, move_right)) -> {
      use move_left <- result.try(translate(move_left, left_of))
      use move_right <- result.try(translate(move_right, right_of))
      Ok(
        Some(Move(op_id: op, origin_left: move_left, origin_right: move_right)),
      )
    }
  }
}

fn left_of(forwarding: Forwarding) -> Option(ItemId) {
  forwarding.left
}

fn right_of(forwarding: Forwarding) -> Option(ItemId) {
  forwarding.right
}

/// Encode a sequence CRDT as a self-describing JSON value.
///
/// Produces an envelope with `type`, `v` (schema version), and `state`. The
/// state includes this replica ID, local counter, applied compaction
/// frontier, forwarding entries, and every segment: compact blocks of stable
/// values and full items including tombstones.
pub fn to_json(
  sequence: Sequence(a),
  encode_value: fn(a) -> json.Json,
) -> json.Json {
  json.object([
    #("type", json.string("sequence")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("self_id", replica_id.to_json(sequence.replica_id)),
        #("counter", json.int(sequence.counter)),
        #("frontier", version_vector.to_json(sequence.frontier)),
        #(
          "forwardings",
          json.array(dict.to_list(sequence.forwardings), encode_forwarding),
        ),
        #(
          "segments",
          json.array(sequence.segments, encode_segment(_, encode_value)),
        ),
      ]),
    ),
  ])
}

/// Decode a sequence CRDT from a JSON string produced by `to_json`.
///
/// Returns `Ok(Sequence)` on success, or `Error(json.DecodeError)` if the
/// input is not a valid sequence JSON envelope. Live items are reordered
/// deterministically from their stable origins before the `Sequence` is
/// returned.
pub fn from_json(
  json_string: String,
  value_decoder: decode.Decoder(a),
) -> Result(Sequence(a), json.DecodeError) {
  let state_decoder = fn(version: Int) {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", replica_id.decoder())
      use counter <- decode.field("counter", non_negative_int_decoder())
      use frontier <- decode.field("frontier", version_vector.decoder())
      use forwardings <- decode.field(
        "forwardings",
        decode.list(forwarding_decoder()),
      )
      use segments <- decode.field(
        "segments",
        decode.list(segment_decoder(value_decoder)),
      )
      let forwarding_map = dict.from_list(forwardings)
      case base_order_segments(version, segments, forwarding_map) {
        Ok(base) ->
          decode.success(Sequence(
            replica_id: self_id,
            counter: counter,
            segments: base,
            forwardings: forwarding_map,
            frontier: frontier,
          ))
        Error(Nil) ->
          decode.failure(
            Sequence(
              replica_id: self_id,
              counter: counter,
              segments: [],
              forwardings: forwarding_map,
              frontier: frontier,
            ),
            "a v1 payload whose moved items were not already compacted",
          )
      }
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
      case type_tag == "sequence" && { version == 1 || version == 2 } {
        True -> json.parse(from: json_string, using: state_decoder(version))
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=sequence and v=1 or v=2",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

/// Bring a decoded payload's segments into canonical base order.
///
/// Version 2 stores the pre-move base and overlays moves on read, so its
/// segments are already the base. Version 1 stored the move-APPLIED order, so
/// a mover sits at its post-move slot and would be pinned there.
///
/// A v1 payload with no move records never had an overlay, so its order is
/// already the base. One with movers but no compacted segments still carries
/// every origin, so the base re-derives exactly. One with both is
/// unrecoverable — the compacted elements have no origins to re-integrate
/// from, and replicas at different frontiers would reconstruct the mover's
/// slot differently — so it is rejected and the holder must resync.
fn base_order_segments(
  version: Int,
  segments: List(Segment(a)),
  forwardings: Dict(ItemId, Forwarding),
) -> Result(List(Segment(a)), Nil) {
  let elements = segments_to_elements(segments)
  case version >= 2 || !list.any(live_items_of(elements), has_move) {
    True -> Ok(elements_to_segments(elements))
    False ->
      case list.any(elements, is_stable_element) {
        True -> Error(Nil)
        False ->
          Ok(
            elements_to_segments(rebuild_base(
              elements,
              forwardings,
              version_vector.new(),
            )),
          )
      }
  }
}

fn encode_segment(
  segment: Segment(a),
  encode_value: fn(a) -> json.Json,
) -> json.Json {
  case segment {
    Block(first_id, values) ->
      json.object([
        #("kind", json.string("block")),
        #("first_id", encode_item_id(first_id)),
        #("values", json.array(values, encode_value)),
      ])
    Live(item) ->
      json.object([
        #("kind", json.string("item")),
        #("id", encode_item_id(item.id)),
        #("origin_left", encode_optional_item_id(item.origin_left)),
        #("origin_right", encode_optional_item_id(item.origin_right)),
        #("value", encode_value(item.value)),
        #("deleted", encode_optional_op_id(item.deleted)),
        #("move", encode_optional_move(item.move)),
      ])
  }
}

fn segment_decoder(
  value_decoder: decode.Decoder(a),
) -> decode.Decoder(Segment(a)) {
  use kind <- decode.field("kind", decode.string)
  case kind {
    "block" -> {
      use first_id <- decode.field("first_id", item_id_decoder())
      use values <- decode.field("values", decode.list(value_decoder))
      decode.success(Block(first_id: first_id, values: values))
    }
    "item" -> {
      use id <- decode.field("id", item_id_decoder())
      use origin_left <- decode.field(
        "origin_left",
        decode.optional(item_id_decoder()),
      )
      use origin_right <- decode.field(
        "origin_right",
        decode.optional(item_id_decoder()),
      )
      use value <- decode.field("value", value_decoder)
      use deleted <- decode.field("deleted", decode.optional(op_id_decoder()))
      use move <- decode.optional_field(
        "move",
        None,
        decode.optional(move_decoder()),
      )
      decode.success(
        Live(Item(
          id: id,
          origin_left: origin_left,
          origin_right: origin_right,
          value: value,
          deleted: deleted,
          move: move,
        )),
      )
    }
    _ ->
      decode.failure(
        Block(first_id: ItemId(replica_id.new(""), 0), values: []),
        "segment kind of block or item",
      )
  }
}

fn encode_forwarding(entry: #(ItemId, Forwarding)) -> json.Json {
  let #(id, Forwarding(left, right)) = entry
  json.object([
    #("id", encode_item_id(id)),
    #("left", encode_optional_item_id(left)),
    #("right", encode_optional_item_id(right)),
  ])
}

fn forwarding_decoder() -> decode.Decoder(#(ItemId, Forwarding)) {
  use id <- decode.field("id", item_id_decoder())
  use left <- decode.field("left", decode.optional(item_id_decoder()))
  use right <- decode.field("right", decode.optional(item_id_decoder()))
  decode.success(#(id, Forwarding(left: left, right: right)))
}

fn move_decoder() -> decode.Decoder(Move) {
  use op_id <- decode.field("op_id", op_id_decoder())
  use origin_left <- decode.field(
    "origin_left",
    decode.optional(item_id_decoder()),
  )
  use origin_right <- decode.field(
    "origin_right",
    decode.optional(item_id_decoder()),
  )
  decode.success(Move(
    op_id: op_id,
    origin_left: origin_left,
    origin_right: origin_right,
  ))
}

fn op_id_decoder() -> decode.Decoder(OpId) {
  use rid <- decode.field("replica_id", replica_id.decoder())
  use counter <- decode.field("counter", non_negative_int_decoder())
  decode.success(OpId(replica_id: rid, counter: counter))
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

fn item_id_decoder() -> decode.Decoder(ItemId) {
  use rid <- decode.field("replica_id", replica_id.decoder())
  use counter <- decode.field("counter", non_negative_int_decoder())
  decode.success(ItemId(replica_id: rid, counter: counter))
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

fn encode_optional_op_id(op_id: Option(OpId)) -> json.Json {
  case op_id {
    Some(op) -> encode_op_id(op)
    None -> json.null()
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

// ---------------------------------------------------------------------------
// Element and segment plumbing
// ---------------------------------------------------------------------------

/// An empty delta carrying no items — the neutral element for `merge`,
/// returned when an insert covers zero values.
fn empty_delta(replica_id: ReplicaId) -> Sequence(a) {
  Sequence(
    replica_id: replica_id,
    counter: 0,
    segments: [],
    forwardings: dict.new(),
    frontier: version_vector.new(),
  )
}

fn delta_sequence(
  replica_id: ReplicaId,
  counter: Int,
  item: Item(a),
) -> Sequence(a) {
  Sequence(
    replica_id: replica_id,
    counter: counter,
    segments: [Live(item)],
    forwardings: dict.new(),
    frontier: version_vector.new(),
  )
}

fn segments_to_elements(segments: List(Segment(a))) -> List(Element(a)) {
  list.flat_map(segments, fn(segment) {
    case segment {
      Live(item) -> [LiveEl(item)]
      Block(first_id, values) -> {
        let ItemId(rid, first_counter) = first_id
        list.index_map(values, fn(value, offset) {
          Stable(id: ItemId(rid, first_counter + offset), value: value)
        })
      }
    }
  })
}

fn elements_to_segments(elements: List(Element(a))) -> List(Segment(a)) {
  chunk_elements(elements, None, [])
  |> list.reverse()
}

fn chunk_elements(
  elements: List(Element(a)),
  run: Option(#(ItemId, List(a), ItemId)),
  acc: List(Segment(a)),
) -> List(Segment(a)) {
  case elements {
    [] -> flush_run(run, acc)
    [LiveEl(item), ..rest] ->
      chunk_elements(rest, None, [Live(item), ..flush_run(run, acc)])
    [Stable(id, value), ..rest] ->
      case run {
        Some(#(first, values_rev, last)) ->
          case follows(last, id) {
            True ->
              chunk_elements(
                rest,
                Some(#(first, [value, ..values_rev], id)),
                acc,
              )
            False ->
              chunk_elements(
                rest,
                Some(#(id, [value], id)),
                flush_run(run, acc),
              )
          }
        None -> chunk_elements(rest, Some(#(id, [value], id)), acc)
      }
  }
}

fn flush_run(
  run: Option(#(ItemId, List(a), ItemId)),
  acc: List(Segment(a)),
) -> List(Segment(a)) {
  case run {
    None -> acc
    Some(#(first, values_rev, _last)) -> [
      Block(first_id: first, values: list.reverse(values_rev)),
      ..acc
    ]
  }
}

fn follows(last: ItemId, next: ItemId) -> Bool {
  let ItemId(last_rid, last_counter) = last
  let ItemId(next_rid, next_counter) = next
  last_rid == next_rid && next_counter == last_counter + 1
}

fn element_id(el: Element(a)) -> ItemId {
  case el {
    Stable(id, _) -> id
    LiveEl(item) -> item.id
  }
}

fn element_is_visible(el: Element(a)) -> Bool {
  case el {
    Stable(_, _) -> True
    LiveEl(item) -> item.deleted == None
  }
}

fn is_stable_element(el: Element(a)) -> Bool {
  case el {
    Stable(_, _) -> True
    LiveEl(_) -> False
  }
}

fn visible_length_elements(elements: List(Element(a))) -> Int {
  elements
  |> list.fold(0, fn(count, el) {
    case element_is_visible(el) {
      True -> count + 1
      False -> count
    }
  })
}

fn visible_element_id_at(
  elements: List(Element(a)),
  index: Int,
) -> Option(ItemId) {
  case elements {
    [] -> None
    [el, ..rest] ->
      case element_is_visible(el) {
        True ->
          case index == 0 {
            True -> Some(element_id(el))
            False -> visible_element_id_at(rest, index - 1)
          }
        False -> visible_element_id_at(rest, index)
      }
  }
}

/// The element that follows `left` in the canonical order (`None` means the
/// head of the document, so the first canonical element).
fn canonical_successor(
  base: List(Element(a)),
  left: Option(ItemId),
) -> Option(ItemId) {
  case left {
    None -> next_element_id(base)
    Some(id) -> successor_of(base, id)
  }
}

fn successor_of(elements: List(Element(a)), id: ItemId) -> Option(ItemId) {
  case elements {
    [] -> None
    [el, ..rest] ->
      case element_id(el) == id {
        True -> next_element_id(rest)
        False -> successor_of(rest, id)
      }
  }
}

fn next_element_id(elements: List(Element(a))) -> Option(ItemId) {
  case elements {
    [] -> None
    [el, ..] -> Some(element_id(el))
  }
}

fn insert_element_before_id(
  elements: List(Element(a)),
  right: ItemId,
  el: Element(a),
) -> List(Element(a)) {
  case elements {
    [] -> [el]
    [first, ..rest] ->
      case element_id(first) == right {
        True -> [el, first, ..rest]
        False -> [first, ..insert_element_before_id(rest, right, el)]
      }
  }
}

fn insert_element_after_id(
  elements: List(Element(a)),
  left: ItemId,
  el: Element(a),
) -> List(Element(a)) {
  case elements {
    [] -> [el]
    [first, ..rest] ->
      case element_id(first) == left {
        True -> [first, el, ..rest]
        False -> [first, ..insert_element_after_id(rest, left, el)]
      }
  }
}

fn contains_element_id(elements: List(Element(a)), id: ItemId) -> Bool {
  list.any(elements, fn(el) { element_id(el) == id })
}

fn swap_in_item(elements: List(Element(a)), item: Item(a)) -> List(Element(a)) {
  case elements {
    [] -> [LiveEl(item)]
    [el, ..rest] ->
      case element_id(el) == item.id {
        True -> [LiveEl(item), ..rest]
        False -> [el, ..swap_in_item(rest, item)]
      }
  }
}

fn remove_element_by_id(
  elements: List(Element(a)),
  id: ItemId,
) -> List(Element(a)) {
  case elements {
    [] -> []
    [el, ..rest] ->
      case element_id(el) == id {
        True -> rest
        False -> [el, ..remove_element_by_id(rest, id)]
      }
  }
}

/// Walk to the visible element at `target`, replacing it with a tombstone.
/// A stable block member is extracted to a live item with origins
/// synthesized from its current neighbors so ordering keeps it in place.
/// Tombstone the element sitting at visible index `target`, updating the
/// CANONICAL base. A stable block member is extracted with its base
/// neighbours as origins, not the neighbours the move overlay gave it.
fn tombstone_in_base(
  elements: List(Element(a)),
  visible: List(Element(a)),
  target: Int,
  op: OpId,
) -> Option(#(List(Element(a)), Item(a))) {
  case visible_element_id_at(visible, target) {
    None -> None
    Some(id) -> tombstone_element_by_id(elements, id, None, op)
  }
}

fn tombstone_element_by_id(
  elements: List(Element(a)),
  id: ItemId,
  prev: Option(ItemId),
  op: OpId,
) -> Option(#(List(Element(a)), Item(a))) {
  case elements {
    [] -> None
    [el, ..rest] ->
      case element_id(el) == id {
        True -> {
          let item = tombstone_of(el, prev, next_element_id(rest), op)
          Some(#([LiveEl(item), ..rest], item))
        }
        False ->
          tombstone_element_by_id(rest, id, Some(element_id(el)), op)
          |> prepend_element_result(el)
      }
  }
}

/// The item at visible index `target`, read out of the CANONICAL base so a
/// stable block member gets its base neighbours as origins.
fn base_item_at_visible_index(
  elements: List(Element(a)),
  visible: List(Element(a)),
  target: Int,
) -> Option(Item(a)) {
  case visible_element_id_at(visible, target) {
    None -> None
    Some(id) -> element_as_item_by_id(elements, id, None)
  }
}

fn element_as_item_by_id(
  elements: List(Element(a)),
  id: ItemId,
  prev: Option(ItemId),
) -> Option(Item(a)) {
  case elements {
    [] -> None
    [el, ..rest] ->
      case element_id(el) == id {
        True ->
          case el {
            LiveEl(item) -> Some(item)
            Stable(stable_id, value) ->
              Some(Item(
                id: stable_id,
                origin_left: prev,
                origin_right: next_element_id(rest),
                value: value,
                deleted: None,
                move: None,
              ))
          }
        False -> element_as_item_by_id(rest, id, Some(element_id(el)))
      }
  }
}

fn tombstone_of(
  el: Element(a),
  prev: Option(ItemId),
  next: Option(ItemId),
  op: OpId,
) -> Item(a) {
  case el {
    LiveEl(item) -> Item(..item, deleted: Some(op))
    Stable(id, value) ->
      Item(
        id: id,
        origin_left: prev,
        origin_right: next,
        value: value,
        deleted: Some(op),
        move: None,
      )
  }
}

fn prepend_element_result(
  result: Option(#(List(Element(a)), Item(a))),
  el: Element(a),
) -> Option(#(List(Element(a)), Item(a))) {
  case result {
    Some(#(updated_rest, item)) -> Some(#([el, ..updated_rest], item))
    None -> None
  }
}

fn live_items_of(elements: List(Element(a))) -> List(Item(a)) {
  list.filter_map(elements, fn(el) {
    case el {
      LiveEl(item) -> Ok(item)
      Stable(_, _) -> Error(Nil)
    }
  })
}

fn live_item_dict(elements: List(Element(a))) -> Dict(ItemId, Item(a)) {
  elements
  |> live_items_of()
  |> list.fold(dict.new(), fn(acc, item) { dict.insert(acc, item.id, item) })
}

fn stable_elements_of(elements: List(Element(a))) -> List(Element(a)) {
  list.filter(elements, is_stable_element)
}

fn element_id_dict(elements: List(Element(a))) -> Dict(ItemId, Nil) {
  list.fold(elements, dict.new(), fn(acc, el) {
    dict.insert(acc, element_id(el), Nil)
  })
}

fn stable_id_dict(elements: List(Element(a))) -> Dict(ItemId, Nil) {
  elements
  |> stable_elements_of()
  |> element_id_dict()
}

// ---------------------------------------------------------------------------
// Ordering (YATA integration)
// ---------------------------------------------------------------------------
//
// The stored element order is authoritative. It is never rebuilt from
// origins: local edits splice in place, and merge integrates only elements
// this side has not seen, one at a time, using the YATA conflict-resolution
// scan. Origins of already-placed elements are inert position metadata.

/// Place a new item into the element order using its origins.
///
/// Follows the YATA/Yjs `integrate` algorithm: the item lands between its
/// left and right origins, and the scan over the conflict window decides its
/// position among concurrently inserted items. For causally valid ops the
/// window never contains a stable (origin-stripped) element — those were
/// visible when the op was created, so they cannot sit strictly between its
/// visible-adjacent origins; a stale op that does hit one degrades by
/// stopping the scan there.
fn integrate_element(
  elements: List(Element(a)),
  item: Item(a),
  forwardings: Dict(ItemId, Forwarding),
) -> List(Element(a)) {
  let fuel = dict.size(forwardings) + 1
  // Left origins are compared forwarding-chased, so a reference to a
  // compacted ID behaves exactly like a reference to the gap it collapsed
  // into and integration decides the same way whether or not the tombstone
  // has been dropped yet. Right origins are compared raw — chasing them
  // would conflate distinct identities (an op created before a neighbor's
  // delete versus one created after it) and flip tie-breaks depending on
  // how far the state is compacted; the chased form is used only to locate
  // the window boundary.
  let item_left = chase_left(item.origin_left, forwardings, fuel)
  let item_right = item.origin_right
  let left = resolve_origin(item_left, elements)
  let right =
    resolve_origin(chase_right(item.origin_right, forwardings, fuel), elements)

  let left_pos = case left {
    None -> -1
    Some(id) ->
      case index_of_element(elements, id) {
        Ok(pos) -> pos
        Error(Nil) -> -1
      }
  }
  let total = list.length(elements)
  let right_pos = case right {
    None -> total
    Some(id) ->
      case index_of_element(elements, id) {
        Ok(pos) -> pos
        Error(Nil) -> total
      }
  }
  let window =
    elements
    |> list.drop(left_pos + 1)
    |> list.take(right_pos - left_pos - 1)
    |> list.map(scan_entry(_, forwardings, fuel))
  let offset =
    yata_scan(
      window,
      item_left,
      item_right,
      replica_of(item.id),
      0,
      0,
      dict.new(),
      dict.new(),
    )

  insert_element_at(elements, left_pos + 1 + offset, LiveEl(item))
}

type ScanEntry {
  ScanEntry(
    id: ItemId,
    left: Option(ItemId),
    right: Option(ItemId),
    stable: Bool,
  )
}

fn scan_entry(
  el: Element(a),
  forwardings: Dict(ItemId, Forwarding),
  fuel: Int,
) -> ScanEntry {
  case el {
    Stable(id, _) -> ScanEntry(id: id, left: None, right: None, stable: True)
    LiveEl(other) ->
      ScanEntry(
        id: other.id,
        left: chase_left(other.origin_left, forwardings, fuel),
        right: other.origin_right,
        stable: False,
      )
  }
}

/// Degrade origins that reference IDs this state has never seen (or whose
/// forwardings expired) to the document boundary, mirroring how unmerged
/// origins have always been treated.
fn resolve_origin(
  origin: Option(ItemId),
  elements: List(Element(a)),
) -> Option(ItemId) {
  case origin {
    None -> None
    Some(id) ->
      case contains_element_id(elements, id) {
        True -> Some(id)
        False -> None
      }
  }
}

fn yata_scan(
  window: List(ScanEntry),
  item_left: Option(ItemId),
  item_right: Option(ItemId),
  item_replica: ReplicaId,
  position: Int,
  dest: Int,
  before_origin: Dict(ItemId, Nil),
  conflicting: Dict(ItemId, Nil),
) -> Int {
  case window {
    [] -> dest
    [entry, ..rest] ->
      case entry.stable {
        True -> dest
        False -> {
          let before_origin = dict.insert(before_origin, entry.id, Nil)
          let conflicting = dict.insert(conflicting, entry.id, Nil)
          case
            scan_step(
              entry,
              item_left,
              item_right,
              item_replica,
              before_origin,
              conflicting,
            )
          {
            StopScan -> dest
            TakeAsLeft ->
              yata_scan(
                rest,
                item_left,
                item_right,
                item_replica,
                position + 1,
                position + 1,
                before_origin,
                dict.new(),
              )
            AdvancePast ->
              yata_scan(
                rest,
                item_left,
                item_right,
                item_replica,
                position + 1,
                dest,
                before_origin,
                conflicting,
              )
          }
        }
      }
  }
}

type ScanStep {
  /// The item belongs before this window entry: stop, keep current dest.
  StopScan
  /// This entry becomes the item's effective left neighbor.
  TakeAsLeft
  /// Undecided; keep this entry in the conflicting set and scan on.
  AdvancePast
}

fn scan_step(
  entry: ScanEntry,
  item_left: Option(ItemId),
  item_right: Option(ItemId),
  item_replica: ReplicaId,
  before_origin: Dict(ItemId, Nil),
  conflicting: Dict(ItemId, Nil),
) -> ScanStep {
  case entry.left == item_left {
    True ->
      case replica_id.compare(replica_of(entry.id), item_replica) {
        order.Lt -> TakeAsLeft
        order.Eq | order.Gt ->
          case entry.right == item_right {
            True -> StopScan
            False -> AdvancePast
          }
      }
    False ->
      case entry.left {
        None -> StopScan
        Some(entry_left) ->
          case
            dict.has_key(before_origin, entry_left),
            dict.has_key(conflicting, entry_left)
          {
            True, False -> TakeAsLeft
            True, True -> AdvancePast
            False, _ -> StopScan
          }
      }
  }
}

fn replica_of(id: ItemId) -> ReplicaId {
  let ItemId(rid, _) = id
  rid
}

fn index_of_element(
  elements: List(Element(a)),
  id: ItemId,
) -> Result(Int, Nil) {
  index_of_element_loop(elements, id, 0)
}

fn index_of_element_loop(
  elements: List(Element(a)),
  id: ItemId,
  current: Int,
) -> Result(Int, Nil) {
  case elements {
    [] -> Error(Nil)
    [el, ..rest] ->
      case element_id(el) == id {
        True -> Ok(current)
        False -> index_of_element_loop(rest, id, current + 1)
      }
  }
}

fn insert_element_at(
  elements: List(Element(a)),
  index: Int,
  el: Element(a),
) -> List(Element(a)) {
  case index <= 0 {
    True -> [el, ..elements]
    False ->
      case elements {
        [] -> [el]
        [first, ..rest] -> [first, ..insert_element_at(rest, index - 1, el)]
      }
  }
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

fn compare_item_ids(a: ItemId, b: ItemId) -> order.Order {
  let ItemId(a_replica, a_counter) = a
  let ItemId(b_replica, b_counter) = b

  case replica_id.compare(a_replica, b_replica) {
    order.Eq -> int.compare(a_counter, b_counter)
    other -> other
  }
}

// ---------------------------------------------------------------------------
// Merge internals
// ---------------------------------------------------------------------------

fn merge_item(a: Item(a), b: Item(a)) -> Item(a) {
  let #(origin_left, origin_right) = pick_origins(a, b)

  Item(
    id: a.id,
    origin_left: origin_left,
    origin_right: origin_right,
    value: a.value,
    deleted: merge_deleted(a.deleted, b.deleted),
    move: merge_move(a.move, b.move),
  )
}

/// Origins are immutable in normal operation, but extracting a block member
/// (for a volatile delete or move) synthesizes origins from local neighbors,
/// so two replicas can disagree. Pick deterministically so merge commutes.
fn pick_origins(a: Item(a), b: Item(a)) -> #(Option(ItemId), Option(ItemId)) {
  use <- bool.guard(
    a.origin_left == b.origin_left && a.origin_right == b.origin_right,
    #(a.origin_left, a.origin_right),
  )
  case
    compare_origin_pair(#(a.origin_left, a.origin_right), #(
      b.origin_left,
      b.origin_right,
    ))
  {
    order.Gt -> #(b.origin_left, b.origin_right)
    order.Lt | order.Eq -> #(a.origin_left, a.origin_right)
  }
}

fn compare_origin_pair(
  a: #(Option(ItemId), Option(ItemId)),
  b: #(Option(ItemId), Option(ItemId)),
) -> order.Order {
  let #(a_left, a_right) = a
  let #(b_left, b_right) = b
  case compare_optional_id(a_left, b_left) {
    order.Eq -> compare_optional_id(a_right, b_right)
    other -> other
  }
}

fn compare_optional_id(a: Option(ItemId), b: Option(ItemId)) -> order.Order {
  case a, b {
    None, None -> order.Eq
    None, Some(_) -> order.Lt
    Some(_), None -> order.Gt
    Some(a_id), Some(b_id) -> compare_item_ids(a_id, b_id)
  }
}

fn merge_deleted(a: Option(OpId), b: Option(OpId)) -> Option(OpId) {
  case a, b {
    None, None -> None
    Some(op), None -> Some(op)
    None, Some(op) -> Some(op)
    Some(a_op), Some(b_op) ->
      case compare_op_ids(a_op, b_op) {
        order.Gt -> Some(b_op)
        order.Lt | order.Eq -> Some(a_op)
      }
  }
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

fn frontier_covers(frontier: VersionVector, id: ItemId) -> Bool {
  let ItemId(rid, counter) = id
  version_vector.get(frontier, rid) >= counter
}

fn frontier_covers_op(frontier: VersionVector, op: OpId) -> Bool {
  let OpId(rid, counter) = op
  version_vector.get(frontier, rid) >= counter
}

// ---------------------------------------------------------------------------
// Forwarding internals
// ---------------------------------------------------------------------------

fn merge_forwarding_entries(
  a: Dict(ItemId, Forwarding),
  b: Dict(ItemId, Forwarding),
) -> Dict(ItemId, Forwarding) {
  dict.fold(b, a, fn(acc, id, forwarding) {
    case dict.get(acc, id) {
      Ok(existing) ->
        dict.insert(acc, id, pick_forwarding(existing, forwarding))
      Error(Nil) -> dict.insert(acc, id, forwarding)
    }
  })
}

fn pick_forwarding(a: Forwarding, b: Forwarding) -> Forwarding {
  case compare_origin_pair(#(a.left, a.right), #(b.left, b.right)) {
    order.Gt -> b
    order.Lt | order.Eq -> a
  }
}

/// Collapse forwarding chains: a target that was itself dropped in a later
/// pass (or on the other side of a merge) is chased to a retained ID, so a
/// single lookup always lands on a live target.
fn normalize_forwardings(
  entries: Dict(ItemId, Forwarding),
) -> Dict(ItemId, Forwarding) {
  let fuel = dict.size(entries) + 1
  dict.map_values(entries, fn(_id, forwarding) {
    let Forwarding(left, right) = forwarding
    Forwarding(
      left: chase_left(left, entries, fuel),
      right: chase_right(right, entries, fuel),
    )
  })
}

fn chase_left(
  target: Option(ItemId),
  entries: Dict(ItemId, Forwarding),
  fuel: Int,
) -> Option(ItemId) {
  case target, fuel <= 0 {
    None, _ -> None
    _, True -> target
    Some(id), False ->
      case dict.get(entries, id) {
        Ok(Forwarding(left, _)) -> chase_left(left, entries, fuel - 1)
        Error(Nil) -> target
      }
  }
}

fn chase_right(
  target: Option(ItemId),
  entries: Dict(ItemId, Forwarding),
  fuel: Int,
) -> Option(ItemId) {
  case target, fuel <= 0 {
    None, _ -> None
    _, True -> target
    Some(id), False ->
      case dict.get(entries, id) {
        Ok(Forwarding(_, right)) -> chase_right(right, entries, fuel - 1)
        Error(Nil) -> target
      }
  }
}
