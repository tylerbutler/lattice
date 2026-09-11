import gleam/json
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_counters/pn_counter

fn rid(id: String) {
  replica_id.new(id)
}

// G-Counter round-trip tests

pub fn g_counter_to_json_simple_test() {
  let assert Ok(counter) = g_counter.new(rid("A")) |> g_counter.increment(5)
  let json_str = json.to_string(g_counter.to_json(counter))
  assert g_counter.from_json(json_str) == Ok(counter)
}

pub fn g_counter_round_trip_multi_replica_test() {
  let assert Ok(a) = g_counter.new(rid("A")) |> g_counter.increment(3)
  let assert Ok(b) = g_counter.new(rid("B")) |> g_counter.increment(7)
  let merged = g_counter.merge(a, b)
  let json_str = json.to_string(g_counter.to_json(merged))
  assert g_counter.from_json(json_str) == Ok(merged)
}

pub fn g_counter_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"pn_counter\",\"v\":1,\"state\":{\"self_id\":\"A\",\"counts\":{\"A\":3}}}"
  let assert Error(_) = g_counter.from_json(payload)
}

pub fn g_counter_from_json_wrong_version_rejected_test() {
  let payload =
    "{\"type\":\"g_counter\",\"v\":2,\"state\":{\"self_id\":\"A\",\"counts\":{\"A\":3}}}"
  let assert Error(_) = g_counter.from_json(payload)
}

// PN-Counter round-trip tests

pub fn pn_counter_to_json_simple_test() {
  let assert Ok(counter) = pn_counter.new(rid("A")) |> pn_counter.increment(10)
  let json_str = json.to_string(pn_counter.to_json(counter))
  assert pn_counter.from_json(json_str) == Ok(counter)
}

pub fn pn_counter_round_trip_inc_dec_test() {
  let assert Ok(counter) =
    pn_counter.new(rid("A"))
    |> pn_counter.increment(10)
  let assert Ok(counter) = pn_counter.decrement(counter, 3)
  let json_str = json.to_string(pn_counter.to_json(counter))
  assert pn_counter.from_json(json_str) == Ok(counter)
}

pub fn pn_counter_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"g_counter\",\"v\":1,\"state\":{\"positive\":{\"self_id\":\"A\",\"counts\":{}},\"negative\":{\"self_id\":\"A\",\"counts\":{}}}}"
  let assert Error(_) = pn_counter.from_json(payload)
}
