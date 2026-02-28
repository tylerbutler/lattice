import gleeunit
import gleeunit/should
import lattice/g_counter
import lattice/pn_counter

pub fn main() -> Nil {
  gleeunit.main()
}

// Tests for new/constructor

pub fn new_returns_counter_at_zero_test() {
  let counter = pn_counter.new("A")
  counter
  |> pn_counter.value
  |> should.equal(0)
}

// Tests for increment

pub fn increment_adds_to_positive_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 3)
  counter
  |> pn_counter.value
  |> should.equal(3)
}

pub fn increment_by_five_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 5)
  counter
  |> pn_counter.value
  |> should.equal(5)
}

// Tests for decrement

pub fn decrement_adds_to_negative_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.decrement(counter, 2)
  counter
  |> pn_counter.value
  |> should.equal(-2)
}

pub fn decrement_by_three_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.decrement(counter, 3)
  counter
  |> pn_counter.value
  |> should.equal(-3)
}

// Tests combining increment and decrement

pub fn increment_and_decrement_combined_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 5)
  let counter = pn_counter.decrement(counter, 2)
  counter
  |> pn_counter.value
  |> should.equal(3)
}

pub fn value_returns_positive_minus_negative_test() {
  // positive:5, negative:2 = 3
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 5)
  let counter = pn_counter.decrement(counter, 2)
  counter
  |> pn_counter.value
  |> should.equal(3)
}

pub fn value_with_more_negative_test() {
  // positive:3, negative:7 = -4
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 3)
  let counter = pn_counter.decrement(counter, 7)
  counter
  |> pn_counter.value
  |> should.equal(-4)
}

// Tests for merge

pub fn merge_preserves_both_counters_test() {
  // {positive: {A:5}, negative: {A:2}} merge {positive: {A:3}, negative: {A:7}}
  // Result: positive max(A:5, A:3) = A:5, negative max(A:2, A:7) = A:7
  // Value: 5 - 7 = -2

  let a_counter = pn_counter.new("A")
  let a_counter = pn_counter.increment(a_counter, 5)
  let a_counter = pn_counter.decrement(a_counter, 2)

  let b_counter = pn_counter.new("B")
  let b_counter = pn_counter.increment(b_counter, 3)
  let b_counter = pn_counter.decrement(b_counter, 7)

  let merged = pn_counter.merge(a_counter, b_counter)

  merged
  |> pn_counter.value
  |> should.equal(-2)
}

pub fn merge_preserves_different_replicas_test() {
  // Replica A: +5
  // Replica B: -3
  // Merge should have both: +5 + (-3) = 2

  let a_counter = pn_counter.new("A")
  let a_counter = pn_counter.increment(a_counter, 5)

  let b_counter = pn_counter.new("B")
  let b_counter = pn_counter.decrement(b_counter, 3)

  let merged = pn_counter.merge(a_counter, b_counter)

  merged
  |> pn_counter.value
  |> should.equal(2)
}

pub fn concurrent_increments_and_decrements_test() {
  // A: +5, B: -3
  // B: +2, A: -1
  // After full merge: A: +4, B: -1 = 3

  let a1 = pn_counter.new("A")
  let a1 = pn_counter.increment(a1, 5)

  let b1 = pn_counter.new("B")
  let b1 = pn_counter.decrement(b1, 3)

  let merged1 = pn_counter.merge(a1, b1)
  // merged1 = A:5, B:-3 = 2

  let a2 = pn_counter.new("A")
  let a2 = pn_counter.increment(a2, 2)
  let a2 = pn_counter.decrement(a2, 1)

  let b2 = pn_counter.new("B")
  let b2 = pn_counter.increment(b2, 2)

  let merged2 = pn_counter.merge(a2, b2)
  // merged2 = A:1, B:2 = 3

  let final = pn_counter.merge(merged1, merged2)
  // final = A: max(5, 1) = 5, B: max(-3, 2) = 2 = 7

  final
  |> pn_counter.value
  |> should.equal(7)
}
