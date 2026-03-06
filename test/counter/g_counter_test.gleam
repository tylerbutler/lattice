import lattice/g_counter
import startest/expect

pub fn new_returns_counter_at_zero_test() {
  g_counter.new("A")
  |> g_counter.value
  |> expect.to_equal(0)
}

pub fn increment_increases_value_by_one_test() {
  g_counter.new("A")
  |> g_counter.increment(1)
  |> g_counter.value
  |> expect.to_equal(1)
}

pub fn increment_increases_value_by_five_test() {
  g_counter.new("A")
  |> g_counter.increment(5)
  |> g_counter.value
  |> expect.to_equal(5)
}

pub fn value_returns_sum_of_all_replicas_test() {
  let a_counter = g_counter.new("A")
  let a_counter = g_counter.increment(a_counter, 3)

  let b_counter = g_counter.new("B")
  let b_counter = g_counter.increment(b_counter, 2)

  let merged = g_counter.merge(a_counter, b_counter)

  merged
  |> g_counter.value
  |> expect.to_equal(5)
}

pub fn merge_uses_max_per_key_test() {
  // {A:3} merge {A:1} = {A:3}
  let a_counter = g_counter.new("A")
  let a_counter = g_counter.increment(a_counter, 3)

  let a1 = g_counter.new("A")
  let a1 = g_counter.increment(a1, 1)

  let merged = g_counter.merge(a_counter, a1)

  merged
  |> g_counter.value
  |> expect.to_equal(3)
}

pub fn merge_two_counters_test() {
  // {A:1, B:1} merge {A:1} = {A:1, B:1}
  let a1_b1 = g_counter.new("A")
  let a1_b1 = g_counter.increment(a1_b1, 1)

  let b1 = g_counter.new("B")
  let b1 = g_counter.increment(b1, 1)

  let a1 = g_counter.new("A")
  let a1 = g_counter.increment(a1, 1)

  let first = g_counter.merge(a1_b1, b1)
  let merged = g_counter.merge(first, a1)

  merged
  |> g_counter.value
  |> expect.to_equal(2)
}
