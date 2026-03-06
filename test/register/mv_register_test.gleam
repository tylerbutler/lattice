import gleam/list
import gleam/order
import gleam/string
import lattice/mv_register
import startest/expect

pub fn new_creates_empty_register_test() {
  mv_register.new("A")
  |> mv_register.value
  |> expect.to_equal([])
}

pub fn set_then_value_returns_single_value_test() {
  mv_register.new("A")
  |> mv_register.set("hello")
  |> mv_register.value
  |> expect.to_equal(["hello"])
}

pub fn set_twice_supersedes_previous_value_test() {
  mv_register.new("A")
  |> mv_register.set("hello")
  |> mv_register.set("world")
  |> mv_register.value
  |> expect.to_equal(["world"])
}

pub fn concurrent_writes_preserved_after_merge_test() {
  let reg_a = mv_register.new("A") |> mv_register.set("alice_val")
  let reg_b = mv_register.new("B") |> mv_register.set("bob_val")

  let merged = mv_register.merge(reg_a, reg_b)
  let vals = mv_register.value(merged)

  vals
  |> list.length
  |> expect.to_equal(2)

  vals
  |> list.contains("alice_val")
  |> expect.to_be_true

  vals
  |> list.contains("bob_val")
  |> expect.to_be_true
}

pub fn sequential_write_dominates_earlier_value_test() {
  // reg_a writes "v1"
  let reg_a = mv_register.new("A") |> mv_register.set("v1")
  // reg_b merges in reg_a's state, then writes "v2"
  // After merge, reg_b knows about A's clock, so B's write supersedes A's
  let reg_b =
    mv_register.merge(mv_register.new("B"), reg_a) |> mv_register.set("v2")

  // When we merge reg_a with reg_b, B's write dominates because
  // B's vclock has seen A's write
  let merged = mv_register.merge(reg_a, reg_b)
  let vals = mv_register.value(merged)

  vals
  |> expect.to_equal(["v2"])
}

pub fn merge_commutativity_test() {
  let reg_a = mv_register.new("A") |> mv_register.set("alice")
  let reg_b = mv_register.new("B") |> mv_register.set("bob")

  let string_compare = fn(a: String, b: String) -> order.Order {
    string.compare(a, b)
  }

  let vals_ab =
    mv_register.merge(reg_a, reg_b)
    |> mv_register.value
    |> list.sort(by: string_compare)

  let vals_ba =
    mv_register.merge(reg_b, reg_a)
    |> mv_register.value
    |> list.sort(by: string_compare)

  expect.to_equal(vals_ab, vals_ba)
}
