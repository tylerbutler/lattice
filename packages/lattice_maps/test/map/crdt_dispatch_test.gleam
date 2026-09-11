import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
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

fn rid(id: String) {
  replica_id.new(id)
}

// --- default_crdt tests ---

pub fn default_crdt_g_counter_test() {
  crdt.default_crdt(GCounterSpec, rid("A"))
  |> fn(assertion_actual) {
    let assert True = assertion_actual == CrdtGCounter(g_counter.new(rid("A")))
  }
}

pub fn default_crdt_pn_counter_test() {
  crdt.default_crdt(PnCounterSpec, rid("A"))
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == CrdtPnCounter(pn_counter.new(rid("A")))
  }
}

pub fn default_crdt_lww_register_test() {
  crdt.default_crdt(LwwRegisterSpec(""), rid("A"))
  |> fn(actual) {
    let assert True =
      actual == CrdtLwwRegister(lww_register.new("", 0, rid("A")))
  }
}

pub fn default_crdt_mv_register_test() {
  crdt.default_crdt(MvRegisterSpec, rid("A"))
  |> fn(assertion_actual) {
    let assert True =
      assertion_actual == CrdtMvRegister(mv_register.new(rid("A")))
  }
}

pub fn default_crdt_g_set_test() {
  crdt.default_crdt(GSetSpec, rid("A"))
  |> fn(assertion_actual) {
    let assert True = assertion_actual == CrdtGSet(g_set.new())
  }
}

pub fn default_crdt_two_p_set_test() {
  crdt.default_crdt(TwoPSetSpec, rid("A"))
  |> fn(assertion_actual) {
    let assert True = assertion_actual == CrdtTwoPSet(two_p_set.new())
  }
}

pub fn default_crdt_or_set_test() {
  crdt.default_crdt(OrSetSpec, rid("A"))
  |> fn(assertion_actual) {
    let assert True = assertion_actual == CrdtOrSet(or_set.new(rid("A")))
  }
}

// --- merge dispatch tests ---

