//// A dot context tracks observed events (dots) across replicas.
////
//// A "dot" is a pair of (replica_id, counter) uniquely identifying a single
//// write event. The dot context is used by causal CRDTs like MV-Register and
//// OR-Set to determine which operations have been observed and which can be
//// safely discarded during merge.
////
//// ## Example
////
//// ```gleam
//// import lattice/dot_context.{Dot}
////
//// let ctx = dot_context.new()
////   |> dot_context.add_dot("node-a", 1)
////   |> dot_context.add_dot("node-b", 1)
//// dot_context.contains_dots(ctx, [Dot("node-a", 1)])  // -> True
//// ```

import gleam/list
import gleam/set

/// A unique identifier for a single write event at a specific replica.
///
/// `replica_id` identifies the replica that produced the event and `counter`
/// is the replica's logical clock value at the time of the write. Together
/// they form a globally unique event identifier. Users construct `Dot` values
/// when calling `contains_dots` or `remove_dots`.
pub type Dot {
  Dot(replica_id: String, counter: Int)
}

/// An opaque set of observed dots (write events).
///
/// Use `new`, `add_dot`, `remove_dots`, and `contains_dots` to interact
/// with a DotContext. The internal set representation is hidden to allow
/// future changes to the storage strategy.
pub opaque type DotContext {
  DotContext(dots: set.Set(Dot))
}

/// Create a new empty DotContext.
///
/// Returns a context with no observed dots. Use `add_dot` to record events.
pub fn new() -> DotContext {
  DotContext(dots: set.new())
}

/// Add a specific dot to the context.
///
/// Records that the event `(replica_id, counter)` has been observed. If the
/// dot is already present, the context is returned unchanged.
pub fn add_dot(
  context: DotContext,
  replica_id: String,
  counter: Int,
) -> DotContext {
  DotContext(dots: set.insert(context.dots, Dot(replica_id:, counter:)))
}

/// Remove a list of dots from the context.
///
/// Returns a new context with all dots in `dots` removed. Dots that are not
/// present are silently ignored.
pub fn remove_dots(context: DotContext, dots: List(Dot)) -> DotContext {
  DotContext(
    dots: list.fold(dots, context.dots, fn(acc, dot) { set.delete(acc, dot) }),
  )
}

/// Check if all given dots are present in the context.
///
/// Returns `True` only if every dot in `dots` has been observed (i.e., every
/// dot was previously added via `add_dot` and not subsequently removed).
/// Returns `True` for an empty `dots` list.
pub fn contains_dots(context: DotContext, dots: List(Dot)) -> Bool {
  list.all(dots, fn(dot) { set.contains(context.dots, dot) })
}
