import gleeunit
import gleeunit/should
import lattice/version_vector

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn new_returns_empty_test() {
  version_vector.new()
  |> version_vector.get("A")
  |> should.equal(0)
}

pub fn increment_increases_count_test() {
  version_vector.new()
  |> version_vector.increment("A")
  |> version_vector.get("A")
  |> should.equal(1)
}

pub fn get_returns_zero_for_missing_test() {
  version_vector.new()
  |> version_vector.get("A")
  |> should.equal(0)
}

pub fn compare_before_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A")

  version_vector.compare(a, b)
  |> should.equal(version_vector.Before)
}

pub fn compare_after_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A")

  version_vector.compare(b, a)
  |> should.equal(version_vector.After)
}

pub fn compare_equal_test() {
  let a = version_vector.new() |> version_vector.increment("A")

  version_vector.compare(a, a)
  |> should.equal(version_vector.Equal)
}

pub fn compare_concurrent_test() {
  // Two vectors with different replicas: A:1 vs B:1 are concurrent
  let vv1 = version_vector.new() |> version_vector.increment("A")
  let vv2 = version_vector.new() |> version_vector.increment("B")

  version_vector.compare(vv1, vv2)
  |> should.equal(version_vector.Concurrent)
}

pub fn compare_before_multiple_keys_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A") |> version_vector.increment("B")

  version_vector.compare(a, b)
  |> should.equal(version_vector.Before)
}

pub fn merge_takes_max_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A")

  version_vector.merge(a, b)
  |> version_vector.get("A")
  |> should.equal(2)
}

pub fn merge_multiple_keys_test() {
  let a =
    version_vector.new()
    |> version_vector.increment("A")
    |> version_vector.increment("B")
  let b = a |> version_vector.increment("A")

  // Result should have A:2, B:1
  let merged = version_vector.merge(a, b)

  merged
  |> version_vector.get("A")
  |> should.equal(2)

  merged
  |> version_vector.get("B")
  |> should.equal(1)
}
