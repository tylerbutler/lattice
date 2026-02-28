import lattice/lww_register
import startest/expect

pub fn new_creates_register_with_value_test() {
  lww_register.new("hello", 1)
  |> lww_register.value
  |> expect.to_equal("hello")
}

pub fn value_returns_current_value_test() {
  lww_register.new("world", 42)
  |> lww_register.value
  |> expect.to_equal("world")
}

pub fn set_updates_value_when_timestamp_is_higher_test() {
  lww_register.new("hello", 1)
  |> lww_register.set("world", 2)
  |> lww_register.value
  |> expect.to_equal("world")
}

pub fn set_keeps_value_when_timestamp_is_lower_test() {
  lww_register.new("hello", 1)
  |> lww_register.set("world", 0)
  |> lww_register.value
  |> expect.to_equal("hello")
}

pub fn set_keeps_value_when_timestamp_is_equal_test() {
  lww_register.new("hello", 5)
  |> lww_register.set("world", 5)
  |> lww_register.value
  |> expect.to_equal("hello")
}

pub fn merge_returns_register_with_higher_timestamp_test() {
  let reg_ts1 = lww_register.new("first", 1)
  let reg_ts2 = lww_register.new("second", 2)

  lww_register.merge(reg_ts1, reg_ts2)
  |> lww_register.value
  |> expect.to_equal("second")
}

pub fn merge_is_commutative_on_higher_timestamp_test() {
  let reg_ts1 = lww_register.new("first", 1)
  let reg_ts2 = lww_register.new("second", 2)

  lww_register.merge(reg_ts2, reg_ts1)
  |> lww_register.value
  |> expect.to_equal("second")
}

pub fn merge_tiebreak_favors_second_argument_test() {
  let reg_a = lww_register.new("aaa", 5)
  let reg_b = lww_register.new("bbb", 5)

  lww_register.merge(reg_a, reg_b)
  |> lww_register.value
  |> expect.to_equal("bbb")
}

pub fn merge_commutativity_on_value_test() {
  let reg_a = lww_register.new("alpha", 10)
  let reg_b = lww_register.new("beta", 20)

  let merged_ab = lww_register.merge(reg_a, reg_b) |> lww_register.value
  let merged_ba = lww_register.merge(reg_b, reg_a) |> lww_register.value

  expect.to_equal(merged_ab, merged_ba)
}
