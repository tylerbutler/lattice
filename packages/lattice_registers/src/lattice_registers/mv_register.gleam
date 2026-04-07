//// A multi-value register (MV-Register) CRDT.
////
//// Preserves all concurrently written values using causal history tracked by
//// version vectors. When one write causally supersedes another, only the newer
//// value survives. When writes are concurrent, all values are retained — the
//// application decides how to resolve the conflict.
////
//// ## Example
////
//// ```gleam
//// import lattice_core/replica_id
//// import lattice_registers/mv_register
////
//// let a = mv_register.new(replica_id.new("node-a")) |> mv_register.set("hello")
//// let b = mv_register.new(replica_id.new("node-b")) |> mv_register.set("world")
//// let merged = mv_register.merge(a, b)
//// mv_register.value(merged)  // -> ["hello", "world"] (concurrent writes)
//// ```

import gleam/dict
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}

/// An opaque identifier for a specific write operation.
///
/// Tags are generated internally by `set` and are not meant to be constructed
/// by application code. A tag pairs a replica ID with a counter value,
/// uniquely identifying one write event at one replica.
pub opaque type Tag {
  Tag(replica_id: ReplicaId, counter: Int)
}

/// A multi-value register that preserves concurrent writes.
///
/// `replica_id` identifies this node. `entries` maps write tags to values;
/// multiple entries indicate concurrent writes. `vclock` tracks the causal
/// history observed by this replica.
///
/// This type is opaque: use `new`, `set`, `value`, and `merge` to interact
/// with it. Do not pattern-match on the internal fields directly.
pub opaque type MVRegister(a) {
  MVRegister(
    replica_id: ReplicaId,
    entries: dict.Dict(Tag, a),
    vclock: VersionVector,
  )
}

/// Create a new empty MV-Register for the given replica.
///
/// Returns a register with no entries and an empty version vector.
/// `replica_id` identifies this node and is used when writing new values.
pub fn new(replica_id: ReplicaId) -> MVRegister(a) {
  MVRegister(
    replica_id: replica_id,
    entries: dict.new(),
    vclock: version_vector.new(),
  )
}

/// Write a new value to the register.
///
/// Increments this replica's logical clock, creates a fresh tag for the write,
/// clears all prior entries (this write causally supersedes everything in the
/// current vclock), and inserts the new tag-value pair. After a `set`, calling
/// `value` returns a single-element list containing `val`.
pub fn set(register: MVRegister(a), val: a) -> MVRegister(a) {
  let new_vclock =
    version_vector.increment(register.vclock, register.replica_id)
  let new_counter = version_vector.get(new_vclock, register.replica_id)
  let tag = Tag(replica_id: register.replica_id, counter: new_counter)

  // Clear all prior entries — this write supersedes everything we've seen
  MVRegister(
    replica_id: register.replica_id,
    entries: dict.insert(dict.new(), tag, val),
    vclock: new_vclock,
  )
}

/// Return all concurrent values in the register.
///
/// Returns a list of all surviving values. An empty list means the register
/// has never been written. A single-element list is the common case after a
/// `set`. Multiple values indicate concurrent writes from different replicas
/// that have not yet been causally superseded — the application must decide
/// how to resolve them (e.g., pick one, merge, or surface the conflict).
pub fn value(register: MVRegister(a)) -> List(a) {
  dict.values(register.entries)
}

/// Merge two MV-Registers.
///
/// An entry survives the merge if it is not dominated by the other register's
/// version vector, or if both registers share the same entry (handles
/// self-merge idempotency):
///
/// - Entry `Tag(rid, counter)` from `a` survives if `b.vclock[rid] < counter`
///   OR `b.entries` also contains that tag.
/// - Entry `Tag(rid, counter)` from `b` survives if `a.vclock[rid] < counter`
///   OR `a.entries` also contains that tag.
///
/// The merged vclock is the pairwise maximum of both vclocks.
/// The result's `replica_id` is taken from `a`.
///
/// This operation is commutative, associative, and idempotent.
pub fn merge(a: MVRegister(el), b: MVRegister(el)) -> MVRegister(el) {
  // Entries from a that survive: not dominated by b's vclock, or shared with b
  let surviving_from_a =
    dict.filter(a.entries, fn(tag, _val) {
      version_vector.get(b.vclock, tag.replica_id) < tag.counter
      || dict.has_key(b.entries, tag)
    })

  // Entries from b that survive: not dominated by a's vclock, or shared with a
  let surviving_from_b =
    dict.filter(b.entries, fn(tag, _val) {
      version_vector.get(a.vclock, tag.replica_id) < tag.counter
      || dict.has_key(a.entries, tag)
    })

  // Combine surviving entries from both sides
  let merged_entries = dict.merge(surviving_from_a, surviving_from_b)

  MVRegister(
    replica_id: a.replica_id,
    entries: merged_entries,
    vclock: version_vector.merge(a.vclock, b.vclock),
  )
}

