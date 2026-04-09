import lattice_core/replica_id
import lattice_core/version_vector
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_returns_empty_test() {
  version_vector.new()
  |> version_vector.get(rid("A"))
  |> expect.to_equal(0)
}

pub fn increment_increases_count_test() {
  version_vector.new()
  |> version_vector.increment(rid("A"))
  |> version_vector.get(rid("A"))
  |> expect.to_equal(1)
}

pub fn get_returns_zero_for_missing_test() {
  version_vector.new()
  |> version_vector.get(rid("A"))
  |> expect.to_equal(0)
}

pub fn compare_before_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = a |> version_vector.increment(rid("A"))

  version_vector.compare(a, b)
  |> expect.to_equal(version_vector.Before)
}

pub fn compare_after_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = a |> version_vector.increment(rid("A"))

  version_vector.compare(b, a)
  |> expect.to_equal(version_vector.After)
}

pub fn compare_equal_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))

  version_vector.compare(a, a)
  |> expect.to_equal(version_vector.Equal)
}

pub fn compare_concurrent_test() {
  let vv1 = version_vector.new() |> version_vector.increment(rid("A"))
  let vv2 = version_vector.new() |> version_vector.increment(rid("B"))

  version_vector.compare(vv1, vv2)
  |> expect.to_equal(version_vector.Concurrent)
}

pub fn compare_before_multiple_keys_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b =
    a
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))

  version_vector.compare(a, b)
  |> expect.to_equal(version_vector.Before)
}

pub fn merge_takes_max_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = a |> version_vector.increment(rid("A"))

  version_vector.merge(a, b)
  |> version_vector.get(rid("A"))
  |> expect.to_equal(2)
}

pub fn merge_multiple_keys_test() {
  let a =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))
  let b = a |> version_vector.increment(rid("A"))

  let merged = version_vector.merge(a, b)

  merged
  |> version_vector.get(rid("A"))
  |> expect.to_equal(2)

  merged
  |> version_vector.get(rid("B"))
  |> expect.to_equal(1)
}

// --- dominates ---

pub fn dominates_equal_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  version_vector.dominates(a, a) |> expect.to_be_true()
}

pub fn dominates_after_test() {
  let a =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
  let b = version_vector.new() |> version_vector.increment(rid("A"))
  version_vector.dominates(a, b) |> expect.to_be_true()
}

pub fn dominates_before_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
  version_vector.dominates(a, b) |> expect.to_be_false()
}

pub fn dominates_concurrent_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = version_vector.new() |> version_vector.increment(rid("B"))
  version_vector.dominates(a, b) |> expect.to_be_false()
}

pub fn dominates_empty_dominates_empty_test() {
  version_vector.dominates(version_vector.new(), version_vector.new())
  |> expect.to_be_true()
}

pub fn dominates_nonempty_dominates_empty_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  version_vector.dominates(a, version_vector.new()) |> expect.to_be_true()
}

pub fn dominates_empty_does_not_dominate_nonempty_test() {
  let b = version_vector.new() |> version_vector.increment(rid("A"))
  version_vector.dominates(version_vector.new(), b) |> expect.to_be_false()
}

// --- is_empty ---

pub fn is_empty_new_test() {
  version_vector.new() |> version_vector.is_empty() |> expect.to_be_true()
}

pub fn is_empty_incremented_test() {
  version_vector.new()
  |> version_vector.increment(rid("A"))
  |> version_vector.is_empty()
  |> expect.to_be_false()
}
