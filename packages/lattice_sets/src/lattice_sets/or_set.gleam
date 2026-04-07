//// An observed-remove set (OR-Set) CRDT.
////
//// The most flexible set CRDT: supports add, remove, and re-add. Each add
//// creates a unique tag. Remove only deletes tags observed locally, so a
//// concurrent add on another replica survives (add-wins semantics). This makes
//// OR-Set suitable for collaborative data where elements may be toggled.
////
//// ## Example
////
//// ```gleam
//// import lattice_sets/or_set
////
//// let a = or_set.new("node-a") |> or_set.add("item")
//// let b = or_set.new("node-b") |> or_set.add("item") |> or_set.remove("item")
//// let merged = or_set.merge(a, b)
//// or_set.contains(merged, "item")  // -> True (concurrent add wins)
//// ```

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/result
import gleam/set

/// A unique tag identifying a specific add operation.
///
/// Tags are opaque: users never construct them directly. They are created
/// internally by `add` and stored in the entries dict so that `remove` can
/// target exactly the tags observed at remove time, enabling add-wins
/// semantics for concurrent operations.
pub opaque type Tag {
  Tag(replica_id: String, counter: Int)
}

/// An OR-Set (observed-remove set) CRDT.
///
/// Each element maps to a set of tags representing the add operations that
/// are currently "live" for that element. An element is present in the set
/// when its tag set is non-empty. Removed tags are retained in `tombstones`
/// so stale replicas cannot resurrect elements that were already observed and
/// removed elsewhere. A concurrent add on another replica will have created a
/// new tag that survives the remove.
///
/// **Note:** Do not pattern-match on the constructor fields directly in
/// application code. The internal representation may change in a future
/// major version. Use the provided public API (`new`, `add`, `remove`,
/// `contains`, `merge`, `value`, `to_json`, `from_json`) for all operations.
pub opaque type ORSet(a) {
  ORSet(
    replica_id: String,
    counter: Int,
    entries: dict.Dict(a, set.Set(Tag)),
    tombstones: set.Set(Tag),
  )
}

/// Create a new empty OR-Set for the given replica.
///
/// Each replica should have a unique `replica_id` to ensure that tags
/// generated on different replicas never collide.
pub fn new(replica_id: String) -> ORSet(a) {
  ORSet(
    replica_id: replica_id,
    counter: 0,
    entries: dict.new(),
    tombstones: set.new(),
  )
}

/// Add an element to the set.
///
/// Creates a fresh unique tag for this add operation using the replica's
/// monotonically-increasing counter. The element may already be present;
/// in that case a new tag is added alongside existing ones.
pub fn add(orset: ORSet(a), element: a) -> ORSet(a) {
  let new_counter = orset.counter + 1
  let tag = Tag(replica_id: orset.replica_id, counter: new_counter)
  let existing_tags = result.unwrap(dict.get(orset.entries, element), set.new())
  let new_tags = set.insert(existing_tags, tag)
  ORSet(
    replica_id: orset.replica_id,
    counter: new_counter,
    entries: dict.insert(orset.entries, element, new_tags),
    tombstones: orset.tombstones,
  )
}

/// Remove an element from the set.
///
/// Removes all currently observed tags for the element (observed-remove
/// semantics). Any concurrent add on another replica that created a new tag
/// not yet observed here will survive this remove after merging.
pub fn remove(orset: ORSet(a), element: a) -> ORSet(a) {
  let removed_tags = result.unwrap(dict.get(orset.entries, element), set.new())
  ORSet(
    replica_id: orset.replica_id,
    counter: orset.counter,
    entries: dict.delete(orset.entries, element),
    tombstones: set.union(orset.tombstones, removed_tags),
  )
}

/// Check if the set contains the given element.
///
/// Returns `True` if the element has at least one live tag (i.e., it has
/// been added and not yet removed on this replica, or a concurrent add
/// survived a remove after merging).
pub fn contains(orset: ORSet(a), element: a) -> Bool {
  case dict.get(orset.entries, element) {
    Error(_) -> False
    Ok(tags) -> !set.is_empty(tags)
  }
}

