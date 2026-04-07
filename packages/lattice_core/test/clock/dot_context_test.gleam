import lattice_core/dot_context.{Dot}
import lattice_core/replica_id
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_creates_empty_context_test() {
  dot_context.new()
  |> dot_context.contains_dots([])
  |> expect.to_be_true()
}

pub fn add_dot_inserts_dot_test() {
  dot_context.new()
  |> dot_context.add_dot(rid("A"), 1)
  |> dot_context.contains_dots([Dot(rid("A"), 1)])
  |> expect.to_be_true()
}

pub fn add_dot_idempotent_test() {
  dot_context.new()
  |> dot_context.add_dot(rid("A"), 1)
  |> dot_context.add_dot(rid("A"), 1)
  |> dot_context.contains_dots([Dot(rid("A"), 1)])
  |> expect.to_be_true()
}

pub fn multiple_replicas_coexist_test() {
  let ctx =
    dot_context.new()
    |> dot_context.add_dot(rid("A"), 1)
    |> dot_context.add_dot(rid("B"), 2)

  ctx
  |> dot_context.contains_dots([Dot(rid("A"), 1), Dot(rid("B"), 2)])
  |> expect.to_be_true()
}

pub fn remove_dots_removes_specific_dot_test() {
  dot_context.new()
  |> dot_context.add_dot(rid("A"), 1)
  |> dot_context.remove_dots([Dot(rid("A"), 1)])
  |> dot_context.contains_dots([Dot(rid("A"), 1)])
  |> expect.to_be_false()
}

pub fn remove_dots_noop_for_missing_test() {
  dot_context.new()
  |> dot_context.add_dot(rid("A"), 1)
  |> dot_context.remove_dots([Dot(rid("B"), 99)])
  |> dot_context.contains_dots([Dot(rid("A"), 1)])
  |> expect.to_be_true()
}

pub fn contains_dots_empty_list_is_true_test() {
  dot_context.new()
  |> dot_context.contains_dots([])
  |> expect.to_be_true()
}

pub fn contains_dots_partial_match_is_false_test() {
  dot_context.new()
  |> dot_context.add_dot(rid("A"), 1)
  |> dot_context.contains_dots([Dot(rid("A"), 1), Dot(rid("B"), 2)])
  |> expect.to_be_false()
}
