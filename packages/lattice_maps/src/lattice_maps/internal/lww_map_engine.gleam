//// Atomic assignments. Child states are never joined across write identities.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order.{Eq, Gt, Lt}
import gleam/result
import gleam/string
import lattice_core/replica_id.{type ReplicaId}

pub type Provenance {
  Modern(writer: ReplicaId)
  Legacy(tie_key: String)
}

pub type Entry(value) {
  Entry(value: Option(value), timestamp: Int, provenance: Provenance)
}

pub type State(value) {
  State(entries: Dict(String, Entry(value)), pruned_timestamp: Int)
}

pub type Error {
  TimestampNotAdvanced(key: String, timestamp: Int, floor: Int)
  ConflictingWrite(key: String, timestamp: Int)
  InvalidTimestamp(key: String, timestamp: Int)
}

pub fn new() -> State(value) {
  State(dict.new(), 0)
}

pub fn check_timestamp(
  state: State(value),
  key: String,
  timestamp: Int,
) -> Result(Nil, Error) {
  let floor = case dict.get(state.entries, key) {
    Ok(entry) -> int.max(entry.timestamp, state.pruned_timestamp)
    Error(Nil) -> state.pruned_timestamp
  }
  case timestamp > 9_007_199_254_740_991 || timestamp < -9_007_199_254_740_991 {
    True -> Error(InvalidTimestamp(key, timestamp))
    False ->
      case timestamp > floor {
        True -> Ok(Nil)
        False -> Error(TimestampNotAdvanced(key, timestamp, floor))
      }
  }
}

pub fn put(
  state: State(value),
  key: String,
  entry: Entry(value),
) -> State(value) {
  State(..state, entries: dict.insert(state.entries, key, entry))
}

fn choose(
  key: String,
  a: Entry(value),
  b: Entry(value),
  equal: fn(value, value) -> Bool,
) -> Result(Entry(value), Error) {
  case int.compare(a.timestamp, b.timestamp) {
    Gt -> Ok(a)
    Lt -> Ok(b)
    Eq -> choose_equal_timestamp(key, a, b, equal)
  }
}

fn choose_equal_timestamp(
  key: String,
  a: Entry(value),
  b: Entry(value),
  equal: fn(value, value) -> Bool,
) -> Result(Entry(value), Error) {
  case a.provenance, b.provenance {
    Modern(aw), Modern(bw) if aw == bw -> {
      let same = case a.value, b.value {
        Some(av), Some(bv) -> equal(av, bv)
        None, None -> True
        _, _ -> False
      }
      case same {
        True -> Ok(a)
        False -> Error(ConflictingWrite(key, a.timestamp))
      }
    }
    _, _ ->
      case a.value, b.value {
        None, Some(_) -> Ok(a)
        Some(_), None -> Ok(b)
        _, _ -> Ok(choose_provenance(a, b))
      }
  }
}

fn choose_provenance(a: Entry(value), b: Entry(value)) -> Entry(value) {
  case a.provenance, b.provenance {
    Modern(_), Legacy(_) -> a
    Legacy(_), Modern(_) -> b
    Legacy(ak), Legacy(bk) ->
      case string.compare(ak, bk) {
        Lt -> b
        _ -> a
      }
    Modern(aw), Modern(bw) ->
      case string.compare(replica_id.to_string(aw), replica_id.to_string(bw)) {
        Lt -> b
        _ -> a
      }
  }
}

pub fn merge(
  a: State(value),
  b: State(value),
  equal: fn(value, value) -> Bool,
) -> Result(State(value), Error) {
  let keys =
    dict.keys(a.entries) |> list.append(dict.keys(b.entries)) |> list.unique
  use entries <- result.try(
    list.try_fold(keys, dict.new(), fn(entries, key) {
      let winner = case dict.get(a.entries, key), dict.get(b.entries, key) {
        Ok(a), Ok(b) -> choose(key, a, b, equal) |> result.map(Some)
        Ok(entry), Error(Nil) ->
          Ok(case entry.timestamp > b.pruned_timestamp {
            True -> Some(entry)
            False -> None
          })
        Error(Nil), Ok(entry) ->
          Ok(case entry.timestamp > a.pruned_timestamp {
            True -> Some(entry)
            False -> None
          })
        Error(Nil), Error(Nil) -> Ok(None)
      }
      use winner <- result.try(winner)
      Ok(case winner {
        Some(entry) -> dict.insert(entries, key, entry)
        None -> entries
      })
    }),
  )
  Ok(prune(State(entries, int.max(a.pruned_timestamp, b.pruned_timestamp)), 0))
}

pub fn prune(state: State(value), stable: Int) -> State(value) {
  let floor = int.max(state.pruned_timestamp, stable)
  State(
    dict.filter(state.entries, fn(_, entry) {
      case entry.value {
        Some(_) -> True
        None -> entry.timestamp > floor
      }
    }),
    floor,
  )
}
