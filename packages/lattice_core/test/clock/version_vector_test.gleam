import gleam/dict
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_returns_empty_test() {
  assert version_vector.new()
    |> version_vector.get(rid("A"))
    == 0
}

pub fn increment_increases_count_test() {
  assert version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.get(rid("A"))
    == 1
}

pub fn get_returns_zero_for_missing_test() {
  assert version_vector.new()
    |> version_vector.get(rid("A"))
    == 0
}

pub fn compare_before_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = a |> version_vector.increment(rid("A"))

  assert version_vector.compare(a, b) == version_vector.Before
}

pub fn compare_after_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = a |> version_vector.increment(rid("A"))

  assert version_vector.compare(b, a) == version_vector.After
}

pub fn compare_equal_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))

  assert version_vector.compare(a, a) == version_vector.Equal
}

pub fn compare_concurrent_test() {
  let vv1 = version_vector.new() |> version_vector.increment(rid("A"))
  let vv2 = version_vector.new() |> version_vector.increment(rid("B"))

  assert version_vector.compare(vv1, vv2) == version_vector.Concurrent
}

pub fn compare_explicit_zero_clocks_test() {
  let empty = version_vector.new()
  let zero_a = version_vector.from_dict(dict.from_list([#(rid("A"), 0)]))
  let zero_b = version_vector.from_dict(dict.from_list([#(rid("B"), 0)]))

  list.each([#(empty, zero_a), #(zero_a, zero_b)], fn(pair) {
    let #(a, b) = pair
    assert version_vector.compare(a, b) == version_vector.Equal
    assert version_vector.compare(b, a) == version_vector.Equal
    assert version_vector.dominates(a, b)
    assert version_vector.dominates(b, a)
  })
}

pub fn compare_positive_clock_with_disjoint_zero_test() {
  let positive = version_vector.new() |> version_vector.increment(rid("A"))
  let zero = version_vector.from_dict(dict.from_list([#(rid("B"), 0)]))

  assert version_vector.compare(positive, zero) == version_vector.After
  assert version_vector.compare(zero, positive) == version_vector.Before
  assert version_vector.dominates(positive, zero)
  assert !version_vector.dominates(zero, positive)
}

pub fn compare_merge_consistency_with_zero_clocks_test() {
  let vectors = [
    version_vector.new(),
    version_vector.from_dict(dict.from_list([#(rid("A"), 0)])),
    version_vector.from_dict(dict.from_list([#(rid("B"), 0)])),
    version_vector.new() |> version_vector.increment(rid("A")),
    version_vector.from_dict(
      dict.from_list([
        #(rid("A"), 0),
        #(rid("B"), 1),
      ]),
    ),
  ]

  list.each(vectors, fn(a) {
    list.each(vectors, fn(b) {
      let merged = version_vector.merge(a, b)
      assert version_vector.dominates(merged, a)
      assert version_vector.dominates(merged, b)
      assert version_vector.compare(merged, version_vector.merge(b, a))
        == version_vector.Equal
      assert version_vector.dominates(a, b)
        == { version_vector.compare(a, merged) == version_vector.Equal }
    })
  })
}

pub fn compare_before_multiple_keys_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b =
    a
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))

  assert version_vector.compare(a, b) == version_vector.Before
}

pub fn merge_takes_max_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = a |> version_vector.increment(rid("A"))

  assert version_vector.merge(a, b)
    |> version_vector.get(rid("A"))
    == 2
}

pub fn merge_multiple_keys_test() {
  let a =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("B"))
  let b = a |> version_vector.increment(rid("A"))

  let merged = version_vector.merge(a, b)

  assert merged
    |> version_vector.get(rid("A"))
    == 2

  assert merged
    |> version_vector.get(rid("B"))
    == 1
}

// --- dominates ---

pub fn dominates_equal_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  assert version_vector.dominates(a, a)
}

pub fn dominates_after_test() {
  let a =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
  let b = version_vector.new() |> version_vector.increment(rid("A"))
  assert version_vector.dominates(a, b)
}

pub fn dominates_before_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b =
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.increment(rid("A"))
  assert !version_vector.dominates(a, b)
}

pub fn dominates_concurrent_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  let b = version_vector.new() |> version_vector.increment(rid("B"))
  assert !version_vector.dominates(a, b)
}

pub fn dominates_empty_dominates_empty_test() {
  assert version_vector.dominates(version_vector.new(), version_vector.new())
}

pub fn dominates_nonempty_dominates_empty_test() {
  let a = version_vector.new() |> version_vector.increment(rid("A"))
  assert version_vector.dominates(a, version_vector.new())
}

pub fn dominates_empty_does_not_dominate_nonempty_test() {
  let b = version_vector.new() |> version_vector.increment(rid("A"))
  assert !version_vector.dominates(version_vector.new(), b)
}

// --- is_empty ---

pub fn is_empty_new_test() {
  assert version_vector.new() |> version_vector.is_empty()
}

pub fn is_empty_incremented_test() {
  assert !{
    version_vector.new()
    |> version_vector.increment(rid("A"))
    |> version_vector.is_empty()
  }
}
