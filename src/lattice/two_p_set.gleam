//// A two-phase set (2P-Set) CRDT.
////
//// Supports both add and remove, but an element can only be removed once. Once
//// removed (tombstoned), an element can never be re-added. Internally tracks
//// two sets: `added` and `removed`. An element is active if it is in `added`
//// but not in `removed`. Use `ORSet` if you need re-add after remove.
////
//// ## Example
////
//// ```gleam
//// import lattice/two_p_set
////
//// let set = two_p_set.new()
////   |> two_p_set.add("alice")
////   |> two_p_set.add("bob")
////   |> two_p_set.remove("bob")
//// two_p_set.contains(set, "alice")  // -> True
//// two_p_set.contains(set, "bob")    // -> False (tombstoned)
//// ```

import gleam/dynamic/decode
import gleam/json
import gleam/set

/// A 2P-Set (two-phase set) CRDT.
///
/// Tracks two monotonically-growing sets: `added` (elements ever added) and
/// `removed` (elements ever tombstoned). An element is active only when it
/// is in `added` but not in `removed`. Tombstoning is permanent — once
/// removed, an element cannot be re-added to the active set.
pub type TwoPSet(a) {
  TwoPSet(added: set.Set(a), removed: set.Set(a))
}

/// Create a new empty 2P-Set.
pub fn new() -> TwoPSet(a) {
  TwoPSet(added: set.new(), removed: set.new())
}

/// Add an element to the set.
///
/// If the element has already been tombstoned (removed), this call records the
/// element in `added` but the element will not be considered active because
/// the tombstone takes precedence.
pub fn add(tpset: TwoPSet(a), element: a) -> TwoPSet(a) {
  TwoPSet(added: set.insert(tpset.added, element), removed: tpset.removed)
}

/// Remove an element from the set by adding it to the tombstone set.
///
/// Once tombstoned, the element is permanently inactive. Removing an element
/// that was never added is also valid and creates a preemptive tombstone.
pub fn remove(tpset: TwoPSet(a), element: a) -> TwoPSet(a) {
  TwoPSet(added: tpset.added, removed: set.insert(tpset.removed, element))
}

/// Check if the set currently contains the given element.
///
/// Returns `True` only if `element` is in `added` and NOT in `removed`.
pub fn contains(tpset: TwoPSet(a), element: a) -> Bool {
  set.contains(tpset.added, element) && !set.contains(tpset.removed, element)
}

/// Return the set of all currently active elements.
///
/// Active elements are those in `added` that have not been tombstoned.
/// Equivalent to `added ∖ removed`.
pub fn value(tpset: TwoPSet(a)) -> set.Set(a) {
  set.filter(tpset.added, fn(element) { !set.contains(tpset.removed, element) })
}

/// Merge two 2P-Sets by taking the union of both added sets and both removed sets.
///
/// A tombstone on any replica propagates to all replicas after merge.
/// Merge is commutative, associative, and idempotent (a valid CRDT join).
pub fn merge(a: TwoPSet(el), b: TwoPSet(el)) -> TwoPSet(el) {
  TwoPSet(
    added: set.union(a.added, b.added),
    removed: set.union(a.removed, b.removed),
  )
}

/// Encode a `TwoPSet(String)` as a self-describing JSON value.
///
/// Format: `{"type": "two_p_set", "v": 1, "state": {"added": [...], "removed": [...]}}`
///
/// The encoded value can be restored with `from_json`.
pub fn to_json(tpset: TwoPSet(String)) -> json.Json {
  json.object([
    #("type", json.string("two_p_set")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("added", json.array(set.to_list(tpset.added), json.string)),
        #("removed", json.array(set.to_list(tpset.removed), json.string)),
      ]),
    ),
  ])
}

/// Decode a `TwoPSet(String)` from a JSON string produced by `to_json`.
///
/// Returns `Error` if the string is not valid JSON or does not match the
/// expected format.
pub fn from_json(
  json_string: String,
) -> Result(TwoPSet(String), json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use added <- decode.field("added", decode.list(decode.string))
      use removed <- decode.field("removed", decode.list(decode.string))
      decode.success(TwoPSet(
        added: set.from_list(added),
        removed: set.from_list(removed),
      ))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
