import gleeunit
import gleeunit/should
import lattice/g_counter
import lattice/pn_counter

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

// PN-Counter commutativity test: merge(a, b) == merge(b, a)
pub fn pn_counter_merge_commutativity__test() {
  let a = pn_counter.new("A")
  let a = pn_counter.increment(a, 10)
  let a = pn_counter.decrement(a, 3)

  let b = pn_counter.new("B")
  let b = pn_counter.increment(b, 7)
  let b = pn_counter.decrement(b, 2)

  let merge_ab = pn_counter.merge(a, b)
  let merge_ba = pn_counter.merge(b, a)

  pn_counter.value(merge_ab)
  |> should.equal(pn_counter.value(merge_ba))
}

// PN-Counter associativity test: merge(merge(a, b), c) == merge(a, merge(b, c))
pub fn pn_counter_merge_associativity__test() {
  let a = pn_counter.new("A") |> pn_counter.increment(5)
  let b = pn_counter.new("B") |> pn_counter.increment(3)
  let c = pn_counter.new("C") |> pn_counter.increment(7)

  let merge_ab_c = pn_counter.merge(pn_counter.merge(a, b), c)
  let merge_a_bc = pn_counter.merge(a, pn_counter.merge(b, c))

  pn_counter.value(merge_ab_c)
  |> should.equal(pn_counter.value(merge_a_bc))
}

// PN-Counter idempotency test: merge(a, a) == a
pub fn pn_counter_merge_idempotency__test() {
  let a = pn_counter.new("A")
  let a = pn_counter.increment(a, 10)
  let a = pn_counter.decrement(a, 3)

  let merged = pn_counter.merge(a, a)

  pn_counter.value(merged)
  |> should.equal(pn_counter.value(a))
}

// PN-Counter convergence test: all-to-all exchange produces identical values
pub fn pn_counter_merge_convergence__test() {
  // Create three replicas
  let a =
    pn_counter.new("A") |> pn_counter.increment(10) |> pn_counter.decrement(3)
  let b = pn_counter.new("B") |> pn_counter.increment(5)
  let c =
    pn_counter.new("C") |> pn_counter.increment(2) |> pn_counter.decrement(1)

  // All-to-all merge: a receives from b and c
  let a_final = pn_counter.merge(a, pn_counter.merge(b, c))
  // b receives from a and c
  let b_final = pn_counter.merge(b, pn_counter.merge(a, c))
  // c receives from a and b
  let c_final = pn_counter.merge(c, pn_counter.merge(a, b))

  // All replicas should have the same value after convergence
  let a_val = pn_counter.value(a_final)
  let b_val = pn_counter.value(b_final)
  let c_val = pn_counter.value(c_final)

  a_val |> should.equal(b_val)
  b_val |> should.equal(c_val)
}
