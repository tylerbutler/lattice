import gleam/list
import gleam/set

/// A Dot uniquely identifies a single event: a write by a replica at a specific counter value
pub type Dot {
  Dot(replica_id: String, counter: Int)
}

/// A DotContext tracks which events (dots) have been observed
pub type DotContext {
  DotContext(dots: set.Set(Dot))
}

/// Create a new empty DotContext
pub fn new() -> DotContext {
  DotContext(dots: set.new())
}

/// Add a specific dot to the context
pub fn add_dot(context: DotContext, replica_id: String, counter: Int) -> DotContext {
  DotContext(dots: set.insert(context.dots, Dot(replica_id:, counter:)))
}

/// Remove a list of dots from the context
pub fn remove_dots(context: DotContext, dots: List(Dot)) -> DotContext {
  DotContext(
    dots: list.fold(dots, context.dots, fn(acc, dot) { set.delete(acc, dot) }),
  )
}

/// Check if all given dots are present in the context
pub fn contains_dots(context: DotContext, dots: List(Dot)) -> Bool {
  list.all(dots, fn(dot) { set.contains(context.dots, dot) })
}
