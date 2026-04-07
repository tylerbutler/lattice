import gleam/json
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_counters/pn_counter
import lattice_maps/crdt.{
  CrdtGCounter, CrdtGSet, CrdtLwwRegister, CrdtMvRegister, CrdtOrSet,
  CrdtPnCounter, CrdtTwoPSet, CrdtVersionVector, GCounterSpec, GSetSpec,
  LwwRegisterSpec, MvRegisterSpec, OrSetSpec, PnCounterSpec, TwoPSetSpec,
}
import lattice_registers/lww_register
import lattice_registers/mv_register
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import startest/expect

// --- default_crdt tests ---

pub fn default_crdt_g_counter_test() {
  crdt.default_crdt(GCounterSpec, "A")
  |> expect.to_equal(CrdtGCounter(g_counter.new("A")))
}

pub fn default_crdt_pn_counter_test() {
  crdt.default_crdt(PnCounterSpec, "A")
  |> expect.to_equal(CrdtPnCounter(pn_counter.new("A")))
}

pub fn default_crdt_lww_register_test() {
  crdt.default_crdt(LwwRegisterSpec, "A")
  |> expect.to_equal(CrdtLwwRegister(lww_register.new("", 0, "A")))
}

pub fn default_crdt_mv_register_test() {
  crdt.default_crdt(MvRegisterSpec, "A")
  |> expect.to_equal(CrdtMvRegister(mv_register.new("A")))
}

pub fn default_crdt_g_set_test() {
  crdt.default_crdt(GSetSpec, "A")
  |> expect.to_equal(CrdtGSet(g_set.new()))
}

pub fn default_crdt_two_p_set_test() {
  crdt.default_crdt(TwoPSetSpec, "A")
  |> expect.to_equal(CrdtTwoPSet(two_p_set.new()))
}

pub fn default_crdt_or_set_test() {
  crdt.default_crdt(OrSetSpec, "A")
  |> expect.to_equal(CrdtOrSet(or_set.new("A")))
}

// --- merge dispatch tests ---

pub fn merge_g_counter_dispatches_test() {
  let a = CrdtGCounter(g_counter.new("A") |> g_counter.increment(3))
  let b = CrdtGCounter(g_counter.new("B") |> g_counter.increment(5))
  let merged = crdt.merge(a, b)
  case merged {
    CrdtGCounter(c) -> g_counter.value(c) |> expect.to_equal(8)
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_pn_counter_dispatches_test() {
  let a = CrdtPnCounter(pn_counter.new("A") |> pn_counter.increment(3))
  let b = CrdtPnCounter(pn_counter.new("B") |> pn_counter.increment(7))
  let merged = crdt.merge(a, b)
  case merged {
    CrdtPnCounter(c) -> pn_counter.value(c) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_lww_register_dispatches_test() {
  let a = CrdtLwwRegister(lww_register.new("hello", 1, "A"))
  let b = CrdtLwwRegister(lww_register.new("world", 5, "B"))
  let merged = crdt.merge(a, b)
  case merged {
    CrdtLwwRegister(r) -> lww_register.value(r) |> expect.to_equal("world")
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_g_set_dispatches_test() {
  let a = CrdtGSet(g_set.new() |> g_set.add("x"))
  let b = CrdtGSet(g_set.new() |> g_set.add("y"))
  let merged = crdt.merge(a, b)
  case merged {
    CrdtGSet(s) -> {
      g_set.contains(s, "x") |> expect.to_be_true
      g_set.contains(s, "y") |> expect.to_be_true
    }
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_or_set_dispatches_test() {
  let a = CrdtOrSet(or_set.new("A") |> or_set.add("x"))
  let b = CrdtOrSet(or_set.new("B") |> or_set.add("y"))
  let merged = crdt.merge(a, b)
  case merged {
    CrdtOrSet(s) -> {
      or_set.contains(s, "x") |> expect.to_be_true
      or_set.contains(s, "y") |> expect.to_be_true
    }
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_version_vector_dispatches_test() {
  let a =
    CrdtVersionVector(version_vector.new() |> version_vector.increment("A"))
  let b =
    CrdtVersionVector(version_vector.new() |> version_vector.increment("B"))
  let merged = crdt.merge(a, b)
  case merged {
    CrdtVersionVector(vv) -> {
      version_vector.get(vv, "A") |> expect.to_equal(1)
      version_vector.get(vv, "B") |> expect.to_equal(1)
    }
    _ -> expect.to_be_true(False)
  }
}

pub fn merge_type_mismatch_returns_first_test() {
  let a = CrdtGCounter(g_counter.new("A"))
  let b = CrdtGSet(g_set.new())

  crdt.merge(a, b) |> expect.to_equal(a)
}

// --- to_json / from_json round-trip tests ---

pub fn to_json_from_json_g_counter_test() {
  let c = CrdtGCounter(g_counter.new("A") |> g_counter.increment(5))
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> expect.to_equal(Ok(c))
}

pub fn to_json_from_json_pn_counter_test() {
  let c = CrdtPnCounter(pn_counter.new("A") |> pn_counter.increment(3))
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> expect.to_equal(Ok(c))
}

pub fn to_json_from_json_lww_register_test() {
  let c = CrdtLwwRegister(lww_register.new("hello", 42, "A"))
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> expect.to_equal(Ok(c))
}

pub fn to_json_from_json_g_set_test() {
  let c = CrdtGSet(g_set.new() |> g_set.add("a") |> g_set.add("b"))
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> expect.to_equal(Ok(c))
}

pub fn to_json_from_json_two_p_set_test() {
  let c =
    CrdtTwoPSet(
      two_p_set.new()
      |> two_p_set.add("a")
      |> two_p_set.add("b")
      |> two_p_set.remove("a"),
    )
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> expect.to_equal(Ok(c))
}

pub fn to_json_from_json_or_set_test() {
  let c =
    CrdtOrSet(
      or_set.new("A")
      |> or_set.add("x"),
    )
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> expect.to_equal(Ok(c))
}

pub fn to_json_from_json_version_vector_test() {
  let c =
    CrdtVersionVector(
      version_vector.new()
      |> version_vector.increment("A")
      |> version_vector.increment("B"),
    )
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> expect.to_equal(Ok(c))
}

pub fn from_json_unknown_type_returns_error_test() {
  let json_str = "{\"type\": \"unknown_type\", \"v\": 1, \"state\": {}}"
  case crdt.from_json(json_str) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}
