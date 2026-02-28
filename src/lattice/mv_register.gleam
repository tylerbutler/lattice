import gleam/dict
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
  let new_vclock = version_vector.increment(register.vclock, register.replica_id)
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
    list.fold(
      dict.to_list(surviving_from_b),
      surviving_from_a,
      fn(acc, entry) {
        let #(tag, val) = entry
        dict.insert(acc, tag, val)
      },
    )

  MVRegister(
    replica_id: a.replica_id,
    entries: merged_entries,
    vclock: version_vector.merge(a.vclock, b.vclock),
  )
}
