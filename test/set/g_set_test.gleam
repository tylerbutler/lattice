import gleam/set
import lattice/g_set
import startest/expect

pub fn new_creates_empty_set_test() {
  g_set.new()
  |> g_set.value
  |> expect.to_equal(set.new())
}

pub fn new_contains_returns_false_test() {
  g_set.new()
  |> g_set.contains("a")
  |> expect.to_be_false
}

pub fn add_then_contains_returns_true_test() {
  g_set.new()
  |> g_set.add("hello")
  |> g_set.contains("hello")
  |> expect.to_be_true
}

pub fn add_multiple_elements_test() {
  let s =
    g_set.new()
    |> g_set.add("a")
    |> g_set.add("b")
    |> g_set.add("c")

  s
  |> g_set.contains("a")
  |> expect.to_be_true

  s
  |> g_set.contains("b")
  |> expect.to_be_true

  s
  |> g_set.contains("c")
  |> expect.to_be_true
}

pub fn add_duplicate_is_idempotent_test() {
  let s =
    g_set.new()
    |> g_set.add("hello")
    |> g_set.add("hello")

  s
  |> g_set.value
  |> expect.to_equal(set.from_list(["hello"]))
}

pub fn value_returns_all_elements_test() {
  g_set.new()
  |> g_set.add("a")
  |> g_set.add("b")
  |> g_set.value
  |> expect.to_equal(set.from_list(["a", "b"]))
}

pub fn merge_is_union_test() {
  let s1 =
    g_set.new()
    |> g_set.add("a")
    |> g_set.add("b")

  let s2 =
    g_set.new()
    |> g_set.add("b")
    |> g_set.add("c")

  g_set.merge(s1, s2)
  |> g_set.value
  |> expect.to_equal(set.from_list(["a", "b", "c"]))
}

pub fn merge_empty_left_test() {
  let s =
    g_set.new()
    |> g_set.add("x")

  g_set.merge(g_set.new(), s)
  |> g_set.value
  |> expect.to_equal(set.from_list(["x"]))
}

pub fn merge_empty_right_test() {
  let s =
    g_set.new()
    |> g_set.add("x")

  g_set.merge(s, g_set.new())
  |> g_set.value
  |> expect.to_equal(set.from_list(["x"]))
}