/// Return the set of all elements currently in the OR-Set.
///
/// An element is included only when its tag set is non-empty.
pub fn value(orset: ORSet(a)) -> set.Set(a) {
  // We maintain the invariant that entries only contains keys with non-empty tag sets
  // (via merge/remove logic).
  dict.keys(orset.entries)
  |> set.from_list
}

/// Merge two OR-Sets.
///
/// For each element, the merged tag set is the union of both sides' tags with
/// any tombstoned tags removed. This prevents stale replicas from
/// reintroducing tags that have already been observed and removed elsewhere.
/// The merged counter is the maximum of both sides, ensuring future adds on
/// either replica generate unique tags.
///
/// Merge is commutative, associative, and idempotent (a valid CRDT join).
///
/// **Known limitation:** removing an element on one replica and then merging
/// with a stale replica that still has the element can resurrect it, because
/// the remove only deletes locally-observed tags. A tombstone-based fix
/// requires changing the type layout and is deferred to v2.0.
/// See https://github.com/tylerbutler/lattice/issues/27.
pub fn merge(a: ORSet(el), b: ORSet(el)) -> ORSet(el) {
  let merged_tombstones = set.union(a.tombstones, b.tombstones)
  let merged_counter = int.max(a.counter, b.counter)

  // Filter B entries against tombstones
  let clean_b =
    dict.fold(b.entries, dict.new(), fn(acc, key, tags) {
      let remaining = set.difference(tags, merged_tombstones)
      case set.is_empty(remaining) {
        True -> acc
        False -> dict.insert(acc, key, remaining)
      }
    })

  // Merge A entries
  let merged_entries =
    dict.fold(a.entries, clean_b, fn(acc, key, tags) {
      let remaining = set.difference(tags, merged_tombstones)
      case set.is_empty(remaining) {
        True -> acc
        False ->
          case dict.get(acc, key) {
            Ok(existing) ->
              dict.insert(acc, key, set.union(existing, remaining))
            Error(_) -> dict.insert(acc, key, remaining)
          }
      }
    })

  ORSet(
    replica_id: a.replica_id,
    counter: merged_counter,
    entries: merged_entries,
    tombstones: merged_tombstones,
  )
}

/// Encode an `ORSet(String)` as a self-describing JSON value.
///
/// Entries are encoded as a JSON dict where values are arrays of tag objects
/// `{"r": replica_id, "c": counter}`. Removed tags are encoded separately in
/// `tombstones`.
///
/// Format: `{"type": "or_set", "v": 1, "state": {"replica_id": "...", "counter": N, "entries": {...}, "tombstones": [...]}}`
///
/// The encoded value can be restored with `from_json`.
pub fn to_json(orset: ORSet(String)) -> json.Json {
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(orset.replica_id)),
        #("counter", json.int(orset.counter)),
        #(
          "entries",
          json.dict(orset.entries, fn(k) { k }, fn(tag_set) {
            json.array(set.to_list(tag_set), encode_tag)
          }),
        ),
        #("tombstones", json.array(set.to_list(orset.tombstones), encode_tag)),
      ]),
    ),
  ])
}

/// Decode an `ORSet(String)` from a JSON string produced by `to_json`.
///
/// Returns `Error` if the string is not valid JSON or does not match the
/// expected format.
pub fn from_json(json_string: String) -> Result(ORSet(String), json.DecodeError) {
  let tag_decoder = {
    use r <- decode.field("r", decode.string)
    use c <- decode.field("c", decode.int)
    decode.success(Tag(replica_id: r, counter: c))
  }
  let tag_set_decoder = decode.map(decode.list(tag_decoder), set.from_list)
  let state_decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field(
        "entries",
        decode.dict(decode.string, tag_set_decoder),
      )
      use tombstones <- decode.optional_field(
        "tombstones",
        [],
        decode.list(tag_decoder),
      )
      decode.success(ORSet(
        replica_id: replica_id,
        counter: counter,
        entries: entries,
        tombstones: set.from_list(tombstones),
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
      case type_tag == "or_set" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=or_set and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}

fn encode_tag(tag: Tag) -> json.Json {
  let Tag(rid, c) = tag
  json.object([#("r", json.string(rid)), #("c", json.int(c))])
}
