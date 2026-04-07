import gleam/json
import lattice_core/replica_id
import lattice_core/version_vector
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// Version Vector round-trip tests

pub fn version_vector_to_json_simple_test() {
  let vv = version_vector.new() |> version_vector.increment(rid("A"))
  let json_str = json.to_string(version_vector.to_json(vv))
  version_vector.from_json(json_str)
  |> expect.to_equal(Ok(vv))
}

pub fn version_vector_round_trip_multi_replica_test() {
  let vv =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))
    |> version_vector.increment(rid("C"))
  let json_str = json.to_string(version_vector.to_json(vv))
  version_vector.from_json(json_str)
  |> expect.to_equal(Ok(vv))
}
