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
