import lattice_core/replica_id
import lattice_counters/pn_counter

fn rid(id: String) {
  replica_id.new(id)
}

// Tests for new/constructor

pub fn new_returns_counter_at_zero_test() {
  let counter = pn_counter.new(rid("A"))
  assert counter
    |> pn_counter.value
    == 0
}

// Tests for increment

pub fn increment_adds_to_positive_test() {
  let counter = pn_counter.new(rid("A"))
  let assert Ok(counter) = pn_counter.increment(counter, 3)
  assert counter
    |> pn_counter.value
    == 3
}

pub fn increment_by_five_test() {
  let counter = pn_counter.new(rid("A"))
  let assert Ok(counter) = pn_counter.increment(counter, 5)
  assert counter
    |> pn_counter.value
    == 5
}

// Tests for decrement

pub fn decrement_adds_to_negative_test() {
  let counter = pn_counter.new(rid("A"))
  let assert Ok(counter) = pn_counter.decrement(counter, 2)
  assert counter
    |> pn_counter.value
    == -2
}

pub fn decrement_by_three_test() {
  let counter = pn_counter.new(rid("A"))
  let assert Ok(counter) = pn_counter.decrement(counter, 3)
  assert counter
    |> pn_counter.value
    == -3
}

pub fn increment_negative_delta_returns_error_test() {
  assert pn_counter.new(rid("A"))
    |> pn_counter.increment(-1)
    == Error(pn_counter.NegativeDelta(-1))
}

pub fn decrement_negative_delta_returns_error_test() {
  assert pn_counter.new(rid("A"))
    |> pn_counter.decrement(-1)
    == Error(pn_counter.NegativeDelta(-1))
}

// Tests combining increment and decrement

pub fn increment_and_decrement_combined_test() {
  let counter = pn_counter.new(rid("A"))
  let assert Ok(counter) = pn_counter.increment(counter, 5)
  let assert Ok(counter) = pn_counter.decrement(counter, 2)
  assert counter
    |> pn_counter.value
    == 3
}

pub fn value_returns_positive_minus_negative_test() {
  // positive:5, negative:2 = 3
  let counter = pn_counter.new(rid("A"))
  let assert Ok(counter) = pn_counter.increment(counter, 5)
  let assert Ok(counter) = pn_counter.decrement(counter, 2)
  assert counter
    |> pn_counter.value
    == 3
}

pub fn value_with_more_negative_test() {
  // positive:3, negative:7 = -4
  let counter = pn_counter.new(rid("A"))
  let assert Ok(counter) = pn_counter.increment(counter, 3)
  let assert Ok(counter) = pn_counter.decrement(counter, 7)
  assert counter
    |> pn_counter.value
    == -4
}

// Tests for merge

pub fn merge_preserves_both_counters_test() {
  let a_counter = pn_counter.new(rid("A"))
  let assert Ok(a_counter) = pn_counter.increment(a_counter, 5)
  let assert Ok(a_counter) = pn_counter.decrement(a_counter, 2)

  let b_counter = pn_counter.new(rid("B"))
  let assert Ok(b_counter) = pn_counter.increment(b_counter, 3)
  let assert Ok(b_counter) = pn_counter.decrement(b_counter, 7)

  let merged = pn_counter.merge(a_counter, b_counter)

  assert merged
    |> pn_counter.value
    == -1
}

pub fn merge_preserves_different_replicas_test() {
  let a_counter = pn_counter.new(rid("A"))
  let assert Ok(a_counter) = pn_counter.increment(a_counter, 5)

  let b_counter = pn_counter.new(rid("B"))
  let assert Ok(b_counter) = pn_counter.decrement(b_counter, 3)

  let merged = pn_counter.merge(a_counter, b_counter)

  assert merged
    |> pn_counter.value
    == 2
}

pub fn concurrent_increments_and_decrements_test() {
  let a1 = pn_counter.new(rid("A"))
  let assert Ok(a1) = pn_counter.increment(a1, 5)

  let b1 = pn_counter.new(rid("B"))
  let assert Ok(b1) = pn_counter.decrement(b1, 3)

  let merged1 = pn_counter.merge(a1, b1)

  let a2 = pn_counter.new(rid("A"))
  let assert Ok(a2) = pn_counter.increment(a2, 2)
  let assert Ok(a2) = pn_counter.decrement(a2, 1)

  let b2 = pn_counter.new(rid("B"))
  let assert Ok(b2) = pn_counter.increment(b2, 2)

  let merged2 = pn_counter.merge(a2, b2)

  let final = pn_counter.merge(merged1, merged2)

  assert final
    |> pn_counter.value
    == 3
}

pub fn delta_updates_reject_negative_amounts_test() {
  let counter = pn_counter.new(rid("A"))
  assert pn_counter.increment_with_delta(counter, -7)
    == Error(pn_counter.NegativeDelta(-7))
  assert pn_counter.decrement_with_delta(counter, -9)
    == Error(pn_counter.NegativeDelta(-9))
  assert pn_counter.value(counter) == 0
}

pub fn zero_updates_preserve_value_and_delta_test() {
  let assert Ok(counter) = pn_counter.increment(pn_counter.new(rid("A")), 5)
  let assert Ok(counter) = pn_counter.decrement(counter, 2)
  let assert Ok(incremented) = pn_counter.increment(counter, 0)
  let assert Ok(decremented) = pn_counter.decrement(counter, 0)
  let assert Ok(#(inc_state, inc_delta)) =
    pn_counter.increment_with_delta(counter, 0)
  let assert Ok(#(dec_state, dec_delta)) =
    pn_counter.decrement_with_delta(counter, 0)
  assert incremented == counter
  assert decremented == counter
  assert inc_state == incremented
  assert dec_state == decremented
  assert pn_counter.merge(counter, inc_delta) == counter
  assert pn_counter.merge(counter, dec_delta) == counter
}

pub fn positive_updates_state_and_delta_agree_test() {
  let assert Ok(counter) = pn_counter.increment(pn_counter.new(rid("A")), 5)
  let assert Ok(counter) = pn_counter.decrement(counter, 2)
  let assert Ok(incremented) = pn_counter.increment(counter, 4)
  let assert Ok(decremented) = pn_counter.decrement(counter, 4)
  let assert Ok(#(inc_state, inc_delta)) =
    pn_counter.increment_with_delta(counter, 4)
  let assert Ok(#(dec_state, dec_delta)) =
    pn_counter.decrement_with_delta(counter, 4)
  assert pn_counter.value(incremented) == 7
  assert pn_counter.value(decremented) == -1
  assert inc_state == incremented
  assert dec_state == decremented
  assert pn_counter.merge(counter, inc_delta) == incremented
  assert pn_counter.merge(counter, dec_delta) == decremented
}
