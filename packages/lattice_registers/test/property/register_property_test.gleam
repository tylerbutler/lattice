import gleam/int
import gleam/list
import gleam/order
import gleam/string
import lattice_core/replica_id
import lattice_registers/lww_register
import lattice_registers/mv_register
import qcheck
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

// ---------------------------------------------------------------------------
// LWW-Register property tests
// ---------------------------------------------------------------------------

pub fn lww_register_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(ts_a, ts_b) = pair
      let reg_a = lww_register.new("val_a", ts_a, rid("A"))
      let reg_b = lww_register.new("val_b", ts_b, rid("B"))
      lww_register.value(lww_register.merge(reg_a, reg_b))
      |> expect.to_equal(lww_register.value(lww_register.merge(reg_b, reg_a)))
      Nil
    },
  )
}

pub fn lww_register_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(ts_a, ts_b, ts_c) = triple
      let reg_a = lww_register.new("val_a", ts_a, rid("A"))
      let reg_b = lww_register.new("val_b", ts_b, rid("B"))
      let reg_c = lww_register.new("val_c", ts_c, rid("C"))
      let merged1 = lww_register.merge(lww_register.merge(reg_a, reg_b), reg_c)
      let merged2 = lww_register.merge(reg_a, lww_register.merge(reg_b, reg_c))
      lww_register.value(merged1)
      |> expect.to_equal(lww_register.value(merged2))
      Nil
    },
  )
}

pub fn lww_register_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(ts) {
    let reg = lww_register.new("val_a", ts, rid("A"))
    lww_register.value(lww_register.merge(reg, reg))
    |> expect.to_equal(lww_register.value(reg))
    Nil
  })
}

// ---------------------------------------------------------------------------
// MV-Register property tests
// ---------------------------------------------------------------------------

pub fn mv_register_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 10), qcheck.bounded_int(0, 10), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(a, b) = pair
      let reg_a = mv_register.new(rid("A")) |> mv_register.set(a)
      let reg_b = mv_register.new(rid("B")) |> mv_register.set(b)
      let sorted_ab =
        list.sort(
          mv_register.value(mv_register.merge(reg_a, reg_b)),
          int.compare,
        )
      let sorted_ba =
        list.sort(
          mv_register.value(mv_register.merge(reg_b, reg_a)),
          int.compare,
        )
      sorted_ab |> expect.to_equal(sorted_ba)
      Nil
    },
  )
}

pub fn mv_register_associativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 10),
      qcheck.bounded_int(0, 10),
      qcheck.bounded_int(0, 10),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let reg_a = mv_register.new(rid("A")) |> mv_register.set(a)
      let reg_b = mv_register.new(rid("B")) |> mv_register.set(b)
      let reg_c = mv_register.new(rid("C")) |> mv_register.set(c)
      let merged1 = mv_register.merge(mv_register.merge(reg_a, reg_b), reg_c)
      let merged2 = mv_register.merge(reg_a, mv_register.merge(reg_b, reg_c))
      let sorted1 = list.sort(mv_register.value(merged1), int.compare)
      let sorted2 = list.sort(mv_register.value(merged2), int.compare)
      sorted1 |> expect.to_equal(sorted2)
      Nil
    },
  )
}

pub fn mv_register_idempotency__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 10), fn(a) {
    let reg = mv_register.new(rid("A")) |> mv_register.set(a)
    let sorted_merged =
      list.sort(mv_register.value(mv_register.merge(reg, reg)), int.compare)
    let sorted_original = list.sort(mv_register.value(reg), int.compare)
    sorted_merged |> expect.to_equal(sorted_original)
    Nil
  })
}

// ---------------------------------------------------------------------------
// Delta-state property tests.
// ---------------------------------------------------------------------------

pub fn lww_register_delta_correctness__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(ts1, ts2) = pair
      let r = lww_register.new("v0", ts1, rid("A"))
      let direct = lww_register.set(r, "v1", ts2)
      let #(_, delta) = lww_register.set_with_delta(r, "v1", ts2)
      lww_register.value(lww_register.merge(r, delta))
      |> expect.to_equal(lww_register.value(direct))
      Nil
    },
  )
}

pub fn lww_register_delta_sufficiency_on_remote__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(ts_local, ts_new, ts_remote) = triple
      let local = lww_register.new("local", ts_local, rid("A"))
      let local_after = lww_register.set(local, "new", ts_new)
      let #(_, delta) = lww_register.set_with_delta(local, "new", ts_new)
      let remote = lww_register.new("remote", ts_remote, rid("B"))
      lww_register.value(lww_register.merge(remote, delta))
      |> expect.to_equal(
        lww_register.value(lww_register.merge(remote, local_after)),
      )
      Nil
    },
  )
}

pub fn mv_register_delta_correctness__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(_n) {
    let r = mv_register.new(rid("A")) |> mv_register.set("v0")
    let direct = mv_register.set(r, "v1")
    let #(_, delta) = mv_register.set_with_delta(r, "v1")
    mv_register.value(mv_register.merge(r, delta))
    |> list.sort(string_compare)
    |> expect.to_equal(mv_register.value(direct) |> list.sort(string_compare))
    Nil
  })
}

pub fn mv_register_delta_supersedes_on_remote__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(_n) {
    // Local replica A has previously merged a write from B.
    let a = mv_register.new(rid("A")) |> mv_register.set("a-old")
    let b = mv_register.new(rid("B")) |> mv_register.set("b-old")
    let local = mv_register.merge(a, b)
    // A writes a new value: this should supersede both prior writes.
    let local_after = mv_register.set(local, "a-new")
    let #(_, delta) = mv_register.set_with_delta(local, "a-new")
    // Apply delta to a fresh remote that has only seen B's old write.
    let remote = mv_register.new(rid("C")) |> mv_register.merge(b)
    let merged_via_delta = mv_register.merge(remote, delta)
    let merged_via_full = mv_register.merge(remote, local_after)
    mv_register.value(merged_via_delta)
    |> list.sort(string_compare)
    |> expect.to_equal(
      mv_register.value(merged_via_full) |> list.sort(string_compare),
    )
    Nil
  })
}

pub fn mv_register_delta_idempotent_commutative__test() {
  qcheck.run(small_test_config(), qcheck.bounded_int(0, 100), fn(_n) {
    let s0 = mv_register.new(rid("A"))
    let #(s1, d1) = mv_register.set_with_delta(s0, "v1")
    let #(s2, d2) = mv_register.set_with_delta(s1, "v2")
    let #(_s3, d3) = mv_register.set_with_delta(s2, "v3")
    let fresh = mv_register.new(rid("B"))
    let merged =
      fresh
      |> mv_register.merge(d3)
      |> mv_register.merge(d1)
      |> mv_register.merge(d2)
      |> mv_register.merge(d1)
      |> mv_register.merge(d3)
    mv_register.value(merged) |> expect.to_equal(["v3"])
    Nil
  })
}

fn string_compare(a: String, b: String) -> order.Order {
  string.compare(a, b)
}
