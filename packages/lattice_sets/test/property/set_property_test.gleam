import lattice_core/replica_id
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import qcheck
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

// ---------------------------------------------------------------------------
// G-Set property tests
// ---------------------------------------------------------------------------

pub fn g_set_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 20), qcheck.bounded_int(0, 20), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let set_a = g_set.new() |> g_set.add(a)
      let set_b = g_set.new() |> g_set.add(b)
      g_set.value(g_set.merge(set_a, set_b))
      |> expect.to_equal(g_set.value(g_set.merge(set_b, set_a)))
      Nil
    },
  )
}

pub fn g_set_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let set_a = g_set.new() |> g_set.add(a)
      let set_b = g_set.new() |> g_set.add(b)
      let set_c = g_set.new() |> g_set.add(c)
      let merged1 = g_set.merge(g_set.merge(set_a, set_b), set_c)
      let merged2 = g_set.merge(set_a, g_set.merge(set_b, set_c))
      g_set.value(merged1) |> expect.to_equal(g_set.value(merged2))
      Nil
    },
  )
}

pub fn g_set_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 20), fn(a) {
    let s = g_set.new() |> g_set.add(a)
    g_set.merge(s, s) |> expect.to_equal(s)
    Nil
  })
}

// ---------------------------------------------------------------------------
// 2P-Set property tests
// ---------------------------------------------------------------------------

pub fn two_p_set_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 20), qcheck.bounded_int(0, 20), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let set_a = two_p_set.new() |> two_p_set.add(a)
      let set_b = two_p_set.new() |> two_p_set.add(b)
      two_p_set.value(two_p_set.merge(set_a, set_b))
      |> expect.to_equal(two_p_set.value(two_p_set.merge(set_b, set_a)))
      Nil
    },
  )
}

pub fn two_p_set_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let set_a = two_p_set.new() |> two_p_set.add(a)
      let set_b = two_p_set.new() |> two_p_set.add(b)
      let set_c = two_p_set.new() |> two_p_set.add(c)
      let merged1 = two_p_set.merge(two_p_set.merge(set_a, set_b), set_c)
      let merged2 = two_p_set.merge(set_a, two_p_set.merge(set_b, set_c))
      two_p_set.value(merged1) |> expect.to_equal(two_p_set.value(merged2))
      Nil
    },
  )
}

pub fn two_p_set_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 20), fn(a) {
    let s = two_p_set.new() |> two_p_set.add(a)
    two_p_set.merge(s, s) |> expect.to_equal(s)
    Nil
  })
}

// ---------------------------------------------------------------------------
// OR-Set property tests
// ---------------------------------------------------------------------------

pub fn or_set_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 10), qcheck.bounded_int(0, 10), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let set_a = or_set.new(rid("A")) |> or_set.add(a)
      let set_b = or_set.new(rid("B")) |> or_set.add(b)
      or_set.value(or_set.merge(set_a, set_b))
      |> expect.to_equal(or_set.value(or_set.merge(set_b, set_a)))
      Nil
    },
  )
}

pub fn or_set_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 10), fn(a) {
    let s = or_set.new(rid("A")) |> or_set.add(a)
    or_set.value(or_set.merge(s, s))
    |> expect.to_equal(or_set.value(s))
    Nil
  })
}
