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
//// import lattice_core/replica_id
//// import lattice_sets/or_set
////
//// let a = or_set.new(replica_id.new("node-a")) |> or_set.add("item")
//// let b = or_set.new(replica_id.new("node-b")) |> or_set.add("item") |> or_set.remove("item")
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
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}

/// A unique tag identifying a specific add operation.
///
/// Tags are opaque: users never construct them directly. They are created
/// internally by `add` and stored in the entries dict so that `remove` can
/// target exactly the tags observed at remove time, enabling add-wins
/// semantics for concurrent operations.
pub opaque type Tag {
  Tag(replica_id: ReplicaId, counter: Int)
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
/// The `pruned` vector tracks the causal history that has been safely garbage
/// collected (tombstones removed). Use `prune` to compact tombstones once
/// events are causally stable across all replicas.
pub opaque type ORSet(a) {
  ORSet(
    replica_id: ReplicaId,
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
pub fn new(replica_id: ReplicaId) -> ORSet(a) {
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
  let #(updated, _) = add_with_delta(orset, element)
  updated
}

/// Add an element and return both the new state and a delta.
///
/// The returned delta is an `ORSet` whose `entries` contains only the newly
/// inserted element with its single fresh tag, with empty tombstones and
/// pruned vector. Merging the delta into a remote via `merge` adds the new
/// tag to the remote's entry for `element` (creating it if necessary),
/// producing the same observable result as merging the full new state.
///
/// The delta carries this replica's `replica_id` and the post-mutation
/// `counter`, so successive deltas remain causally distinguishable.
pub fn add_with_delta(orset: ORSet(a), element: a) -> #(ORSet(a), ORSet(a)) {
  let new_counter = orset.counter + 1
  let tag = Tag(replica_id: orset.replica_id, counter: new_counter)
  let existing_tags = result.unwrap(dict.get(orset.entries, element), set.new())
  let new_tags = set.insert(existing_tags, tag)
  let updated =
    ORSet(
      replica_id: orset.replica_id,
      counter: new_counter,
      entries: dict.insert(orset.entries, element, new_tags),
      tombstones: orset.tombstones,
      pruned: orset.pruned,
    )
  let delta =
    ORSet(
      replica_id: orset.replica_id,
      counter: new_counter,
      entries: dict.from_list([#(element, set.from_list([tag]))]),
      tombstones: set.new(),
      pruned: version_vector.new(),
    )
  #(updated, delta)
}

/// Remove an element from the set.
///
/// Removes all currently observed tags for the element (observed-remove
/// semantics). Any concurrent add on another replica that created a new tag
/// not yet observed here will survive this remove after merging.
pub fn remove(orset: ORSet(a), element: a) -> ORSet(a) {
  let #(updated, _) = remove_with_delta(orset, element)
  updated
}

/// Remove an element and return both the new state and a delta.
///
/// The returned delta is an `ORSet` whose `tombstones` contains exactly the
/// tags that were live for `element` at the time of the remove, with empty
/// entries and pruned vector. Merging the delta into a remote via `merge`
/// retracts those tags from the remote's entry for `element`. Tags that the
/// remote has but the delta source had not yet observed (concurrent adds)
/// survive — preserving the add-wins property of OR-Set.
pub fn remove_with_delta(orset: ORSet(a), element: a) -> #(ORSet(a), ORSet(a)) {
  let removed_tags = result.unwrap(dict.get(orset.entries, element), set.new())
  let updated =
    ORSet(
      replica_id: orset.replica_id,
      counter: orset.counter,
      entries: dict.delete(orset.entries, element),
      tombstones: set.union(orset.tombstones, removed_tags),
      pruned: orset.pruned,
    )
  let delta =
    ORSet(
      replica_id: orset.replica_id,
      counter: orset.counter,
      entries: dict.new(),
      tombstones: removed_tags,
      pruned: version_vector.new(),
    )
  #(updated, delta)
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
/// For each element, the merged tag set is the union of both sides' tags,
/// minus merged tombstones, and minus any tags dominated by the merged
/// pruned vector that are not live on the side that pruned them (zombie
/// detection). An element is present if it has at least one surviving tag.
///
/// The merged counter is the maximum of both sides, ensuring future adds on
/// either replica generate unique tags.
///
/// Merge is commutative, associative, and idempotent (a valid CRDT join).
pub fn merge(a: ORSet(el), b: ORSet(el)) -> ORSet(el) {
  let merged_pruned = version_vector.merge(a.pruned, b.pruned)
  let merged_tombstones =
    set.union(a.tombstones, b.tombstones)
    |> set.filter(fn(tag) { not_dominated(tag, merged_pruned) })
  let merged_counter = int.max(a.counter, b.counter)

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
          !set.contains(merged_tombstones, tag)
          && !is_pruned_zombie(tag, a_tags, a.pruned, b_tags, b.pruned)
        })

      case set.is_empty(combined) {
        True -> acc
        False -> dict.insert(acc, element, combined)
      }
    })

  ORSet(
    replica_id: a.replica_id,
    counter: merged_counter,
    entries: merged_entries,
    tombstones: merged_tombstones,
    pruned: merged_pruned,
  )
}