pub fn merge_g_counter_dispatches_test() {
  let assert Ok(a) = g_counter.new(rid("A")) |> g_counter.increment(3)
  let assert Ok(b) = g_counter.new(rid("B")) |> g_counter.increment(5)
  let a = CrdtGCounter(a)
  let b = CrdtGCounter(b)
  let assert Ok(merged) = crdt.merge(a, b, rid("A"))
  case merged {
    CrdtGCounter(c) ->
      g_counter.value(c)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 8
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn merge_pn_counter_dispatches_test() {
  let assert Ok(a) = pn_counter.new(rid("A")) |> pn_counter.increment(3)
  let assert Ok(b) = pn_counter.new(rid("B")) |> pn_counter.increment(7)
  let a = CrdtPnCounter(a)
  let b = CrdtPnCounter(b)
  let assert Ok(merged) = crdt.merge(a, b, rid("A"))
  case merged {
    CrdtPnCounter(c) ->
      pn_counter.value(c)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 10
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn merge_lww_register_dispatches_test() {
  let a = CrdtLwwRegister(lww_register.new("hello", 1, rid("A")))
  let b = CrdtLwwRegister(lww_register.new("world", 5, rid("B")))
  let assert Ok(merged) = crdt.merge(a, b, rid("A"))
  case merged {
    CrdtLwwRegister(r) ->
      lww_register.value(r)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == "world"
      }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn merge_lww_register_unicode_order_dispatch_test() {
  let bmp = CrdtLwwRegister(lww_register.new("bmp value", 5, rid("\u{e000}")))
  let supplementary =
    CrdtLwwRegister(lww_register.new("supplementary value", 5, rid("\u{10000}")))

  list.each(
    [
      crdt.merge(bmp, supplementary, rid("R")),
      crdt.merge(supplementary, bmp, rid("R")),
    ],
    fn(result) {
      let assert Ok(CrdtLwwRegister(merged)) = result
      lww_register.value(merged)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == "supplementary value"
      }
      lww_register.replica_id(merged)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == rid("\u{10000}")
      }
      lww_register.timestamp(merged)
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 5
      }
    },
  )
}

pub fn merge_g_set_dispatches_test() {
  let a = CrdtGSet(g_set.new() |> g_set.add("x"))
  let b = CrdtGSet(g_set.new() |> g_set.add("y"))
  let assert Ok(merged) = crdt.merge(a, b, rid("A"))
  case merged {
    CrdtGSet(s) -> {
      g_set.contains(s, "x")
      |> fn(value) {
        let assert True = value
      }
      g_set.contains(s, "y")
      |> fn(value) {
        let assert True = value
      }
    }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn merge_or_set_dispatches_test() {
  let a = CrdtOrSet(or_set.new(rid("A")) |> or_set.add("x"))
  let b = CrdtOrSet(or_set.new(rid("B")) |> or_set.add("y"))
  let assert Ok(merged) = crdt.merge(a, b, rid("A"))
  case merged {
    CrdtOrSet(s) -> {
      or_set.contains(s, "x")
      |> fn(value) {
        let assert True = value
      }
      or_set.contains(s, "y")
      |> fn(value) {
        let assert True = value
      }
    }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn merge_version_vector_dispatches_test() {
  let a =
    CrdtVersionVector(
      version_vector.new() |> version_vector.increment(rid("A")),
    )
  let b =
    CrdtVersionVector(
      version_vector.new() |> version_vector.increment(rid("B")),
    )
  let assert Ok(merged) = crdt.merge(a, b, rid("A"))
  case merged {
    CrdtVersionVector(vv) -> {
      version_vector.get(vv, rid("A"))
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 1
      }
      version_vector.get(vv, rid("B"))
      |> fn(assertion_actual) {
        let assert True = assertion_actual == 1
      }
    }
    _ -> {
      panic as "Unexpected test branch"
    }
  }
}

pub fn merge_type_mismatch_returns_error_test() {
  let a = CrdtGCounter(g_counter.new(rid("A")))
  let b = CrdtGSet(g_set.new())

  crdt.merge(a, b, rid("A"))
  |> fn(actual) {
    let assert True =
      actual == Error(crdt.TypeMismatch(expected: "g_counter", found: "g_set"))
  }
}

// --- to_json / from_json round-trip tests ---

pub fn to_json_from_json_g_counter_test() {
  let assert Ok(c) = g_counter.new(rid("A")) |> g_counter.increment(5)
  let c = CrdtGCounter(c)
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(c)
  }
}

pub fn to_json_from_json_pn_counter_test() {
  let assert Ok(c) = pn_counter.new(rid("A")) |> pn_counter.increment(3)
  let c = CrdtPnCounter(c)
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(c)
  }
}

pub fn to_json_from_json_lww_register_test() {
  let c = CrdtLwwRegister(lww_register.new("hello", 42, rid("A")))
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(c)
  }
}

pub fn from_json_lww_register_requires_v2_replica_id_test() {
  let input =
    "{\"type\":\"lww_register\",\"v\":2,\"state\":{\"value\":\"hello\",\"timestamp\":42}}"

  crdt.from_json(input)
  |> fn(actual) {
    let assert True =
      actual
      == Error(
        json.UnableToDecode([
          decode.DecodeError(expected: "Field", found: "Nothing", path: [
            "state",
            "replica_id",
          ]),
        ]),
      )
  }
}

pub fn to_json_from_json_g_set_test() {
  let c = CrdtGSet(g_set.new() |> g_set.add("a") |> g_set.add("b"))
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(c)
  }
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
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(c)
  }
}

pub fn to_json_from_json_or_set_test() {
  let c =
    CrdtOrSet(
      or_set.new(rid("A"))
      |> or_set.add("x"),
    )
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(c)
  }
}

pub fn to_json_from_json_version_vector_test() {
  let c =
    CrdtVersionVector(
      version_vector.new()
      |> version_vector.increment(rid("A"))
      |> version_vector.increment(rid("B")),
    )
  let json_str = json.to_string(crdt.to_json(c))
  crdt.from_json(json_str)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(c)
  }
}

pub fn from_json_unknown_type_returns_error_test() {
  let json_str = "{\"type\": \"unknown_type\", \"v\": 1, \"state\": {}}"
  case crdt.from_json(json_str) {
    Error(_) -> {
      Nil
    }
    Ok(_) -> {
      panic as "Unexpected test branch"
    }
  }
}
