import gleam/set as gleam_set
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

// ---------------------------------------------------------------------------
// Delta-state property tests.
// Verify the three δ-CRDT laws for each delta-aware mutator.
// ---------------------------------------------------------------------------

pub fn g_set_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let s = g_set.new() |> g_set.add(7)
    let direct = g_set.add(s, n)
    let #(_, delta) = g_set.add_with_delta(s, n)
    g_set.value(g_set.merge(s, delta))
    |> expect.to_equal(g_set.value(direct))
    Nil
  })
}

pub fn g_set_delta_idempotent_commutative__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 50),
      qcheck.bounded_int(0, 50),
      qcheck.bounded_int(0, 50),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let s0 = g_set.new()
      let #(s1, d1) = g_set.add_with_delta(s0, a)
      let #(s2, d2) = g_set.add_with_delta(s1, b)
      let #(_s3, d3) = g_set.add_with_delta(s2, c)
      // Apply scrambled + duplicated to a fresh remote.
      let merged =
        g_set.new()
        |> g_set.merge(d3)
        |> g_set.merge(d1)
        |> g_set.merge(d2)
        |> g_set.merge(d1)
      g_set.value(merged)
      |> expect.to_equal(gleam_set.from_list([a, b, c]))
      Nil
    },
  )
}

pub fn two_p_set_add_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let s = two_p_set.new() |> two_p_set.add(1) |> two_p_set.remove(2)
    let direct = two_p_set.add(s, n)
    let #(_, delta) = two_p_set.add_with_delta(s, n)
    two_p_set.value(two_p_set.merge(s, delta))
    |> expect.to_equal(two_p_set.value(direct))
    Nil
  })
}

pub fn two_p_set_remove_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let s = two_p_set.new() |> two_p_set.add(n) |> two_p_set.add(99)
    let direct = two_p_set.remove(s, n)
    let #(_, delta) = two_p_set.remove_with_delta(s, n)
    two_p_set.value(two_p_set.merge(s, delta))
    |> expect.to_equal(two_p_set.value(direct))
    Nil
  })
}

pub fn two_p_set_remove_delta_propagates_tombstone__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    // Remote replica has element added but never observed the remove.
    let remote = two_p_set.new() |> two_p_set.add(n)
    let local = two_p_set.new() |> two_p_set.add(n)
    let #(_, remove_delta) = two_p_set.remove_with_delta(local, n)
    // Applying the remove delta to the remote must deactivate the element.
    two_p_set.contains(two_p_set.merge(remote, remove_delta), n)
    |> expect.to_equal(False)
    Nil
  })
}

pub fn or_set_add_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    let s = or_set.new(rid("A")) |> or_set.add(7)
    let direct = or_set.add(s, n)
    let #(_, delta) = or_set.add_with_delta(s, n)
    or_set.value(or_set.merge(s, delta))
    |> expect.to_equal(or_set.value(direct))
    Nil
  })
}

pub fn or_set_add_delta_sufficiency_on_fresh_remote__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    // Fresh remote has never seen the element. Delta alone must suffice.
    let local = or_set.new(rid("A"))
    let #(_, delta) = or_set.add_with_delta(local, n)
    let remote = or_set.new(rid("B"))
    or_set.contains(or_set.merge(remote, delta), n)
    |> expect.to_equal(True)
    Nil
  })
}

pub fn or_set_remove_delta_add_wins__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(n) {
    // Replica A adds and removes; replica B concurrently adds.
    // Applying A's remove delta to B must NOT remove B's concurrent add.
    let a = or_set.new(rid("A")) |> or_set.add(n)
    let #(_, remove_delta) = or_set.remove_with_delta(a, n)
    let b = or_set.new(rid("B")) |> or_set.add(n)
    or_set.contains(or_set.merge(b, remove_delta), n)
    |> expect.to_equal(True)
    Nil
  })
}

pub fn or_set_delta_idempotent_commutative__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 30),
      qcheck.bounded_int(0, 30),
      qcheck.bounded_int(0, 30),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(x, y, z) = triple
      // Sequence on replica A: add x, add y, add z, remove y.
      let s0 = or_set.new(rid("A"))
      let #(s1, d_add_x) = or_set.add_with_delta(s0, x)
      let #(s2, d_add_y) = or_set.add_with_delta(s1, y)
      let #(s3, d_add_z) = or_set.add_with_delta(s2, z)
      let #(local_final, d_rm_y) = or_set.remove_with_delta(s3, y)
      // Apply scrambled + duplicated deltas to fresh remote of replica B.
      let from_deltas =
        or_set.new(rid("B"))
        |> or_set.merge(d_add_z)
        |> or_set.merge(d_rm_y)
        |> or_set.merge(d_add_x)
        |> or_set.merge(d_add_y)
        |> or_set.merge(d_add_x)
        |> or_set.merge(d_rm_y)
      // Apply the full final state to a fresh replica B for comparison.
      let from_full = or_set.merge(or_set.new(rid("B")), local_final)
      // The two paths must converge to the same observable value, regardless
      // of delta ordering and duplication.
      or_set.value(from_deltas)
      |> expect.to_equal(or_set.value(from_full))
      Nil
    },
  )
}
