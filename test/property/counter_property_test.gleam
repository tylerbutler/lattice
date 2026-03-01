import lattice/g_counter
import lattice/pn_counter
import qcheck
import startest/expect

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
      let counter_a = g_counter.new("A") |> g_counter.increment(a)
      let counter_b = g_counter.new("B") |> g_counter.increment(b)
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
      let counter_a = g_counter.new("A") |> g_counter.increment(a)
      let counter_b = g_counter.new("B") |> g_counter.increment(b)
      let counter_c = g_counter.new("C") |> g_counter.increment(c)
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
    let counter = g_counter.new("A") |> g_counter.increment(n)
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
        True -> pn_counter.new("A") |> pn_counter.increment(a)
        False -> pn_counter.new("A") |> pn_counter.decrement(-a)
      }
      let counter_b = case b >= 0 {
        True -> pn_counter.new("B") |> pn_counter.increment(b)
        False -> pn_counter.new("B") |> pn_counter.decrement(-b)
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
        True -> pn_counter.new("A") |> pn_counter.increment(a)
        False -> pn_counter.new("A") |> pn_counter.decrement(-a)
      }
      let counter_b = case b >= 0 {
        True -> pn_counter.new("B") |> pn_counter.increment(b)
        False -> pn_counter.new("B") |> pn_counter.decrement(-b)
      }
      let counter_c = case c >= 0 {
        True -> pn_counter.new("C") |> pn_counter.increment(c)
        False -> pn_counter.new("C") |> pn_counter.decrement(-c)
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
      True -> pn_counter.new("A") |> pn_counter.increment(n)
      False -> pn_counter.new("A") |> pn_counter.decrement(-n)
    }
    pn_counter.value(pn_counter.merge(counter, counter))
    |> expect.to_equal(pn_counter.value(counter))
    Nil
  })
}
