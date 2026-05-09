import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_counters/pn_counter
import qcheck
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

pub fn g_counter_simple_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let counter_a = g_counter.new(rid("A")) |> g_counter.increment(a)
      let counter_b = g_counter.new(rid("B")) |> g_counter.increment(b)
      g_counter.value(g_counter.merge(counter_a, counter_b))
      |> expect.to_equal(g_counter.value(g_counter.merge(counter_b, counter_a)))
      Nil
    },
  )
}

pub fn g_counter_simple_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let counter_a = g_counter.new(rid("A")) |> g_counter.increment(a)
      let counter_b = g_counter.new(rid("B")) |> g_counter.increment(b)
      let counter_c = g_counter.new(rid("C")) |> g_counter.increment(c)
      let merged1 =
        g_counter.merge(g_counter.merge(counter_a, counter_b), counter_c)
      let merged2 =
        g_counter.merge(counter_a, g_counter.merge(counter_b, counter_c))
      g_counter.value(merged1) |> expect.to_equal(g_counter.value(merged2))
      Nil
    },
  )
}

pub fn g_counter_simple_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.small_non_negative_int(), fn(n) {
    let counter = g_counter.new(rid("A")) |> g_counter.increment(n)
    g_counter.value(g_counter.merge(counter, counter))
    |> expect.to_equal(g_counter.value(counter))
    Nil
  })
}

pub fn pn_counter_simple_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(-50, 50),
      qcheck.bounded_int(-50, 50),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let counter_a = case a >= 0 {
        True -> pn_counter.new(rid("A")) |> pn_counter.increment(a)
        False -> pn_counter.new(rid("A")) |> pn_counter.decrement(-a)
      }
      let counter_b = case b >= 0 {
        True -> pn_counter.new(rid("B")) |> pn_counter.increment(b)
        False -> pn_counter.new(rid("B")) |> pn_counter.decrement(-b)
      }
      pn_counter.value(pn_counter.merge(counter_a, counter_b))
      |> expect.to_equal(
        pn_counter.value(pn_counter.merge(counter_b, counter_a)),
      )
      Nil
    },
  )
}

pub fn pn_counter_simple_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(-30, 30),
      qcheck.bounded_int(-30, 30),
      qcheck.bounded_int(-30, 30),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let counter_a = case a >= 0 {
        True -> pn_counter.new(rid("A")) |> pn_counter.increment(a)
        False -> pn_counter.new(rid("A")) |> pn_counter.decrement(-a)
      }
      let counter_b = case b >= 0 {
        True -> pn_counter.new(rid("B")) |> pn_counter.increment(b)
        False -> pn_counter.new(rid("B")) |> pn_counter.decrement(-b)
      }
      let counter_c = case c >= 0 {
        True -> pn_counter.new(rid("C")) |> pn_counter.increment(c)
        False -> pn_counter.new(rid("C")) |> pn_counter.decrement(-c)
      }
      let merged1 =
        pn_counter.merge(pn_counter.merge(counter_a, counter_b), counter_c)
      let merged2 =
        pn_counter.merge(counter_a, pn_counter.merge(counter_b, counter_c))
      pn_counter.value(merged1) |> expect.to_equal(pn_counter.value(merged2))
      Nil
    },
  )
}

pub fn pn_counter_simple_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(-50, 50), fn(n) {
    let counter = case n >= 0 {
      True -> pn_counter.new(rid("A")) |> pn_counter.increment(n)
      False -> pn_counter.new(rid("A")) |> pn_counter.decrement(-n)
    }
    pn_counter.value(pn_counter.merge(counter, counter))
    |> expect.to_equal(pn_counter.value(counter))
    Nil
  })
}

// ----------------------------------------------------------------------------
// Delta-state property tests.
//
// For each delta-aware mutator we verify the three δ-CRDT laws:
//   (1) Delta correctness:
//         merge(state, delta_of_op(state)) == op(state)
//   (2) Delta sufficiency on arbitrary remotes:
//         merge(remote, delta) == merge(remote, op(local))
//   (3) Idempotent + commutative replay:
//         merging a sequence of deltas in any order/duplication into a
//         fresh state converges to the same value as applying the ops
//         locally.
// ----------------------------------------------------------------------------

