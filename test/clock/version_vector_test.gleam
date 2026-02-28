import lattice/version_vector
import startest/expect

pub fn new_returns_empty_test() {
  version_vector.new()
  |> version_vector.get("A")
  |> expect.to_equal(0)
}

pub fn increment_increases_count_test() {
  version_vector.new()
  |> version_vector.increment("A")
  |> version_vector.get("A")
  |> expect.to_equal(1)
}

pub fn get_returns_zero_for_missing_test() {
  version_vector.new()
  |> version_vector.get("A")
  |> expect.to_equal(0)
}

pub fn compare_before_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A")

  version_vector.compare(a, b)
  |> expect.to_equal(version_vector.Before)
}

pub fn compare_after_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A")

  version_vector.compare(b, a)
  |> expect.to_equal(version_vector.After)
}

pub fn compare_equal_test() {
  let a = version_vector.new() |> version_vector.increment("A")

  version_vector.compare(a, a)
  |> expect.to_equal(version_vector.Equal)
}

pub fn compare_concurrent_test() {
  let vv1 = version_vector.new() |> version_vector.increment("A")
  let vv2 = version_vector.new() |> version_vector.increment("B")

  version_vector.compare(vv1, vv2)
  |> expect.to_equal(version_vector.Concurrent)
}

pub fn compare_before_multiple_keys_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A") |> version_vector.increment("B")

  version_vector.compare(a, b)
  |> expect.to_equal(version_vector.Before)
}

pub fn merge_takes_max_test() {
  let a = version_vector.new() |> version_vector.increment("A")
  let b = a |> version_vector.increment("A")

  version_vector.merge(a, b)
  |> version_vector.get("A")
  |> expect.to_equal(2)
}

pub fn merge_multiple_keys_test() {
  let a =
    version_vector.new()
    |> version_vector.increment("A")
    |> version_vector.increment("B")
  let b = a |> version_vector.increment("A")

  let merged = version_vector.merge(a, b)

  merged
  |> version_vector.get("A")
  |> expect.to_equal(2)

  merged
  |> version_vector.get("B")
  |> expect.to_equal(1)
}
