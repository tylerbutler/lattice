import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_registers/lww_register
import lattice_registers/mv_register
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// LWW-Register round-trip tests

pub fn lww_register_to_json_simple_test() {
  let reg = lww_register.new("hello", 42, rid("test-replica"))
  let json_str = json.to_string(lww_register.to_json(reg))
  lww_register.from_json(json_str)
  |> expect.to_equal(Ok(reg))
}

pub fn lww_register_round_trip_updated_test() {
  let reg =
    lww_register.new("initial", 1, rid("test-replica"))
    |> lww_register.set("updated", 100)
  let json_str = json.to_string(lww_register.to_json(reg))
  lww_register.from_json(json_str)
  |> expect.to_equal(Ok(reg))
}

pub fn lww_register_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"mv_register\",\"v\":2,\"state\":{\"value\":\"hello\",\"timestamp\":42,\"replica_id\":\"test\"}}"
  case lww_register.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn lww_register_from_json_wrong_version_rejected_test() {
  let payload =
    "{\"type\":\"lww_register\",\"v\":99,\"state\":{\"value\":\"hello\",\"timestamp\":42,\"replica_id\":\"test\"}}"
  case lww_register.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn lww_register_from_json_v1_compat_test() {
  let payload =
    "{\"type\":\"lww_register\",\"v\":1,\"state\":{\"value\":\"hello\",\"timestamp\":42}}"
  case lww_register.from_json(payload) {
    Ok(reg) -> {
      lww_register.value(reg)
      |> expect.to_equal("hello")
    }
    Error(_) -> expect.to_be_true(False)
  }
}

// MV-Register round-trip tests

pub fn mv_register_to_json_simple_test() {
  let reg = mv_register.new(rid("A")) |> mv_register.set("hello")
  let json_str = json.to_string(mv_register.to_json(reg))
  let decoded = mv_register.from_json(json_str)
  case decoded {
    Ok(d) ->
      list.sort(mv_register.value(d), string.compare)
      |> expect.to_equal(list.sort(mv_register.value(reg), string.compare))
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn mv_register_round_trip_concurrent_test() {
  // Simulate two concurrent writes from different replicas
  let a = mv_register.new(rid("A")) |> mv_register.set("from_a")
  let b = mv_register.new(rid("B")) |> mv_register.set("from_b")
  let merged = mv_register.merge(a, b)
  let json_str = json.to_string(mv_register.to_json(merged))
  let decoded = mv_register.from_json(json_str)
  case decoded {
    Ok(d) ->
      list.sort(mv_register.value(d), string.compare)
      |> expect.to_equal(list.sort(mv_register.value(merged), string.compare))
    Error(_) -> expect.to_be_true(False)
  }
}