fn not_dominated(tag: Tag, pruned: VersionVector) -> Bool {
  let Tag(rid, c) = tag
  version_vector.get(pruned, rid) < c
}

fn is_pruned_zombie(
  tag: Tag,
  a_tags: set.Set(Tag),
  a_pruned: VersionVector,
  b_tags: set.Set(Tag),
  b_pruned: VersionVector,
) -> Bool {
  pruned_on_side_without_live_tag(tag, a_tags, a_pruned)
  || pruned_on_side_without_live_tag(tag, b_tags, b_pruned)
}

fn pruned_on_side_without_live_tag(
  tag: Tag,
  live_tags: set.Set(Tag),
  pruned: VersionVector,
) -> Bool {
  let Tag(rid, c) = tag
  version_vector.get(pruned, rid) >= c && !set.contains(live_tags, tag)
}

/// Remove an element and return a causal bound for the removed tags.
///
/// Behaves identically to `remove` but also returns a `VersionVector`
/// representing the maximum counter per replica across all tags that were
/// live for the element. This bound can be compared against a pruned vector
/// to determine when the removal is causally stable.
///
/// Returns an empty `VersionVector` if the element had no live tags.
pub fn remove_with_bound(
  orset: ORSet(a),
  element: a,
) -> #(ORSet(a), VersionVector) {
  let removed_tags = result.unwrap(dict.get(orset.entries, element), set.new())
  let bound = tags_to_bound(removed_tags)
  let updated =
    ORSet(
      ..orset,
      entries: dict.delete(orset.entries, element),
      tombstones: set.union(orset.tombstones, removed_tags),
    )
  #(updated, bound)
}

fn tags_to_bound(tags: set.Set(Tag)) -> VersionVector {
  set.fold(tags, version_vector.new(), fn(vv, tag) {
    let Tag(rid, c) = tag
    version_vector.set_max(vv, rid, c)
  })
}

/// Return the pruned version vector.
///
/// This is the causal horizon below which tombstones have been garbage
/// collected. Useful for determining whether a remove bound is fully
/// dominated (causally stable).
pub fn pruned_vv(orset: ORSet(a)) -> VersionVector {
  orset.pruned
}

/// Prune tombstones based on a stable version vector.
///
/// Updates the `pruned` vector by merging it with `stable_vv`. Any tombstones
/// dominated by the new `pruned` vector are removed. This function should only
/// be called with a version vector representing events that have been seen by
/// all replicas (causally stable), otherwise "zombie" updates might be
/// incorrectly ignored.
pub fn prune(orset: ORSet(a), stable_vv: VersionVector) -> ORSet(a) {
  let new_pruned = version_vector.merge(orset.pruned, stable_vv)
  let pruned_tombstones =
    set.filter(orset.tombstones, fn(tag) { not_dominated(tag, new_pruned) })

  ORSet(..orset, tombstones: pruned_tombstones, pruned: new_pruned)
}

/// Encode an `ORSet(String)` as a self-describing JSON value.
///
/// Entries are encoded as a JSON dict where values are arrays of tag objects
/// `{"r": replica_id, "c": counter}`. Removed tags are encoded separately in
/// `tombstones`. The `pruned` version vector tracks garbage-collected causal
/// history.
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
        #("replica_id", replica_id.to_json(orset.replica_id)),
        #("counter", json.int(orset.counter)),
        #(
          "entries",
          json.dict(orset.entries, fn(k) { k }, fn(tag_set) {
            json.array(set.to_list(tag_set), encode_tag)
          }),
        ),
        #("tombstones", json.array(set.to_list(orset.tombstones), encode_tag)),
        #("pruned", version_vector.to_json(orset.pruned)),
      ]),
    ),
  ])
}

/// Decode an `ORSet(String)` from a JSON string produced by `to_json`.
///
/// Supports both v1 (no pruned field) and v2 formats. Returns `Error` if the
/// string is not valid JSON or does not match the expected format.
pub fn from_json(
  json_string: String,
) -> Result(ORSet(String), json.DecodeError) {
  let tag_decoder = {
    use r <- decode.field("r", replica_id.decoder())
    use c <- decode.field("c", decode.int)
    decode.success(Tag(replica_id: r, counter: c))
  }
  let tag_set_decoder = decode.map(decode.list(tag_decoder), set.from_list)

  let v1_state_decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", replica_id.decoder())
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
        pruned: version_vector.new(),
      ))
    })
    decode.success(state)
  }

  let v2_state_decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", replica_id.decoder())
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field(
        "entries",
        decode.dict(decode.string, tag_set_decoder),
      )
      use tombstones <- decode.field("tombstones", tag_set_decoder)
      use pruned <- decode.field("pruned", version_vector.decoder())
      decode.success(ORSet(
        replica_id: replica_id,
        counter: counter,
        entries: entries,
        tombstones: tombstones,
        pruned: pruned,
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
            1 -> json.parse(from: json_string, using: v1_state_decoder)
            2 -> json.parse(from: json_string, using: v2_state_decoder)
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

fn encode_tag(tag: Tag) -> json.Json {
  let Tag(rid, c) = tag
  json.object([
    #("r", json.string(replica_id.to_string(rid))),
    #("c", json.int(c)),
  ])
}
