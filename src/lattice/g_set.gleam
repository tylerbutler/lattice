import gleam/dynamic/decode
import gleam/json
import gleam/set

/// A G-Set (Grow-only Set) CRDT
/// Elements can only be added, never removed; merge is set union
pub type GSet(a) {
  GSet(elements: set.Set(a))
}

/// Create a new empty G-Set
pub fn new() -> GSet(a) {
  GSet(elements: set.new())
}

/// Add an element to the set (idempotent)
pub fn add(g_set: GSet(a), element: a) -> GSet(a) {
  GSet(elements: set.insert(g_set.elements, element))
}

/// Check if the set contains the given element
pub fn contains(g_set: GSet(a), element: a) -> Bool {
  set.contains(g_set.elements, element)
}

/// Return the underlying set of all elements
pub fn value(g_set: GSet(a)) -> set.Set(a) {
  g_set.elements
}

/// Encode a GSet(String) as a self-describing JSON value.
/// Format: {"type": "g_set", "v": 1, "state": {"elements": [...]}}
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

/// Decode a GSet(String) from a JSON string produced by to_json.
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

/// Merge two G-Sets by computing their union
pub fn merge(a: GSet(el), b: GSet(el)) -> GSet(el) {
  GSet(elements: set.union(a.elements, b.elements))
}
