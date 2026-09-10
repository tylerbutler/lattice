//// Generation selection and observed-remove membership, independent of child types.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None}
import gleam/order.{type Order, Eq, Gt, Lt}
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_sets/or_set.{type ORSet}

pub type Generation {
  Initial
  Generation(clock: Int, creator: ReplicaId)
}

// Each key/generation has an independent, namespaced ORSet causal context.
// An entry is also the permanent generation floor, even without membership.
pub type Entry(value) {
  Entry(generation: Generation, membership: ORSet(String), value: Option(value))
}

pub type State(value) {
  State(clock: Int, entries: Dict(String, Entry(value)))
}

pub fn new() -> State(value) {
  State(0, dict.new())
}

pub fn compare(a: Generation, b: Generation) -> Order {
  case a, b {
    Initial, Initial -> Eq
    Initial, _ -> Lt
    _, Initial -> Gt
    Generation(ac, ar), Generation(bc, br) ->
      case int.compare(ac, bc) {
        Eq -> string.compare(replica_id.to_string(ar), replica_id.to_string(br))
        other -> other
      }
  }
}

pub fn clock(generation: Generation) -> Int {
  case generation {
    Initial -> 0
    Generation(clock, _) -> clock
  }
}

pub fn active(entry: Entry(value), key: String) -> Bool {
  or_set.contains(entry.membership, key)
}

pub fn prepare(
  state: State(value),
  key: String,
  writer: ReplicaId,
) -> Entry(value) {
  case dict.get(state.entries, key) {
    Error(Nil) -> Entry(Initial, or_set.new(writer), None)
    Ok(entry) ->
      case active(entry, key) {
        True ->
          Entry(
            ..entry,
            membership: or_set.merge(or_set.new(writer), entry.membership),
          )
        False ->
          Entry(Generation(state.clock + 1, writer), or_set.new(writer), None)
      }
  }
}

pub fn singleton(
  key: String,
  entry: Entry(value),
  high_water: Int,
) -> State(value) {
  State(
    int.max(high_water, clock(entry.generation)),
    dict.from_list([#(key, entry)]),
  )
}

pub fn remove(
  state: State(value),
  key: String,
) -> #(State(value), State(change)) {
  case dict.get(state.entries, key) {
    Error(Nil) -> #(state, new())
    Ok(entry) -> {
      let #(membership, delta) = or_set.remove_with_delta(entry.membership, key)
      #(
        State(
          ..state,
          entries: dict.insert(
            state.entries,
            key,
            Entry(..entry, membership: membership),
          ),
        ),
        singleton(key, Entry(entry.generation, delta, None), state.clock),
      )
    }
  }
}

/// Select generations before joining values. Absence is never an older baseline.
pub fn join(
  a: State(left),
  b: State(right),
  combine: fn(String, Generation, Option(left), Option(right)) ->
    Result(Option(out), error),
) -> Result(State(out), error) {
  let entries =
    dict.to_list(a.entries)
    |> list.map(fn(pair) { #(pair.0, pair.1, dict.get(b.entries, pair.0)) })
  let only_b =
    dict.to_list(b.entries)
    |> list.filter(fn(pair) { !dict.has_key(a.entries, pair.0) })
  use entries <- result.try(
    list.try_fold(entries, dict.new(), fn(entries, pair) {
      let #(key, a, b) = pair
      let #(generation, membership, left, right) = case b {
        Ok(b) ->
          case compare(a.generation, b.generation) {
            Gt -> #(a.generation, a.membership, a.value, None)
            Lt -> #(b.generation, b.membership, None, b.value)
            Eq -> #(
              a.generation,
              or_set.merge(a.membership, b.membership),
              a.value,
              b.value,
            )
          }
        Error(Nil) -> #(a.generation, a.membership, a.value, None)
      }
      use value <- result.try(combine(key, generation, left, right))
      Ok(dict.insert(entries, key, Entry(generation, membership, value)))
    }),
  )
  use entries <- result.try(
    list.try_fold(only_b, entries, fn(entries, pair) {
      let #(key, entry) = pair
      use value <- result.try(combine(key, entry.generation, None, entry.value))
      Ok(dict.insert(
        entries,
        key,
        Entry(entry.generation, entry.membership, value),
      ))
    }),
  )
  Ok(State(int.max(a.clock, b.clock), entries))
}

pub fn prune(state: State(value), stable: VersionVector) -> State(value) {
  State(
    ..state,
    entries: dict.map_values(state.entries, fn(_, entry) {
      Entry(..entry, membership: or_set.prune(entry.membership, stable))
    }),
  )
}
