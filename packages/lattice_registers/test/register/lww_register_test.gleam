import gleam/int
import lattice_core/replica_id
import lattice_registers/lww_register
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_creates_register_with_value_test() {
  lww_register.new("hello", 1, rid("test-replica"))
  |> lww_register.value
  |> expect.to_equal("hello")
}

pub fn value_returns_current_value_test() {
  lww_register.new("world", 42, rid("test-replica"))
  |> lww_register.value
  |> expect.to_equal("world")
}

pub fn set_updates_value_when_timestamp_is_higher_test() {
  lww_register.new("hello", 1, rid("test-replica"))
  |> lww_register.set("world", 2)
  |> lww_register.value
  |> expect.to_equal("world")
}

pub fn set_keeps_value_when_timestamp_is_lower_test() {
  lww_register.new("hello", 1, rid("test-replica"))
  |> lww_register.set("world", 0)
  |> lww_register.value
  |> expect.to_equal("hello")
}

pub fn set_keeps_value_when_timestamp_is_equal_test() {
  lww_register.new("hello", 5, rid("test-replica"))
  |> lww_register.set("world", 5)
  |> lww_register.value
  |> expect.to_equal("hello")
}

pub fn merge_returns_register_with_higher_timestamp_test() {
  let reg_ts1 = lww_register.new("first", 1, rid("A"))
  let reg_ts2 = lww_register.new("second", 2, rid("B"))

  lww_register.merge(reg_ts1, reg_ts2)
  |> lww_register.value
  |> expect.to_equal("second")
}

pub fn merge_is_commutative_on_higher_timestamp_test() {
  let reg_ts1 = lww_register.new("first", 1, rid("A"))
  let reg_ts2 = lww_register.new("second", 2, rid("B"))

  lww_register.merge(reg_ts2, reg_ts1)
  |> lww_register.value
  |> expect.to_equal("second")
}

pub fn merge_tiebreak_uses_replica_id_test() {
  let reg_a = lww_register.new("aaa", 5, rid("A"))
  let reg_b = lww_register.new("bbb", 5, rid("B"))

  // B > A lexicographically, so reg_b wins
  lww_register.merge(reg_a, reg_b)
  |> lww_register.value
  |> expect.to_equal("bbb")
}

pub fn merge_tiebreak_is_commutative_test() {
  let reg_a = lww_register.new("aaa", 5, rid("A"))
  let reg_b = lww_register.new("bbb", 5, rid("B"))

  let merged_ab = lww_register.merge(reg_a, reg_b) |> lww_register.value
  let merged_ba = lww_register.merge(reg_b, reg_a) |> lww_register.value

  expect.to_equal(merged_ab, merged_ba)
}

pub fn merge_commutativity_on_different_timestamps_test() {
  let reg_a = lww_register.new("alpha", 10, rid("A"))
  let reg_b = lww_register.new("beta", 20, rid("B"))

  let merged_ab = lww_register.merge(reg_a, reg_b) |> lww_register.value
  let merged_ba = lww_register.merge(reg_b, reg_a) |> lww_register.value

  expect.to_equal(merged_ab, merged_ba)
}

// Metadata accessors

pub fn timestamp_returns_constructed_timestamp_test() {
  lww_register.new("hello", 42, rid("test-replica"))
  |> lww_register.timestamp
  |> expect.to_equal(42)
}

pub fn timestamp_advances_after_accepted_set_test() {
  lww_register.new("hello", 1, rid("test-replica"))
  |> lww_register.set("world", 7)
  |> lww_register.timestamp
  |> expect.to_equal(7)
}

pub fn timestamp_unchanged_after_rejected_equal_set_test() {
  lww_register.new("hello", 5, rid("test-replica"))
  |> lww_register.set("world", 5)
  |> lww_register.timestamp
  |> expect.to_equal(5)
}

pub fn timestamp_unchanged_after_rejected_lower_set_test() {
  lww_register.new("hello", 5, rid("test-replica"))
  |> lww_register.set("world", 2)
  |> lww_register.timestamp
  |> expect.to_equal(5)
}

pub fn timestamp_after_merge_is_the_winners_test() {
  let reg_a = lww_register.new("alpha", 10, rid("A"))
  let reg_b = lww_register.new("beta", 20, rid("B"))

  lww_register.merge(reg_a, reg_b)
  |> lww_register.timestamp
  |> expect.to_equal(20)
}

pub fn replica_id_returns_constructed_replica_test() {
  lww_register.new("hello", 1, rid("test-replica"))
  |> lww_register.replica_id
  |> expect.to_equal(rid("test-replica"))
}

pub fn replica_id_survives_set_test() {
  lww_register.new("hello", 1, rid("owner"))
  |> lww_register.set("world", 2)
  |> lww_register.replica_id
  |> expect.to_equal(rid("owner"))
}

pub fn replica_id_after_tiebreak_merge_is_the_winners_test() {
  let reg_a = lww_register.new("aaa", 5, rid("A"))
  let reg_b = lww_register.new("bbb", 5, rid("B"))

  // B > A lexicographically, so the merged register carries B's id
  lww_register.merge(reg_a, reg_b)
  |> lww_register.replica_id
  |> expect.to_equal(rid("B"))
}

/// The bug from issue #154: a client that loads a snapshot can read the held
/// timestamp back and seed a logical clock from it, so a write stamped with a
/// wall clock that has not moved past the snapshot is no longer dropped.
pub fn timestamp_seeds_a_logical_clock_test() {
  let snapshot = lww_register.new("painted", 100, rid("peer"))

  // A fresh client whose wall clock reads 100 — the same millisecond.
  let wall_clock = 100
  let seeded = int.max(wall_clock, lww_register.timestamp(snapshot) + 1)

  let erased = lww_register.set(snapshot, "erased", seeded)

  expect.to_equal(lww_register.value(erased), "erased")
  expect.to_equal(lww_register.timestamp(erased), 101)
}
