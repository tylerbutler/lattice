import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/set

/// A unique tag identifying a specific add operation
pub type Tag {
  Tag(replica_id: String, counter: Int)
}

/// An OR-Set (Observed-Remove Set) CRDT
/// Supports both add and remove operations; concurrent add wins over remove
pub type ORSet(a) {
  ORSet(replica_id: String, counter: Int, entries: dict.Dict(a, set.Set(Tag)))
}

/// Encode an ORSet(String) as a self-describing JSON value.
/// Entries (Dict(String, set.Set(Tag))) are encoded as a JSON dict where
/// values are arrays of tag objects {r, c}.
/// Format: {"type": "or_set", "v": 1, "state": {"replica_id": "...", "counter": N, "entries": {...}}}
pub fn to_json(orset: ORSet(String)) -> json.Json {
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(orset.replica_id)),
        #("counter", json.int(orset.counter)),
        #(
          "entries",
          json.dict(orset.entries, fn(k) { k }, fn(tag_set) {
            json.array(set.to_list(tag_set), fn(tag) {
              let Tag(rid, c) = tag
              json.object([#("r", json.string(rid)), #("c", json.int(c))])
            })
          }),
        ),
      ]),
    ),
  ])
}

/// Decode an ORSet(String) from a JSON string produced by to_json.
pub fn from_json(json_string: String) -> Result(ORSet(String), json.DecodeError) {
  let tag_decoder = {
    use r <- decode.field("r", decode.string)
    use c <- decode.field("c", decode.int)
    decode.success(Tag(replica_id: r, counter: c))
  }
  let tag_set_decoder = decode.map(decode.list(tag_decoder), set.from_list)
  let decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field(
        "entries",
        decode.dict(decode.string, tag_set_decoder),
      )
      decode.success(ORSet(
        replica_id: replica_id,
        counter: counter,
        entries: entries,
      ))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}

/// Create a new empty OR-Set for the given replica
pub fn new(replica_id: String) -> ORSet(a) {
  ORSet(replica_id: replica_id, counter: 0, entries: dict.new())
}

/// Add an element to the set.
/// Creates a fresh unique tag for this add operation.
pub fn add(orset: ORSet(a), element: a) -> ORSet(a) {
  let new_counter = orset.counter + 1
  let tag = Tag(replica_id: orset.replica_id, counter: new_counter)
  let existing_tags = result.unwrap(dict.get(orset.entries, element), set.new())
  let new_tags = set.insert(existing_tags, tag)
  ORSet(
    replica_id: orset.replica_id,
    counter: new_counter,
    entries: dict.insert(orset.entries, element, new_tags),
  )
}

/// Remove an element from the set.
/// Removes all currently observed tags for the element (observed-remove).
/// Concurrent adds with new tags survive the remove.
pub fn remove(orset: ORSet(a), element: a) -> ORSet(a) {
  ORSet(
    replica_id: orset.replica_id,
    counter: orset.counter,
    entries: dict.delete(orset.entries, element),
  )
}

/// Check if the set contains the given element
pub fn contains(orset: ORSet(a), element: a) -> Bool {
  case dict.get(orset.entries, element) {
    Error(_) -> False
    Ok(tags) -> !set.is_empty(tags)
  }
}

/// Return the set of all elements currently in the OR-Set
pub fn value(orset: ORSet(a)) -> set.Set(a) {
  dict.fold(orset.entries, set.new(), fn(acc, element, tags) {
    case set.is_empty(tags) {
      True -> acc
      False -> set.insert(acc, element)
    }
  })
}

/// Merge two OR-Sets.
/// For each element, the merged tag set is the union of both sides' tags.
/// An element is present if it has at least one tag in the merged result.
/// The merged counter is the maximum of both sides.
pub fn merge(a: ORSet(el), b: ORSet(el)) -> ORSet(el) {
  let a_keys = dict.keys(a.entries)
  let b_keys = dict.keys(b.entries)
  let all_keys = list.unique(list.append(a_keys, b_keys))

  let merged_entries =
    list.fold(all_keys, dict.new(), fn(acc, element) {
      let a_tags = result.unwrap(dict.get(a.entries, element), set.new())
      let b_tags = result.unwrap(dict.get(b.entries, element), set.new())
      let combined = set.union(a_tags, b_tags)
      case set.is_empty(combined) {
        True -> acc
        False -> dict.insert(acc, element, combined)
      }
    })

  let merged_counter = case a.counter > b.counter {
    True -> a.counter
    False -> b.counter
  }

  ORSet(
    replica_id: a.replica_id,
    counter: merged_counter,
    entries: merged_entries,
  )
}
