import lattice_core/replica_id
import lattice_counters/g_counter
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_returns_counter_at_zero_test() {
  g_counter.new(rid("A"))
  |> g_counter.value
  |> expect.to_equal(0)
}

pub fn increment_increases_value_by_one_test() {
  let assert Ok(counter) =
    g_counter.new(rid("A"))
    |> g_counter.increment(1)
  counter
  |> g_counter.value
  |> expect.to_equal(1)
}

pub fn increment_increases_value_by_five_test() {
  let assert Ok(counter) =
    g_counter.new(rid("A"))
    |> g_counter.increment(5)
  counter
  |> g_counter.value
  |> expect.to_equal(5)
}

pub fn increment_negative_delta_returns_error_test() {
  g_counter.new(rid("A"))
  |> g_counter.increment(-1)
  |> expect.to_equal(Error(g_counter.NegativeDelta(-1)))
}

pub fn value_returns_sum_of_all_replicas_test() {
  let a_counter = g_counter.new(rid("A"))
  let assert Ok(a_counter) = g_counter.increment(a_counter, 3)

  let b_counter = g_counter.new(rid("B"))
  let assert Ok(b_counter) = g_counter.increment(b_counter, 2)

  let merged = g_counter.merge(a_counter, b_counter)

  merged
  |> g_counter.value
  |> expect.to_equal(5)
}

pub fn merge_uses_max_per_key_test() {
  // {A:3} merge {A:1} = {A:3}
  let a_counter = g_counter.new(rid("A"))
  let assert Ok(a_counter) = g_counter.increment(a_counter, 3)

  let a1 = g_counter.new(rid("A"))
  let assert Ok(a1) = g_counter.increment(a1, 1)

  let merged = g_counter.merge(a_counter, a1)

  merged
  |> g_counter.value
  |> expect.to_equal(3)
}

pub fn merge_two_counters_test() {
  // {A:1, B:1} merge {A:1} = {A:1, B:1}
  let a1_b1 = g_counter.new(rid("A"))
  let assert Ok(a1_b1) = g_counter.increment(a1_b1, 1)

  let b1 = g_counter.new(rid("B"))
  let assert Ok(b1) = g_counter.increment(b1, 1)

  let a1 = g_counter.new(rid("A"))
  let assert Ok(a1) = g_counter.increment(a1, 1)

  let first = g_counter.merge(a1_b1, b1)
  let merged = g_counter.merge(first, a1)

  merged
  |> g_counter.value
  |> expect.to_equal(2)
}

pub fn increment_with_delta_negative_delta_returns_error_test() {
  let counter = g_counter.new(rid("A"))
  g_counter.increment_with_delta(counter, -7)
  |> expect.to_equal(Error(g_counter.NegativeDelta(-7)))
  g_counter.value(counter) |> expect.to_equal(0)
}

pub fn increment_zero_preserves_value_and_delta_test() {
  let assert Ok(counter) = g_counter.increment(g_counter.new(rid("A")), 5)
  let assert Ok(updated) = g_counter.increment(counter, 0)
  let assert Ok(#(with_delta, delta)) =
    g_counter.increment_with_delta(counter, 0)
  updated |> expect.to_equal(counter)
  with_delta |> expect.to_equal(updated)
  g_counter.merge(counter, delta) |> expect.to_equal(updated)
}

pub fn increment_positive_state_and_delta_agree_test() {
  let assert Ok(counter) = g_counter.increment(g_counter.new(rid("A")), 5)
  let assert Ok(updated) = g_counter.increment(counter, 3)
  let assert Ok(#(with_delta, delta)) =
    g_counter.increment_with_delta(counter, 3)
  g_counter.value(updated) |> expect.to_equal(8)
  with_delta |> expect.to_equal(updated)
  g_counter.merge(counter, delta) |> expect.to_equal(updated)
}
