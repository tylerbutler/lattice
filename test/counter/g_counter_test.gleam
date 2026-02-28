import gleeunit
import gleeunit/should
import lattice/g_counter

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn new_returns_counter_at_zero_test() {
  g_counter.new("A")
  |> g_counter.value
  |> should.equal(0)
}

pub fn increment_increases_value_by_one_test() {
  g_counter.new("A")
  |> g_counter.increment(1)
  |> g_counter.value
  |> should.equal(1)
}

pub fn increment_increases_value_by_five_test() {
  g_counter.new("A")
  |> g_counter.increment(5)
  |> g_counter.value
  |> should.equal(5)
}

pub fn value_returns_sum_of_all_replicas_test() {
  // A:3, B:2 should return 5
  let counter = g_counter.new("A")
  let counter = g_counter.increment(counter, 3)
  let counter = g_counter.increment(counter, 0)
  // This doesn't affect A, just creates base
  // Actually, to add another replica, we need merge

  // Let's test by creating separate counters and merging
  let a_counter = g_counter.new("A")
  let a_counter = g_counter.increment(a_counter, 3)

  let b_counter = g_counter.new("B")
  let b_counter = g_counter.increment(b_counter, 2)

  let merged = g_counter.merge(a_counter, b_counter)

  merged
  |> g_counter.value
  |> should.equal(5)
}

pub fn merge_uses_max_per_key_test() {
  // {A:3} merge {A:1, B:2} = {A:3, B:2}
  let a_counter = g_counter.new("A")
  let a_counter = g_counter.increment(a_counter, 3)

  let b_counter = g_counter.new("B")
  let b_counter = g_counter.increment(b_counter, 2)

  // Merge into a new counter with just A:1
  let a1 = g_counter.new("A")
  let a1 = g_counter.increment(a1, 1)

  let merged = g_counter.merge(a_counter, a1)

  merged
  |> g_counter.value
  |> should.equal(3)
}

pub fn merge_two_counters_test() {
  // {A:1, B:1} merge {A:2} = {A:2, B:1}
  let a1_b1 = g_counter.new("A")
  let a1_b1 = g_counter.increment(a1_b1, 1)
  // We need to add B somehow - through merge

  let b1 = g_counter.new("B")
  let b1 = g_counter.increment(b1, 1)

  let a1 = g_counter.new("A")
  let a1 = g_counter.increment(a1, 1)

  let first = g_counter.merge(a1_b1, b1)
  let merged = g_counter.merge(first, a1)

  merged
  |> g_counter.value
  |> should.equal(2)
}
