import gleam/int
import gleam/list
import lattice_core/replica_id
import lattice_registers/lww_register

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_creates_register_with_value_test() {
  assert lww_register.new("hello", 1, rid("test-replica"))
    |> lww_register.value
    == "hello"
}

pub fn value_labels_work_for_construction_and_updates_test() {
  let register =
    lww_register.new(value: "initial", timestamp: 1, replica_id: rid("writer"))
  let register =
    lww_register.set(
      register: register,
      value: "updated",
      timestamp: 2,
      replica_id: rid("writer"),
    )
  let #(updated, delta) =
    lww_register.set_with_delta(
      register: register,
      value: "final",
      timestamp: 3,
      replica_id: rid("writer"),
    )

  assert lww_register.value(updated) == "final"
  assert lww_register.timestamp(updated) == 3
  assert lww_register.merge(register, delta) == updated
}

pub fn value_returns_current_value_test() {
  assert lww_register.new("world", 42, rid("test-replica"))
    |> lww_register.value
    == "world"
}

pub fn set_updates_value_when_timestamp_is_higher_test() {
  assert lww_register.new("hello", 1, rid("test-replica"))
    |> lww_register.set("world", 2, rid("test-replica"))
    |> lww_register.value
    == "world"
}

pub fn set_keeps_value_when_timestamp_is_lower_test() {
  assert lww_register.new("hello", 1, rid("test-replica"))
    |> lww_register.set("world", 0, rid("other-replica"))
    |> lww_register.value
    == "hello"
}

pub fn set_keeps_value_when_timestamp_is_equal_test() {
  assert lww_register.new("hello", 5, rid("test-replica"))
    |> lww_register.set("world", 5, rid("other-replica"))
    |> lww_register.value
    == "hello"
}

pub fn merge_returns_register_with_higher_timestamp_test() {
  let reg_ts1 = lww_register.new("first", 1, rid("A"))
  let reg_ts2 = lww_register.new("second", 2, rid("B"))

  assert lww_register.merge(reg_ts1, reg_ts2)
    |> lww_register.value
    == "second"
}

pub fn merge_is_commutative_on_higher_timestamp_test() {
  let reg_ts1 = lww_register.new("first", 1, rid("A"))
  let reg_ts2 = lww_register.new("second", 2, rid("B"))

  assert lww_register.merge(reg_ts2, reg_ts1)
    |> lww_register.value
    == "second"
}

pub fn merge_tiebreak_uses_replica_id_test() {
  let reg_a = lww_register.new("aaa", 5, rid("A"))
  let reg_b = lww_register.new("bbb", 5, rid("B"))

  // B > A lexicographically, so reg_b wins
  assert lww_register.merge(reg_a, reg_b)
    |> lww_register.value
    == "bbb"
}

pub fn merge_tiebreak_is_commutative_test() {
  let reg_a = lww_register.new("aaa", 5, rid("A"))
  let reg_b = lww_register.new("bbb", 5, rid("B"))

  let merged_ab = lww_register.merge(reg_a, reg_b) |> lww_register.value
  let merged_ba = lww_register.merge(reg_b, reg_a) |> lww_register.value

  assert merged_ab == merged_ba
}

pub fn merge_unicode_order_equal_timestamp_test() {
  let bmp = lww_register.new("bmp value", 5, rid("\u{e000}"))
  let supplementary =
    lww_register.new("supplementary value", 5, rid("\u{10000}"))

  list.each(
    [
      lww_register.merge(bmp, supplementary),
      lww_register.merge(supplementary, bmp),
    ],
    fn(merged) {
      assert lww_register.value(merged) == "supplementary value"
      assert lww_register.replica_id(merged) == rid("\u{10000}")
      assert lww_register.timestamp(merged) == 5
    },
  )
}

pub fn merge_unicode_order_greater_timestamp_takes_precedence_test() {
  let bmp = lww_register.new("newer bmp value", 6, rid("\u{e000}"))
  let supplementary =
    lww_register.new("older supplementary value", 5, rid("\u{10000}"))

  list.each(
    [
      lww_register.merge(bmp, supplementary),
      lww_register.merge(supplementary, bmp),
    ],
    fn(merged) {
      assert lww_register.value(merged) == "newer bmp value"
      assert lww_register.replica_id(merged) == rid("\u{e000}")
      assert lww_register.timestamp(merged) == 6
    },
  )
}

pub fn merge_commutativity_on_different_timestamps_test() {
  let reg_a = lww_register.new("alpha", 10, rid("A"))
  let reg_b = lww_register.new("beta", 20, rid("B"))

  let merged_ab = lww_register.merge(reg_a, reg_b) |> lww_register.value
  let merged_ba = lww_register.merge(reg_b, reg_a) |> lww_register.value

  assert merged_ab == merged_ba
}

// Metadata accessors

pub fn timestamp_returns_constructed_timestamp_test() {
  assert lww_register.new("hello", 42, rid("test-replica"))
    |> lww_register.timestamp
    == 42
}

pub fn timestamp_advances_after_accepted_set_test() {
  assert lww_register.new("hello", 1, rid("test-replica"))
    |> lww_register.set("world", 7, rid("test-replica"))
    |> lww_register.timestamp
    == 7
}

