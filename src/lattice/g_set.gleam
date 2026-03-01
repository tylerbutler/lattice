//// A grow-only set (G-Set) CRDT.
////
//// Elements can be added but never removed. Merge is set union, so any element
//// added on any replica will eventually appear in all replicas. This is the
//// simplest set CRDT — use `TwoPSet` or `ORSet` if you need removal.
////
//// ## Example
////
//// ```gleam
//// import lattice/g_set
////
//// let a = g_set.new() |> g_set.add("alice")
//// let b = g_set.new() |> g_set.add("bob")
//// let merged = g_set.merge(a, b)
//// g_set.contains(merged, "alice")  // -> True
//// g_set.contains(merged, "bob")    // -> True
//// ```

import gleam/dynamic/decode
import gleam/json
import gleam/set

/// A G-Set (grow-only set) CRDT.
///
/// Wraps a `set.Set` and enforces monotonicity: elements are only ever added,
/// never removed. Two `GSet` values on different replicas converge when merged
/// because merge is set union.
pub type GSet(a) {
  GSet(elements: set.Set(a))
}

/// Create a new empty G-Set.
pub fn new() -> GSet(a) {
  GSet(elements: set.new())
}

/// Add an element to the set.
///
/// This operation is idempotent: adding the same element multiple times is
/// equivalent to adding it once.
pub fn add(g_set: GSet(a), element: a) -> GSet(a) {
  GSet(elements: set.insert(g_set.elements, element))
}

/// Check if the set contains the given element.
///
/// Returns `True` if `element` was ever added to this set or any merged replica.
pub fn contains(g_set: GSet(a), element: a) -> Bool {
  set.contains(g_set.elements, element)
}

/// Return the underlying set of all elements.
///
/// Equivalent to inspecting the entire current state of the G-Set.
pub fn value(g_set: GSet(a)) -> set.Set(a) {
  g_set.elements
}

/// Merge two G-Sets by computing their union.
///
/// The result contains every element that was ever added to either set.
/// Merge is commutative, associative, and idempotent (a valid CRDT join).
pub fn merge(a: GSet(el), b: GSet(el)) -> GSet(el) {
  GSet(elements: set.union(a.elements, b.elements))
}

/// Encode a `GSet(String)` as a self-describing JSON value.
///
/// Format: `{"type": "g_set", "v": 1, "state": {"elements": [...]}}`
///
/// The encoded value can be restored with `from_json`.
pub fn to_json(g_set: GSet(String)) -> json.Json {
  json.object([
    #("type", json.string("g_set")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("elements", json.array(set.to_list(g_set.elements), json.string)),
      ]),
    ),
  ])
}

/// Decode a `GSet(String)` from a JSON string produced by `to_json`.
///
/// Returns `Error` if the string is not valid JSON or does not match the
/// expected format.
pub fn from_json(json_string: String) -> Result(GSet(String), json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use elements <- decode.field("elements", decode.list(decode.string))
      decode.success(GSet(elements: set.from_list(elements)))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
