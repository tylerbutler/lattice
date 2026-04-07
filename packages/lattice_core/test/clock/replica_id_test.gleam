import gleam/order
import lattice_core/replica_id
import startest/expect

pub fn new_and_to_string_round_trip_test() {
  replica_id.new("node-a")
  |> replica_id.to_string
  |> expect.to_equal("node-a")
}

pub fn compare_less_than_test() {
  replica_id.compare(replica_id.new("A"), replica_id.new("B"))
  |> expect.to_equal(order.Lt)
}

pub fn compare_greater_than_test() {
  replica_id.compare(replica_id.new("B"), replica_id.new("A"))
  |> expect.to_equal(order.Gt)
}

pub fn compare_equal_test() {
  replica_id.compare(replica_id.new("A"), replica_id.new("A"))
  |> expect.to_equal(order.Eq)
}

pub fn structural_equality_test() {
  let a = replica_id.new("X")
  let b = replica_id.new("X")
  expect.to_equal(a, b)
}

pub fn structural_inequality_test() {
  let a = replica_id.new("X")
  let b = replica_id.new("Y")
  expect.to_not_equal(a, b)
}
