//// An observed-remove set (OR-Set) CRDT.
////
//// The most flexible set CRDT: supports add, remove, and re-add. Each add
//// creates a unique tag. Remove only deletes tags observed locally, so a
//// concurrent add on another replica survives (add-wins semantics). This makes
//// OR-Set suitable for collaborative data where elements may be toggled.
////
//// To prevent unbounded growth of tombstones, use the `prune` function with
//// a stable version vector (representing events seen by all replicas).
////
//// ## Example
////
//// ```gleam
//// import lattice/or_set
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
import gleam/list
import gleam/result
import gleam/set
import lattice/version_vector.{type VersionVector}

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
/// when its tag set is non-empty. Removing an element clears all its tags;
/// a concurrent add on another replica will have created a new tag that
/// survives the remove.
///
/// The `pruned` vector tracks the causal history that has been safely garbage
/// collected (tombstones removed).
pub type ORSet(a) {
  ORSet(
    replica_id: String,
    counter: Int,
    entries: dict.Dict(a, set.Set(Tag)),
    tombstones: set.Set(Tag),
    pruned: VersionVector,
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
    pruned: version_vector.new(),
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
    pruned: orset.pruned,
  )
}

/// Remove an element from the set.
///
/// Removes all currently observed tags for the element (observed-remove
/// semantics). Any concurrent add on another replica that created a new tag
/// not yet observed here will survive this remove after merging.
pub fn remove(orset: ORSet(a), element: a) -> ORSet(a) {
  let observed_tags = result.unwrap(dict.get(orset.entries, element), set.new())
  ORSet(
    replica_id: orset.replica_id,
    counter: orset.counter,
    entries: dict.delete(orset.entries, element),
    tombstones: set.union(orset.tombstones, observed_tags),
    pruned: orset.pruned,
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
  dict.fold(orset.entries, set.new(), fn(acc, element, tags) {
    case set.is_empty(tags) {
      True -> acc
      False -> set.insert(acc, element)
    }
  })
}

/// Merge two OR-Sets.
///
/// For each element, the merged tag set is the union of both sides' tags,
/// minus merged tombstones, and minus any tags dominated by the merged pruned vector.
///
/// An element is present if it has at least one tag in the merged result.
/// The merged counter is the maximum of both sides, ensuring future adds
/// on either replica generate unique tags.
///
/// Merge is commutative, associative, and idempotent (a valid CRDT join).
pub fn merge(a: ORSet(el), b: ORSet(el)) -> ORSet(el) {
  let merged_pruned = version_vector.merge(a.pruned, b.pruned)
  let merged_tombstones =
    set.union(a.tombstones, b.tombstones)
    |> set.filter(fn(tag) {
      let Tag(rid, c) = tag
      version_vector.get(merged_pruned, rid) < c
    })

  let a_keys = dict.keys(a.entries)
  let b_keys = dict.keys(b.entries)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  let merged_entries =
    list.fold(all_keys, dict.new(), fn(acc, element) {
      let a_tags = result.unwrap(dict.get(a.entries, element), set.new())
      let b_tags = result.unwrap(dict.get(b.entries, element), set.new())

      let combined =
        set.union(a_tags, b_tags)
        |> set.filter(fn(tag) {
          let Tag(rid, c) = tag
          // Filter out if in tombstones OR dominated by pruned vector
          !set.contains(merged_tombstones, tag)
          && version_vector.get(merged_pruned, rid) < c
        })

      case set.is_empty(combined) {
        True -> acc
        False -> dict.insert(acc, element, combined)
      }
    })

  let merged_counter = case a.counter > b.counter {
    True -> a.counter
    False -> b.counter
  }

  ORSet(
    replica_id: a.replica_id,
    counter: merged_counter,
    entries: merged_entries,
    tombstones: merged_tombstones,
    pruned: merged_pruned,
  )
}

/// Prune tombstones based on a stable version vector.
///
/// Updates the `pruned` vector by merging it with `stable_vv`. Any tombstones
/// dominated by the new `pruned` vector are removed. This function should only be
/// called with a version vector representing events that have been seen by all
/// replicas (causally stable), otherwise "zombie" updates might be incorrectly ignored.
pub fn prune(orset: ORSet(a), stable_vv: VersionVector) -> ORSet(a) {
  let new_pruned = version_vector.merge(orset.pruned, stable_vv)
  let pruned_tombstones =
    set.filter(orset.tombstones, fn(tag) {
      let Tag(rid, c) = tag
      version_vector.get(new_pruned, rid) < c
    })

  ORSet(..orset, tombstones: pruned_tombstones, pruned: new_pruned)
}

/// Encode an `ORSet(String)` as a self-describing JSON value.
///
/// Entries are encoded as a JSON dict where values are arrays of tag objects
/// `{"r": replica_id, "c": counter}`.
///
/// Format: `{"type": "or_set", "v": 2, "state": {"replica_id": "...", "counter": N, "entries": {...}, "tombstones": [...], "pruned": {...}}}`
///
/// The encoded value can be restored with `from_json`.
pub fn to_json(orset: ORSet(String)) -> json.Json {
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(orset.replica_id)),
        #("counter", json.int(orset.counter)),
        #(
          "entries",
          json.dict(orset.entries, fn(k) { k }, fn(tag_set) {
            json.array(set.to_list(tag_set), fn(tag) {
              let Tag(rid, c) = tag
              json.object([#("r", json.string(rid)), #("c", json.int(c))])
            })
          }),
        ),
        #(
          "tombstones",
          json.array(set.to_list(orset.tombstones), fn(tag) {
            let Tag(rid, c) = tag
            json.object([#("r", json.string(rid)), #("c", json.int(c))])
          }),
        ),
        #("pruned", version_vector.to_json(orset.pruned)),
      ]),
    ),
  ])
}

