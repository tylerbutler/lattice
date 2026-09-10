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

pub fn compare_unicode_order_less_than_test() {
  replica_id.compare(replica_id.new("\u{e000}"), replica_id.new("\u{10000}"))
  |> expect.to_equal(order.Lt)
}

pub fn compare_unicode_order_greater_than_test() {
  replica_id.compare(replica_id.new("\u{10000}"), replica_id.new("\u{e000}"))
  |> expect.to_equal(order.Gt)
}

pub fn compare_unicode_order_equal_test() {
  replica_id.compare(replica_id.new("\u{e000}"), replica_id.new("\u{e000}"))
  |> expect.to_equal(order.Eq)
  replica_id.compare(replica_id.new("\u{10000}"), replica_id.new("\u{10000}"))
  |> expect.to_equal(order.Eq)
}

pub fn compare_unicode_order_common_prefix_test() {
  let bmp = replica_id.new("replica-\u{e000}")
  let supplementary = replica_id.new("replica-\u{10000}")

  replica_id.compare(bmp, supplementary) |> expect.to_equal(order.Lt)
  replica_id.compare(supplementary, bmp) |> expect.to_equal(order.Gt)
  replica_id.compare(supplementary, supplementary)
  |> expect.to_equal(order.Eq)
}

pub fn compare_unicode_order_empty_test() {
  let empty = replica_id.new("")
  let bmp = replica_id.new("\u{e000}")
  let supplementary = replica_id.new("\u{10000}")

  replica_id.compare(empty, empty) |> expect.to_equal(order.Eq)
  replica_id.compare(empty, bmp) |> expect.to_equal(order.Lt)
  replica_id.compare(bmp, empty) |> expect.to_equal(order.Gt)
  replica_id.compare(empty, supplementary) |> expect.to_equal(order.Lt)
  replica_id.compare(supplementary, empty) |> expect.to_equal(order.Gt)
}

pub fn compare_unicode_order_ascii_test() {
  let a = replica_id.new("A")
  let b = replica_id.new("B")

  replica_id.compare(a, b) |> expect.to_equal(order.Lt)
  replica_id.compare(b, a) |> expect.to_equal(order.Gt)
  replica_id.compare(a, a) |> expect.to_equal(order.Eq)
}

pub fn compare_unicode_order_prefix_test() {
  replica_id.compare(replica_id.new("a"), replica_id.new("aa"))
  |> expect.to_equal(order.Lt)
  replica_id.compare(replica_id.new("aa"), replica_id.new("a"))
  |> expect.to_equal(order.Gt)
  replica_id.compare(replica_id.new("\u{10000}"), replica_id.new("\u{10000}a"))
  |> expect.to_equal(order.Lt)
  replica_id.compare(replica_id.new("\u{10000}a"), replica_id.new("\u{10000}"))
  |> expect.to_equal(order.Gt)
}

pub fn compare_unicode_order_lexicographic_not_length_test() {
  replica_id.compare(replica_id.new("z"), replica_id.new("aa"))
  |> expect.to_equal(order.Gt)
  replica_id.compare(replica_id.new("aa"), replica_id.new("z"))
  |> expect.to_equal(order.Lt)
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
