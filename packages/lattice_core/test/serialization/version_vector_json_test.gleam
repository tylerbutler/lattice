import gleam/json
import lattice_core/replica_id
import lattice_core/version_vector

fn rid(id: String) {
  replica_id.new(id)
}

// Version Vector round-trip tests

pub fn version_vector_to_json_simple_test() {
  let vv = version_vector.new() |> version_vector.increment(rid("A"))
  let json_str = json.to_string(version_vector.to_json(vv))
  assert version_vector.from_json(json_str) == Ok(vv)
}

pub fn version_vector_explicit_zero_round_trip_test() {
  let encoded =
    "{\"type\":\"version_vector\",\"v\":1,\"state\":{\"clocks\":{\"A\":0}}}"
  let assert Ok(zero) = version_vector.from_json(encoded)
  let round_trip = json.to_string(version_vector.to_json(zero))
  assert version_vector.from_json(round_trip) == Ok(zero)
  assert !version_vector.is_empty(zero)
  assert version_vector.compare(version_vector.new(), zero)
    == version_vector.Equal
  assert version_vector.compare(zero, version_vector.new())
    == version_vector.Equal
}

pub fn version_vector_round_trip_multi_replica_test() {
  let vv =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))
    |> version_vector.increment(rid("C"))
  let json_str = json.to_string(version_vector.to_json(vv))
  assert version_vector.from_json(json_str) == Ok(vv)
}