pub fn timestamp_unchanged_after_rejected_equal_set_test() {
  assert lww_register.new("hello", 5, rid("test-replica"))
    |> lww_register.set("world", 5, rid("other-replica"))
    |> lww_register.timestamp
    == 5
}

pub fn timestamp_unchanged_after_rejected_lower_set_test() {
  assert lww_register.new("hello", 5, rid("test-replica"))
    |> lww_register.set("world", 2, rid("other-replica"))
    |> lww_register.timestamp
    == 5
}

pub fn timestamp_after_merge_is_the_winners_test() {
  let reg_a = lww_register.new("alpha", 10, rid("A"))
  let reg_b = lww_register.new("beta", 20, rid("B"))

  assert lww_register.merge(reg_a, reg_b)
    |> lww_register.timestamp
    == 20
}

pub fn replica_id_returns_constructed_replica_test() {
  assert lww_register.new("hello", 1, rid("test-replica"))
    |> lww_register.replica_id
    == rid("test-replica")
}

pub fn set_records_the_supplied_writer_test() {
  assert lww_register.new("hello", 1, rid("owner"))
    |> lww_register.set("world", 2, rid("local-writer"))
    |> lww_register.replica_id
    == rid("local-writer")
}

pub fn replica_id_after_tiebreak_merge_is_the_winners_test() {
  let reg_a = lww_register.new("aaa", 5, rid("A"))
  let reg_b = lww_register.new("bbb", 5, rid("B"))

  // B > A lexicographically, so the merged register carries B's id
  assert lww_register.merge(reg_a, reg_b)
    |> lww_register.replica_id
    == rid("B")
}

/// The bug from issue #154: a client that loads a snapshot can read the held
/// timestamp back and seed a logical clock from it, so a write stamped with a
/// wall clock that has not moved past the snapshot is no longer dropped.
pub fn timestamp_seeds_a_logical_clock_test() {
  let snapshot = lww_register.new("painted", 100, rid("peer"))

  // A fresh client whose wall clock reads 100 — the same millisecond.
  let wall_clock = 100
  let seeded = int.max(wall_clock, lww_register.timestamp(snapshot) + 1)

  let erased = lww_register.set(snapshot, "erased", seeded, rid("local"))

  assert lww_register.value(erased) == "erased"
  assert lww_register.timestamp(erased) == 101
}

pub fn set_records_only_an_accepted_new_author_test() {
  let historical = lww_register.new("original", 10, rid("A"))
  let updated =
    lww_register.set(
      register: historical,
      value: "new",
      timestamp: 11,
      replica_id: rid("B"),
    )

  assert lww_register.replica_id(historical) == rid("A")
  assert lww_register.replica_id(updated) == rid("B")
  assert lww_register.timestamp(updated) == 11
  assert lww_register.value(updated) == "new"
  assert lww_register.set(historical, "ignored", 10, rid("Z")) == historical
  assert lww_register.set(historical, "ignored", 9, rid("Z")) == historical
  assert lww_register.set(updated, "next", 12, rid("C"))
    |> lww_register.replica_id()
    == rid("C")
}

pub fn set_delta_preserves_author_and_equal_timestamp_order_test() {
  let historical = lww_register.new("original", 10, rid("Z"))
  let #(a, delta_a) = lww_register.set_with_delta(historical, "a", 11, rid("A"))
  let #(b, delta_b) =
    lww_register.set_with_delta(
      register: historical,
      value: "b",
      timestamp: 11,
      replica_id: rid("B"),
    )
  assert lww_register.merge(historical, delta_a) == a
  assert lww_register.merge(historical, delta_b) == b
  assert lww_register.merge(a, b) == b
  assert lww_register.merge(b, a) == b
  assert lww_register.set_with_delta(a, "ignored", 11, rid("Z")) == #(a, a)
  assert lww_register.set_with_delta(a, "ignored", 0, rid("Z")) == #(a, a)
}

pub fn merge_then_write_uses_each_local_writer_and_converges_test() {
  let shared =
    lww_register.merge(
      lww_register.new("initial A", 10, rid("A")),
      lww_register.new("initial B", 10, rid("B")),
    )
  let a = lww_register.set(shared, "A wrote", 11, rid("A"))
  let b = lww_register.set(shared, "B wrote", 11, rid("B"))

  assert lww_register.replica_id(a) == rid("A")
  assert lww_register.replica_id(b) == rid("B")
  assert lww_register.merge(a, b) == b
  assert lww_register.merge(b, a) == b
}

pub fn repeated_merge_then_write_cycles_keep_local_writer_test() {
  let shared =
    lww_register.merge(
      lww_register.new("A0", 10, rid("A")),
      lww_register.new("B0", 10, rid("B")),
    )
  let first =
    lww_register.merge(
      lww_register.set(shared, "A1", 11, rid("A")),
      lww_register.set(shared, "B1", 11, rid("B")),
    )
  let a = lww_register.set(first, "A2", 12, rid("A"))
  let b = lww_register.set(first, "B2", 12, rid("B"))

  assert lww_register.replica_id(a) == rid("A")
  assert lww_register.replica_id(b) == rid("B")
  assert lww_register.merge(a, b) == lww_register.merge(b, a)
}
