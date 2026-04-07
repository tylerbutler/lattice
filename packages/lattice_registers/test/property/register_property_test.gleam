import gleam/int
import gleam/list
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