/// Encode a MVRegister(String) as a self-describing JSON value.
///
/// Entries are serialized as an array of tag+value objects because `Tag` is a
/// custom type that cannot serve as a JSON dictionary key.
/// Format: `{"type": "mv_register", "v": 1, "state": {"replica_id": "...", "entries": [...], "vclock": {...}}}`
///
/// Use `from_json` to decode the result back into a `MVRegister(String)`.
pub fn to_json(register: MVRegister(String)) -> json.Json {
  let MVRegister(rid, entries, vclock) = register
  let entries_json =
    json.array(dict.to_list(entries), fn(pair) {
      let #(Tag(tag_rid, counter), value) = pair
      json.object([
        #(
          "tag",
          json.object([
            #("r", json.string(replica_id.to_string(tag_rid))),
            #("c", json.int(counter)),
          ]),
        ),
        #("value", json.string(value)),
      ])
    })
  let vclock_dict = version_vector.to_dict(vclock)
  json.object([
    #("type", json.string("mv_register")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(replica_id.to_string(rid))),
        #("entries", entries_json),
        #("vclock", json.dict(vclock_dict, replica_id.to_string, json.int)),
      ]),
    ),
  ])
}

/// Decode a MVRegister(String) from a JSON string produced by `to_json`.
///
/// Returns `Ok(MVRegister(String))` on success, or `Error(json.DecodeError)`
/// if the input is not a valid MV-Register JSON envelope.
pub fn from_json(
  json_string: String,
) -> Result(MVRegister(String), json.DecodeError) {
  let entry_decoder = {
    use tag <- decode.field("tag", {
      use r <- decode.field("r", decode.string)
      use c <- decode.field("c", decode.int)
      decode.success(Tag(replica_id: replica_id.new(r), counter: c))
    })
    use value <- decode.field("value", decode.string)
    decode.success(#(tag, value))
  }
  let state_decoder = {
    use state <- decode.field("state", {
      use rid_str <- decode.field("replica_id", decode.string)
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      use vclock_dict <- decode.field(
        "vclock",
        decode.dict(decode.string, decode.int),
      )
      let entries = dict.from_list(entries_list)
      let vclock_rid_dict =
        dict.fold(vclock_dict, dict.new(), fn(acc, k, v) {
          dict.insert(acc, replica_id.new(k), v)
        })
      let vclock = version_vector.from_dict(vclock_rid_dict)

      let is_valid =
        list.all(entries_list, fn(pair) {
          let #(Tag(rid, c), _val) = pair
          let is_positive = c > 0
          let vclock_counter = version_vector.get(vclock, rid)
          let is_causal = c <= vclock_counter
          is_positive && is_causal
        })

      let mvr =
        MVRegister(
          replica_id: replica_id.new(rid_str),
          entries: entries,
          vclock: vclock,
        )

      case is_valid {
        True -> decode.success(mvr)
        False ->
          decode.failure(
            mvr,
            "causally consistent entries and positive counters",
          )
      }
    })
    decode.success(state)
  }
  let envelope_decoder = {
    use type_tag <- decode.field("type", decode.string)
    use version <- decode.field("v", decode.int)
    decode.success(#(type_tag, version))
  }
  case json.parse(from: json_string, using: envelope_decoder) {
    Error(e) -> Error(e)
    Ok(#(type_tag, version)) ->
      case type_tag == "mv_register" && version == 1 {
        True -> json.parse(from: json_string, using: state_decoder)
        False ->
          Error(
            json.UnableToDecode([
              decode.DecodeError(
                expected: "type=mv_register and v=1",
                found: type_tag <> " v=" <> int.to_string(version),
                path: [],
              ),
            ]),
          )
      }
  }
}
