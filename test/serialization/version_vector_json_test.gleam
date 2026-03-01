import gleam/json
import lattice/version_vector
import startest/expect

// Version Vector round-trip tests

pub fn version_vector_to_json_simple_test() {
  let vv = version_vector.new() |> version_vector.increment("A")
  let json_str = json.to_string(version_vector.to_json(vv))
  version_vector.from_json(json_str)
  |> expect.to_equal(Ok(vv))
}

pub fn version_vector_round_trip_multi_replica_test() {
  let vv =
    version_vector.new()
    |> version_vector.increment("A")
    |> version_vector.increment("A")
    |> version_vector.increment("B")
    |> version_vector.increment("C")
  let json_str = json.to_string(version_vector.to_json(vv))
  version_vector.from_json(json_str)
  |> expect.to_equal(Ok(vv))
}
