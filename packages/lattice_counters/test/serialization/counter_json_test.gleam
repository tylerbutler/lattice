import gleam/json
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_counters/pn_counter
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// G-Counter round-trip tests

pub fn g_counter_to_json_simple_test() {
  let counter = g_counter.new(rid("A")) |> g_counter.increment(5)
  let json_str = json.to_string(g_counter.to_json(counter))
  g_counter.from_json(json_str)
  |> expect.to_equal(Ok(counter))
}

pub fn g_counter_round_trip_multi_replica_test() {
  let a = g_counter.new(rid("A")) |> g_counter.increment(3)
  let b = g_counter.new(rid("B")) |> g_counter.increment(7)
  let merged = g_counter.merge(a, b)
  let json_str = json.to_string(g_counter.to_json(merged))
  g_counter.from_json(json_str)
  |> expect.to_equal(Ok(merged))
}

pub fn g_counter_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"pn_counter\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counts\":{\"A\":3}}}"
  case g_counter.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn g_counter_from_json_wrong_version_rejected_test() {
  let payload =
    "{\"type\":\"g_counter\",\"v\":2,\"state\":{\"self_id\":\"A\",\"counts\":{\"A\":3}}}"
  case g_counter.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

// PN-Counter round-trip tests

pub fn pn_counter_to_json_simple_test() {
  let counter = pn_counter.new(rid("A")) |> pn_counter.increment(10)
  let json_str = json.to_string(pn_counter.to_json(counter))
  pn_counter.from_json(json_str)
  |> expect.to_equal(Ok(counter))
}

pub fn pn_counter_round_trip_inc_dec_test() {
  let counter =
    pn_counter.new(rid("A"))
    |> pn_counter.increment(10)
    |> pn_counter.decrement(3)
  let json_str = json.to_string(pn_counter.to_json(counter))
  pn_counter.from_json(json_str)
  |> expect.to_equal(Ok(counter))
}

pub fn pn_counter_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"g_counter\",\"v\":1,\"state\":{\"positive\":{\"self_id\":\"A\",\"counts\":{}},\"negative\":{\"self_id\":\"A\",\"counts\":{}}}}"
  case pn_counter.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}
