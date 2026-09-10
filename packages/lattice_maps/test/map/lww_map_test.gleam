import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register
import lattice_text/text
import startest/expect

fn new(writer) {
  lww_map.new(replica_id.new(writer), crdt.LwwRegisterSpec(""))
}

fn child(value) {
  crdt.CrdtLwwRegister(lww_register.new(
    value,
    1,
    replica_id.new("historical-author"),
  ))
}

pub fn empty_lww_map_queries_test() {
  let map = new("A")
  lww_map.keys(map) |> expect.to_equal([])
  lww_map.values(map) |> expect.to_equal([])
  lww_map.get(map, "missing") |> expect.to_equal(Error(Nil))
  lww_map.tombstone_count(map) |> expect.to_equal(0)
  lww_map.pruned_timestamp(map) |> expect.to_equal(0)
}

pub fn modern_lww_strict_timestamp_and_schema_errors_test() {
  let assert Ok(map) = lww_map.set(new("A"), "key", child("value"), 10)
  list.each([0, 5, 10], fn(timestamp) {
    lww_map.set(map, "key", child("other"), timestamp)
    |> expect.to_equal(Error(crdt.TimestampNotAdvanced("key", timestamp, 10)))
    lww_map.remove(map, "key", timestamp)
    |> expect.to_equal(Error(crdt.TimestampNotAdvanced("key", timestamp, 10)))
  })
  lww_map.set(
    map,
    "other",
    crdt.default_crdt(crdt.TextSpec, replica_id.new("A")),
    11,
  )
  |> expect.to_equal(
    Error(crdt.AtKey("other", crdt.TypeMismatch("lww_register", "text"))),
  )
  let assert Ok(map) = lww_map.set(map, "key", child("later"), 11)
  lww_map.get(map, "key") |> expect.to_equal(Ok(child("later")))
}

pub fn modern_lww_writer_ties_are_atomic_and_preserve_authors_test() {
  let assert Ok(a) = lww_map.set(new("A"), "key", child("zzz"), 10)
  let assert Ok(b) = lww_map.set(new("B"), "key", child("aaa"), 10)
  let assert Ok(ab) = lww_map.merge_as(a, b, replica_id.new("C"))
  let assert Ok(ba) = lww_map.merge_as(b, a, replica_id.new("C"))
  ab |> expect.to_equal(ba)
  lww_map.get(ab, "key") |> expect.to_equal(Ok(child("aaa")))
}

pub fn modern_lww_conflicting_same_write_is_error_test() {
  let assert Ok(a) = lww_map.set(new("A"), "key", child("one"), 10)
  let assert Ok(b) = lww_map.set(new("A"), "key", child("two"), 10)
  lww_map.merge(a, b)
  |> expect.to_equal(Error(crdt.ConflictingWrite("key", 10)))
  lww_map.merge(b, a)
  |> expect.to_equal(Error(crdt.ConflictingWrite("key", 10)))
  lww_map.merge(a, a) |> expect.to_equal(Ok(a))
}

pub fn modern_lww_tombstone_precedes_writer_test() {
  let assert Ok(a) = lww_map.set(new("Z"), "key", child("alive"), 10)
  let assert Ok(b) = lww_map.remove(new("A"), "key", 10)
  let assert Ok(ab) = lww_map.merge(a, b)
  let assert Ok(ba) = lww_map.merge(b, a)
  lww_map.get(ab, "key") |> expect.to_equal(Error(Nil))
  lww_map.get(ba, "key") |> expect.to_equal(Error(Nil))
  lww_map.tombstone_count(ab) |> expect.to_equal(1)
}

pub fn modern_lww_pruning_prevents_zombies_and_rejects_stale_new_keys_test() {
  let assert Ok(old) = lww_map.set(new("B"), "key", child("old"), 5)
  let assert Ok(removed) = lww_map.remove(new("A"), "key", 10)
  let pruned = lww_map.prune(removed, 10) |> lww_map.prune(2)
  lww_map.pruned_timestamp(pruned) |> expect.to_equal(10)
  lww_map.tombstone_count(pruned) |> expect.to_equal(0)
  lww_map.set(pruned, "new", child("stale"), 9)
  |> expect.to_equal(Error(crdt.TimestampNotAdvanced("new", 9, 10)))
  let assert Ok(merged) = lww_map.merge(pruned, old)
  let assert Ok(reverse) = lww_map.merge(old, pruned)
  lww_map.keys(merged) |> expect.to_equal([])
  lww_map.keys(reverse) |> expect.to_equal([])
  let assert Ok(fresh) = lww_map.set(pruned, "key", child("fresh"), 11)
  lww_map.get(fresh, "key") |> expect.to_equal(Ok(child("fresh")))
}

pub fn modern_lww_prune_preserves_active_children_test() {
  let assert Ok(map) = lww_map.set(new("A"), "active", child("value"), 1)
  let assert Ok(map) = lww_map.remove(map, "removed", 2)
  let map = lww_map.prune(map, 3)
  lww_map.values(map) |> expect.to_equal([child("value")])
  lww_map.keys(map) |> expect.to_equal(["active"])
}

pub fn lww_assignment_context_prevents_fresh_text_id_reuse_test() {
  let map = lww_map.new(replica_id.new("A"), crdt.TextSpec)
  let replace = fn(_, context: crdt.EditContext) {
    let assert Ok(value) = text.append(text.new(context.replica_id), "fresh")
    Ok(crdt.CrdtText(value))
  }
  let assert Ok(first) = lww_map.update(map, "doc", 1, replace)
  let assert Ok(second) = lww_map.update(first, "doc", 2, replace)
  let assert Ok(crdt.CrdtText(a)) = lww_map.get(first, "doc")
  let assert Ok(crdt.CrdtText(b)) = lww_map.get(second, "doc")
  text.length(text.merge(a, b, replica_id.new("C"))) |> expect.to_equal(10)
  let assert Ok(merged) = lww_map.merge(first, second)
  let assert Ok(crdt.CrdtText(value)) = lww_map.get(merged, "doc")
  text.value(value) |> expect.to_equal("fresh")
  let before = lww_map.to_json(second) |> json.to_string
  let _ = lww_map.get(lww_map.bind(second, replica_id.new("B")), "doc")
  lww_map.to_json(second) |> json.to_string |> expect.to_equal(before)
}

pub fn lww_callback_errors_are_atomic_test() {
  lww_map.update(new("A"), "key", 1, fn(_, _) { Error("rejected") })
  |> expect.to_equal(Error(crdt.CallbackError("rejected")))
}
