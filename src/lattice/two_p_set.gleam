import gleam/dynamic/decode
import gleam/json
import gleam/set

/// A 2P-Set (Two-Phase Set) CRDT
/// Supports both add and remove; once removed, elements cannot be re-added (tombstone semantics)
pub type TwoPSet(a) {
  TwoPSet(added: set.Set(a), removed: set.Set(a))
}

/// Create a new empty 2P-Set
pub fn new() -> TwoPSet(a) {
  TwoPSet(added: set.new(), removed: set.new())
}

/// Add an element to the set.
/// Has no effect if the element has been tombstoned (previously removed).
pub fn add(tpset: TwoPSet(a), element: a) -> TwoPSet(a) {
  TwoPSet(added: set.insert(tpset.added, element), removed: tpset.removed)
}

/// Remove an element from the set.
/// Adds the element to the tombstone (removed) set.
/// Once removed, the element cannot be re-added.
pub fn remove(tpset: TwoPSet(a), element: a) -> TwoPSet(a) {
  TwoPSet(added: tpset.added, removed: set.insert(tpset.removed, element))
}

/// Check if the set currently contains the given element.
/// An element is present if it is in the added set but NOT in the removed set.
pub fn contains(tpset: TwoPSet(a), element: a) -> Bool {
  set.contains(tpset.added, element) && !set.contains(tpset.removed, element)
}

/// Return the set of all currently active elements.
/// Active = added minus removed.
pub fn value(tpset: TwoPSet(a)) -> set.Set(a) {
  set.filter(tpset.added, fn(element) { !set.contains(tpset.removed, element) })
}

/// Encode a TwoPSet(String) as a self-describing JSON value.
/// Format: {"type": "two_p_set", "v": 1, "state": {"added": [...], "removed": [...]}}
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

/// Decode a TwoPSet(String) from a JSON string produced by to_json.
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

/// Merge two 2P-Sets by taking the union of both added sets and both removed sets.
pub fn merge(a: TwoPSet(el), b: TwoPSet(el)) -> TwoPSet(el) {
  TwoPSet(
    added: set.union(a.added, b.added),
    removed: set.union(a.removed, b.removed),
  )
}