/// Decode an `ORSet(String)` from a JSON string produced by `to_json`.
///
/// Returns `Error` if the string is not valid JSON or does not match the
/// expected format. Supports v1 (no pruned field) and v2.
pub fn from_json(json_string: String) -> Result(ORSet(String), json.DecodeError) {
  let envelope_decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(type_tag, version))
  }
  let envelope_result = json.parse(from: json_string, using: envelope_decoder)

  let tag_decoder = {
    use r <- decode.field("r", decode.string)
    use c <- decode.field("c", decode.int)
    decode.success(Tag(replica_id: r, counter: c))
  }
  let tag_set_decoder = decode.map(decode.list(tag_decoder), set.from_list)

  // v1 decoder (no pruned field, optional tombstones)
  let v1_decoder_full = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field(
        "entries",
        decode.dict(decode.string, tag_set_decoder),
      )
      use tombstones <- decode.field("tombstones", tag_set_decoder)

      decode.success(ORSet(
        replica_id: replica_id,
        counter: counter,
        entries: entries,
        tombstones: tombstones,
        pruned: version_vector.new(),
      ))
    })
    decode.success(state)
  }

  let v1_decoder_compat = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field(
        "entries",
        decode.dict(decode.string, tag_set_decoder),
      )

      decode.success(ORSet(
        replica_id: replica_id,
        counter: counter,
        entries: entries,
        tombstones: set.new(),
        pruned: version_vector.new(),
      ))
    })
    decode.success(state)
  }

  // v2 decoder (includes pruned field)
  let v2_decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field(
        "entries",
        decode.dict(decode.string, tag_set_decoder),
      )
      use tombstones <- decode.field("tombstones", tag_set_decoder)

      // Decode pruned version vector
      use pruned_state <- decode.field("pruned", {
        use _type <- decode.field("type", decode.string)
        use _v <- decode.field("v", decode.int)
        use vv_state <- decode.field("state", {
          use clocks <- decode.field(
            "clocks",
            decode.dict(decode.string, decode.int),
          )
          decode.success(clocks)
        })
        decode.success(vv_state)
      })

      let pruned_vv = version_vector.from_dict(pruned_state)

      decode.success(ORSet(
        replica_id: replica_id,
        counter: counter,
        entries: entries,
        tombstones: tombstones,
        pruned: pruned_vv,
      ))
    })
    decode.success(state)
  }

  case envelope_result {
    Error(e) -> Error(e)
    Ok(#(type_tag, version)) ->
      case type_tag == "or_set" {
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=or_set",
                found: type_tag,
                path: [],
              ),
            ]),
          )
        True ->
          case version {
            1 -> {
              case json.parse(from: json_string, using: v1_decoder_full) {
                Ok(res) -> Ok(res)
                Error(_) ->
                  json.parse(from: json_string, using: v1_decoder_compat)
              }
            }
            2 -> json.parse(from: json_string, using: v2_decoder)
            _ ->
              Error(
                json.UnableToDecode([
                  decode.DecodeError(
                    expected: "v=1 or v=2",
                    found: int.to_string(version),
                    path: ["v"],
                  ),
                ]),
              )
          }
      }
  }
}
