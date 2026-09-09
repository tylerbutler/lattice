import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_fugue/sequence
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

fn round_trip(state: sequence.Sequence(String)) {
  state
  |> sequence.to_json(json.string)
  |> json.to_string()
  |> sequence.from_json(decode.string)
}

fn metadata(state: sequence.Sequence(String)) {
  let node_id = {
    use id <- decode.field("id", {
      use replica <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      decode.success(#(replica, counter))
    })
    decode.success(id)
  }
  state
  |> sequence.to_json(json.string)
  |> json.to_string()
  |> json.parse(using: {
    use metadata <- decode.field("state", {
      use replica <- decode.field("self_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use ids <- decode.field("nodes", decode.list(node_id))
      decode.success(#(replica, counter, ids))
    })
    decode.success(metadata)
  })
}

pub fn canonical_merge_selects_local_identity_for_states_and_deltas_test() {
  let assert Ok(base) = sequence.insert(sequence.new(rid("A")), 0, "a")
  let assert Ok(anchor) = sequence.anchor_at(base, 1, sequence.After)
  let assert Ok(#(remote, delta)) =
    sequence.merge(base, sequence.new(rid("B")), rid("B"))
    |> sequence.insert_with_delta(1, "b")

  list.each([remote, delta], fn(incoming) {
    let assert Ok(decoded) = round_trip(incoming)
    expect.to_equal(sequence.replica_id(decoded), rid("B"))
    let forward = sequence.merge(base, decoded, rid("A"))
    let backward = sequence.merge(decoded, base, rid("A"))
    expect.to_equal(forward, backward)
    expect.to_equal(sequence.merge_as(base, decoded, rid("A")), forward)
    expect.to_equal(sequence.merge_as(decoded, base, rid("A")), forward)

    list.each([forward, backward], fn(received) {
      expect.to_equal(sequence.replica_id(received), rid("A"))
      sequence.resolve(received, anchor) |> expect.to_equal(Ok(1))
      let assert Ok(#(local, local_delta)) =
        sequence.insert_with_delta(received, 2, "x")
      let assert Ok(#(remote, remote_delta)) =
        sequence.insert_with_delta(remote, 2, "c")
      metadata(local_delta) |> expect.to_equal(Ok(#("A", 3, [#("A", 3)])))
      metadata(remote_delta) |> expect.to_equal(Ok(#("B", 3, [#("B", 3)])))
      let merged = sequence.merge(local, remote, rid("A"))
      merged |> expect.to_equal(sequence.merge(remote, local, rid("A")))
      sequence.length(merged) |> expect.to_equal(4)
      let values = sequence.values(merged)
      expect.to_be_true(
        list.contains(values, "x") && list.contains(values, "c"),
      )

      // Duplicate delivery cannot roll back either the counter or the content.
      let duplicate = sequence.merge(decoded, merged, rid("A"))
      duplicate |> expect.to_equal(merged)
      let assert Ok(#(_, next_local_delta)) =
        sequence.insert_with_delta(duplicate, 4, "y")
      let assert Ok(#(_, next_remote_delta)) =
        sequence.merge(remote, local, rid("B"))
        |> sequence.insert_with_delta(4, "z")
      metadata(next_local_delta) |> expect.to_equal(Ok(#("A", 4, [#("A", 4)])))
      metadata(next_remote_delta) |> expect.to_equal(Ok(#("B", 4, [#("B", 4)])))
    })
  })
}

pub fn merge_can_select_a_new_writer_identity_test() {
  let assert Ok(a) = sequence.insert(sequence.new(rid("A")), 0, "a")
  let assert Ok(b) = sequence.insert(sequence.new(rid("B")), 0, "b")
  let merged = sequence.merge(a, b, rid("C"))
  sequence.replica_id(merged) |> expect.to_equal(rid("C"))
  merged |> expect.to_equal(sequence.merge(b, a, rid("C")))
  let assert Ok(#(_, delta)) = sequence.insert_with_delta(merged, 2, "c")
  metadata(delta) |> expect.to_equal(Ok(#("C", 2, [#("C", 2)])))
}

pub fn serialized_delete_and_empty_deltas_preserve_state_and_anchors_test() {
  let assert Ok(#(base, insert_delta)) =
    sequence.insert_with_delta(sequence.new(rid("A")), 0, "a")
  let assert Ok(anchor) = sequence.anchor_at(base, 1, sequence.After)
  let assert Ok(#(deleted, delete_delta)) = sequence.delete_with_delta(base, 0)
  let assert Ok(delete_delta) = round_trip(delete_delta)
  list.each(
    [
      sequence.merge(base, delete_delta, rid("A")),
      sequence.merge(delete_delta, base, rid("A")),
    ],
    fn(received) {
      received |> expect.to_equal(deleted)
      sequence.resolve(received, anchor) |> expect.to_equal(Ok(0))
      sequence.merge(delete_delta, received, rid("A"))
      |> expect.to_equal(deleted)
      sequence.merge(insert_delta, received, rid("A"))
      |> expect.to_equal(deleted)
      let assert Ok(empty) = round_trip(sequence.empty_delta(received))
      empty |> expect.to_equal(sequence.new(rid("A")))
      sequence.merge(empty, received, rid("A")) |> expect.to_equal(deleted)
      sequence.merge(received, empty, rid("A")) |> expect.to_equal(deleted)
      let assert Ok(#(_, next_delta)) =
        sequence.insert_with_delta(received, 0, "b")
      metadata(next_delta) |> expect.to_equal(Ok(#("A", 3, [#("A", 3)])))
    },
  )
}
