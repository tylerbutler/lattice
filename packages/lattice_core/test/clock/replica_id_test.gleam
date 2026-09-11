import gleam/order
import lattice_core/replica_id

pub fn new_and_to_string_round_trip_test() {
  assert replica_id.new("node-a")
    |> replica_id.to_string
    == "node-a"
}

pub fn compare_less_than_test() {
  assert replica_id.compare(replica_id.new("A"), replica_id.new("B"))
    == order.Lt
}

pub fn compare_greater_than_test() {
  assert replica_id.compare(replica_id.new("B"), replica_id.new("A"))
    == order.Gt
}

pub fn compare_equal_test() {
  assert replica_id.compare(replica_id.new("A"), replica_id.new("A"))
    == order.Eq
}

pub fn compare_unicode_order_less_than_test() {
  assert replica_id.compare(
      replica_id.new("\u{e000}"),
      replica_id.new("\u{10000}"),
    )
    == order.Lt
}

pub fn compare_unicode_order_greater_than_test() {
  assert replica_id.compare(
      replica_id.new("\u{10000}"),
      replica_id.new("\u{e000}"),
    )
    == order.Gt
}

pub fn compare_unicode_order_equal_test() {
  assert replica_id.compare(
      replica_id.new("\u{e000}"),
      replica_id.new("\u{e000}"),
    )
    == order.Eq
  assert replica_id.compare(
      replica_id.new("\u{10000}"),
      replica_id.new("\u{10000}"),
    )
    == order.Eq
}

pub fn compare_unicode_order_common_prefix_test() {
  let bmp = replica_id.new("replica-\u{e000}")
  let supplementary = replica_id.new("replica-\u{10000}")

  assert replica_id.compare(bmp, supplementary) == order.Lt
  assert replica_id.compare(supplementary, bmp) == order.Gt
  assert replica_id.compare(supplementary, supplementary) == order.Eq
}

pub fn compare_unicode_order_empty_test() {
  let empty = replica_id.new("")
  let bmp = replica_id.new("\u{e000}")
  let supplementary = replica_id.new("\u{10000}")

  assert replica_id.compare(empty, empty) == order.Eq
  assert replica_id.compare(empty, bmp) == order.Lt
  assert replica_id.compare(bmp, empty) == order.Gt
  assert replica_id.compare(empty, supplementary) == order.Lt
  assert replica_id.compare(supplementary, empty) == order.Gt
}

pub fn compare_unicode_order_ascii_test() {
  let a = replica_id.new("A")
  let b = replica_id.new("B")

  assert replica_id.compare(a, b) == order.Lt
  assert replica_id.compare(b, a) == order.Gt
  assert replica_id.compare(a, a) == order.Eq
}

pub fn compare_unicode_order_prefix_test() {
  assert replica_id.compare(replica_id.new("a"), replica_id.new("aa"))
    == order.Lt
  assert replica_id.compare(replica_id.new("aa"), replica_id.new("a"))
    == order.Gt
  assert replica_id.compare(
      replica_id.new("\u{10000}"),
      replica_id.new("\u{10000}a"),
    )
    == order.Lt
  assert replica_id.compare(
      replica_id.new("\u{10000}a"),
      replica_id.new("\u{10000}"),
    )
    == order.Gt
}

pub fn compare_unicode_order_lexicographic_not_length_test() {
  assert replica_id.compare(replica_id.new("z"), replica_id.new("aa"))
    == order.Gt
  assert replica_id.compare(replica_id.new("aa"), replica_id.new("z"))
    == order.Lt
}

pub fn structural_equality_test() {
  let a = replica_id.new("X")
  let b = replica_id.new("X")
  assert a == b
}

pub fn structural_inequality_test() {
  let a = replica_id.new("X")
  let b = replica_id.new("Y")
  assert a != b
}
