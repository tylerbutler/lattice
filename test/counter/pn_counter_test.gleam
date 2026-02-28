import lattice/pn_counter
import startest/expect

// Tests for new/constructor

pub fn new_returns_counter_at_zero_test() {
  let counter = pn_counter.new("A")
  counter
  |> pn_counter.value
  |> expect.to_equal(0)
}

// Tests for increment

pub fn increment_adds_to_positive_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 3)
  counter
  |> pn_counter.value
  |> expect.to_equal(3)
}

pub fn increment_by_five_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 5)
  counter
  |> pn_counter.value
  |> expect.to_equal(5)
}

// Tests for decrement

pub fn decrement_adds_to_negative_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.decrement(counter, 2)
  counter
  |> pn_counter.value
  |> expect.to_equal(-2)
}

pub fn decrement_by_three_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.decrement(counter, 3)
  counter
  |> pn_counter.value
  |> expect.to_equal(-3)
}

// Tests combining increment and decrement

pub fn increment_and_decrement_combined_test() {
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 5)
  let counter = pn_counter.decrement(counter, 2)
  counter
  |> pn_counter.value
  |> expect.to_equal(3)
}

pub fn value_returns_positive_minus_negative_test() {
  // positive:5, negative:2 = 3
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 5)
  let counter = pn_counter.decrement(counter, 2)
  counter
  |> pn_counter.value
  |> expect.to_equal(3)
}

pub fn value_with_more_negative_test() {
  // positive:3, negative:7 = -4
  let counter = pn_counter.new("A")
  let counter = pn_counter.increment(counter, 3)
  let counter = pn_counter.decrement(counter, 7)
  counter
  |> pn_counter.value
  |> expect.to_equal(-4)
}

// Tests for merge

pub fn merge_preserves_both_counters_test() {
  let a_counter = pn_counter.new("A")
  let a_counter = pn_counter.increment(a_counter, 5)
  let a_counter = pn_counter.decrement(a_counter, 2)

  let b_counter = pn_counter.new("B")
  let b_counter = pn_counter.increment(b_counter, 3)
  let b_counter = pn_counter.decrement(b_counter, 7)

  let merged = pn_counter.merge(a_counter, b_counter)

  merged
  |> pn_counter.value
  |> expect.to_equal(-1)
}

pub fn merge_preserves_different_replicas_test() {
  let a_counter = pn_counter.new("A")
  let a_counter = pn_counter.increment(a_counter, 5)

  let b_counter = pn_counter.new("B")
  let b_counter = pn_counter.decrement(b_counter, 3)

  let merged = pn_counter.merge(a_counter, b_counter)

  merged
  |> pn_counter.value
  |> expect.to_equal(2)
}

pub fn concurrent_increments_and_decrements_test() {
  let a1 = pn_counter.new("A")
  let a1 = pn_counter.increment(a1, 5)

  let b1 = pn_counter.new("B")
  let b1 = pn_counter.decrement(b1, 3)

  let merged1 = pn_counter.merge(a1, b1)

  let a2 = pn_counter.new("A")
  let a2 = pn_counter.increment(a2, 2)
  let a2 = pn_counter.decrement(a2, 1)

  let b2 = pn_counter.new("B")
  let b2 = pn_counter.increment(b2, 2)

  let merged2 = pn_counter.merge(a2, b2)

  let final = pn_counter.merge(merged1, merged2)

  final
  |> pn_counter.value
  |> expect.to_equal(3)
}