pub fn g_counter_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.small_non_negative_int(), fn(n) {
    let counter = g_counter.new(rid("A")) |> g_counter.increment(7)
    let direct = g_counter.increment(counter, n)
    let #(_, delta) = g_counter.increment_with_delta(counter, n)
    g_counter.value(g_counter.merge(counter, delta))
    |> expect.to_equal(g_counter.value(direct))
    Nil
  })
}

pub fn g_counter_delta_sufficiency_on_remote__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      // Local replica A starts at `a`, then increments by `b`.
      let local_before = g_counter.new(rid("A")) |> g_counter.increment(a)
      let local_after = g_counter.increment(local_before, b)
      let #(_, delta) = g_counter.increment_with_delta(local_before, b)
      // Arbitrary remote replica B at `c`.
      let remote = g_counter.new(rid("B")) |> g_counter.increment(c)
      // Applying the delta should converge equivalently to merging full state.
      g_counter.value(g_counter.merge(remote, delta))
      |> expect.to_equal(g_counter.value(g_counter.merge(remote, local_after)))
      Nil
    },
  )
}

pub fn g_counter_delta_idempotent_commutative__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      // Three sequential local mutations on replica A produce three deltas.
      let s0 = g_counter.new(rid("A"))
      let #(s1, d1) = g_counter.increment_with_delta(s0, a)
      let #(s2, d2) = g_counter.increment_with_delta(s1, b)
      let #(_s3, d3) = g_counter.increment_with_delta(s2, c)
      // Apply the deltas to a fresh remote in a scrambled order, with a
      // duplicate of d2, then verify convergence.
      let fresh = g_counter.new(rid("B"))
      let merged =
        fresh
        |> g_counter.merge(d2)
        |> g_counter.merge(d1)
        |> g_counter.merge(d3)
        |> g_counter.merge(d2)
      g_counter.value(merged) |> expect.to_equal(a + b + c)
      Nil
    },
  )
}

pub fn pn_counter_increment_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.small_non_negative_int(), fn(n) {
    let counter = pn_counter.new(rid("A")) |> pn_counter.increment(3)
    let direct = pn_counter.increment(counter, n)
    let #(_, delta) = pn_counter.increment_with_delta(counter, n)
    pn_counter.value(pn_counter.merge(counter, delta))
    |> expect.to_equal(pn_counter.value(direct))
    Nil
  })
}

pub fn pn_counter_decrement_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.small_non_negative_int(), fn(n) {
    let counter = pn_counter.new(rid("A")) |> pn_counter.increment(20)
    let direct = pn_counter.decrement(counter, n)
    let #(_, delta) = pn_counter.decrement_with_delta(counter, n)
    pn_counter.value(pn_counter.merge(counter, delta))
    |> expect.to_equal(pn_counter.value(direct))
    Nil
  })
}

pub fn pn_counter_delta_idempotent_commutative__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(inc1, dec1, inc2) = triple
      // Three sequential mutations: +inc1, -dec1, +inc2 on replica A.
      let s0 = pn_counter.new(rid("A"))
      let #(s1, d1) = pn_counter.increment_with_delta(s0, inc1)
      let #(s2, d2) = pn_counter.decrement_with_delta(s1, dec1)
      let #(_s3, d3) = pn_counter.increment_with_delta(s2, inc2)
      // Apply scrambled + duplicated to fresh remote.
      let fresh = pn_counter.new(rid("B"))
      let merged =
        fresh
        |> pn_counter.merge(d3)
        |> pn_counter.merge(d1)
        |> pn_counter.merge(d2)
        |> pn_counter.merge(d1)
      pn_counter.value(merged) |> expect.to_equal(inc1 - dec1 + inc2)
      Nil
    },
  )
}
