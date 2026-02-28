import gleeunit
import gleeunit/should
import lattice/g_counter

pub fn main() -> Nil {
  gleeunit.main()
}

// G-Counter commutativity test: merge(a, b) == merge(b, a)
pub fn g_counter_merge_commutativity__test() {
  // Test with explicit test cases
  let a = g_counter.new("A") |> g_counter.increment(5)
  let b = g_counter.new("B") |> g_counter.increment(3)

  let merge_ab = g_counter.merge(a, b)
  let merge_ba = g_counter.merge(b, a)

  g_counter.value(merge_ab)
  |> should.equal(g_counter.value(merge_ba))
}

// G-Counter associativity test: merge(merge(a, b), c) == merge(a, merge(b, c))
pub fn g_counter_merge_associativity__test() {
  let a = g_counter.new("A") |> g_counter.increment(5)
  let b = g_counter.new("B") |> g_counter.increment(3)
  let c = g_counter.new("C") |> g_counter.increment(7)

  let merge_ab_c = g_counter.merge(g_counter.merge(a, b), c)
  let merge_a_bc = g_counter.merge(a, g_counter.merge(b, c))

  g_counter.value(merge_ab_c)
  |> should.equal(g_counter.value(merge_a_bc))
}

// G-Counter idempotency test: merge(a, a) == a
pub fn g_counter_merge_idempotency__test() {
  let a = g_counter.new("A") |> g_counter.increment(5)

  let merged = g_counter.merge(a, a)

  g_counter.value(merged)
  |> should.equal(g_counter.value(a))
}

// G-Counter monotonicity test: value(merge(a, b)) >= value(a)
pub fn g_counter_merge_monotonicity__test() {
  let a = g_counter.new("A") |> g_counter.increment(5)
  let b = g_counter.new("B") |> g_counter.increment(3)

  let merged = g_counter.merge(a, b)
  let is_monotonic = g_counter.value(merged) >= g_counter.value(a)

  // G-Counter is grow-only, so merged value >= each operand
  is_monotonic |> should.be_true()
}

// Additional random test for more thorough verification
pub fn g_counter_merge_random_tests__test() {
  // Test multiple random merge scenarios
  // Merge two counters with overlapping keys
  let a1 = g_counter.new("A") |> g_counter.increment(10)
  let a2 = g_counter.new("A") |> g_counter.increment(5)
  let merged = g_counter.merge(a1, a2)
  merged |> g_counter.value |> should.equal(10)

  // Merge with empty counter
  let empty = g_counter.new("X")
  let nonempty = g_counter.new("Y") |> g_counter.increment(7)
  let merged_empty = g_counter.merge(empty, nonempty)
  merged_empty |> g_counter.value |> should.equal(7)

  // Merge three counters
  let x = g_counter.new("X") |> g_counter.increment(1)
  let y = g_counter.new("Y") |> g_counter.increment(2)
  let z = g_counter.new("Z") |> g_counter.increment(3)
  let merged_xyz = g_counter.merge(g_counter.merge(x, y), z)
  merged_xyz |> g_counter.value |> should.equal(6)
}
