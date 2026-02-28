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

/// Merge two G-Sets by computing their union
pub fn merge(a: GSet(el), b: GSet(el)) -> GSet(el) {
  GSet(elements: set.union(a.elements, b.elements))
}
