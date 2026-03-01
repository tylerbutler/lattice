import gleam/json
import lattice/g_counter
import lattice/pn_counter
import startest/expect

// G-Counter round-trip tests

pub fn g_counter_to_json_simple_test() {
  let counter = g_counter.new("A") |> g_counter.increment(5)
  let json_str = json.to_string(g_counter.to_json(counter))
  g_counter.from_json(json_str)
  |> expect.to_equal(Ok(counter))
}

pub fn g_counter_round_trip_multi_replica_test() {
  let a = g_counter.new("A") |> g_counter.increment(3)
  let b = g_counter.new("B") |> g_counter.increment(7)
  let merged = g_counter.merge(a, b)
  let json_str = json.to_string(g_counter.to_json(merged))
  g_counter.from_json(json_str)
  |> expect.to_equal(Ok(merged))
}

// PN-Counter round-trip tests

pub fn pn_counter_to_json_simple_test() {
  let counter = pn_counter.new("A") |> pn_counter.increment(10)
  let json_str = json.to_string(pn_counter.to_json(counter))
  pn_counter.from_json(json_str)
  |> expect.to_equal(Ok(counter))
}

pub fn pn_counter_round_trip_inc_dec_test() {
  let counter =
    pn_counter.new("A")
    |> pn_counter.increment(10)
    |> pn_counter.decrement(3)
  let json_str = json.to_string(pn_counter.to_json(counter))
  pn_counter.from_json(json_str)
  |> expect.to_equal(Ok(counter))
}
