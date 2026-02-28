import gleam/int
import gleeunit/should
import lattice/g_counter
import qcheck

// Generator for G-Counter - generates random G-Counters
fn g_counter_generator() {
  qcheck.map2(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    fn(seed, delta) {
      // Use seed as replica_id and create counter with initial value
      let replica_id = "replica_" <> int.to_string(seed % 5)
      g_counter.new(replica_id)
      |> g_counter.increment(delta)
    },
  )
}

// G-Counter commutativity test: merge(a, b) == merge(b, a)
pub fn g_counter_merge_commutativity__test() {
  use a <- qcheck.given(g_counter_generator())
  use b <- qcheck.given(g_counter_generator())

  let merge_ab = g_counter.merge(a, b)
  let merge_ba = g_counter.merge(b, a)

  // G-Counters should be equal after merge regardless of order
  g_counter.value(merge_ab)
  |> should.equal(g_counter.value(merge_ba))
}

// G-Counter associativity test: merge(merge(a, b), c) == merge(a, merge(b, c))
pub fn g_counter_merge_associativity__test() {
  use a <- qcheck.given(g_counter_generator())
  use b <- qcheck.given(g_counter_generator())
  use c <- qcheck.given(g_counter_generator())

  let merge_ab_c = g_counter.merge(g_counter.merge(a, b), c)
  let merge_a_bc = g_counter.merge(a, g_counter.merge(b, c))

  // Values should be equal after associative merge
  g_counter.value(merge_ab_c)
  |> should.equal(g_counter.value(merge_a_bc))
}

// G-Counter idempotency test: merge(a, a) == a
pub fn g_counter_merge_idempotency__test() {
  use a <- qcheck.given(g_counter_generator())

  let merged = g_counter.merge(a, a)

  // Merging with self should not change value
  g_counter.value(merged)
  |> should.equal(g_counter.value(a))
}

// G-Counter monotonicity test: value(merge(a, b)) >= value(a)
pub fn g_counter_merge_monotonicity__test() {
  use a <- qcheck.given(g_counter_generator())
  use b <- qcheck.given(g_counter_generator())

  let merged = g_counter.merge(a, b)
  let is_monotonic = g_counter.value(merged) >= g_counter.value(a)

  // G-Counter is grow-only, so merged value >= each operand
  is_monotonic |> should.be_true()
}
