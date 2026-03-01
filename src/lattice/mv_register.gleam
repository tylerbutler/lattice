import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice/version_vector.{type VersionVector}

/// A unique tag identifying a specific write operation
pub type Tag {
  Tag(replica_id: String, counter: Int)
}

/// A Multi-Value Register CRDT
/// Preserves concurrent values using causal history (version vectors)
pub type MVRegister(a) {
  MVRegister(
    replica_id: String,
    entries: dict.Dict(Tag, a),
    vclock: VersionVector,
  )
}

/// Encode a MVRegister(String) as a self-describing JSON value.
/// Entries (Dict(Tag, String)) are encoded as an array of tag+value objects
/// because Tag is a custom type that cannot serve as a JSON dict key.
/// Format: {"type": "mv_register", "v": 1, "state": {"replica_id": "...", "entries": [...], "vclock": {...}}}
pub fn to_json(register: MVRegister(String)) -> json.Json {
  let MVRegister(replica_id, entries, vclock) = register
  let entries_json =
    json.array(dict.to_list(entries), fn(pair) {
      let #(Tag(rid, counter), value) = pair
      json.object([
        #(
          "tag",
          json.object([
            #("r", json.string(rid)),
            #("c", json.int(counter)),
          ]),
        ),
        #("value", json.string(value)),
      ])
    })
  let version_vector.VersionVector(vclock_dict) = vclock
  json.object([
    #("type", json.string("mv_register")),
    #("v", json.int(1)),
    #(
      "state",
      json.object([
        #("replica_id", json.string(replica_id)),
        #("entries", entries_json),
        #("vclock", json.dict(vclock_dict, fn(k) { k }, json.int)),
      ]),
    ),
  ])
}

/// Decode a MVRegister(String) from a JSON string produced by to_json.
pub fn from_json(
  json_string: String,
) -> Result(MVRegister(String), json.DecodeError) {
  let entry_decoder = {
    use tag <- decode.field("tag", {
      use r <- decode.field("r", decode.string)
      use c <- decode.field("c", decode.int)
      decode.success(Tag(replica_id: r, counter: c))
    })
    use value <- decode.field("value", decode.string)
    decode.success(#(tag, value))
  }
  let decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      use vclock_dict <- decode.field(
        "vclock",
        decode.dict(decode.string, decode.int),
      )
      let entries = dict.from_list(entries_list)
      let vclock = version_vector.VersionVector(dict: vclock_dict)
      decode.success(MVRegister(
        replica_id: replica_id,
        entries: entries,
        vclock: vclock,
      ))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}

/// Create a new empty MV-Register for the given replica
pub fn new(replica_id: String) -> MVRegister(a) {
  MVRegister(
    replica_id: replica_id,
    entries: dict.new(),
    vclock: version_vector.new(),
  )
}

/// Write a new value to the register.
/// Increments this replica's clock, creates a fresh tag, clears all
/// prior entries (this write causally supersedes everything in our vclock),
/// and inserts the new tag -> value entry.
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
/// Multiple values indicate concurrent writes from different replicas.
pub fn value(register: MVRegister(a)) -> List(a) {
  dict.values(register.entries)
}

/// Merge two MV-Registers.
/// An entry survives if it is not dominated by the other register's vclock,
/// or if both registers share the same entry (handles self-merge idempotency):
///   - Entry Tag(rid, counter) from a survives if b.vclock[rid] < counter
///     OR b.entries also contains that tag
///   - Entry Tag(rid, counter) from b survives if a.vclock[rid] < counter
///     OR a.entries also contains that tag
/// The merged vclock is the pairwise maximum of both vclocks.
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
  let merged_entries =
    list.fold(dict.to_list(surviving_from_b), surviving_from_a, fn(acc, entry) {
      let #(tag, val) = entry
      dict.insert(acc, tag, val)
    })

  MVRegister(
    replica_id: a.replica_id,
    entries: merged_entries,
    vclock: version_vector.merge(a.vclock, b.vclock),
  )
}
