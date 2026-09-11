import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import lattice_core/replica_id
import lattice_fugue/sequence
import lattice_text_fugue/text
import qcheck

fn rid(id: String) {
  replica_id.new(id)
}

fn round_trip(state: text.Text) {
  state
  |> text.to_json()
  |> json.to_string()
  |> text.from_json()
}

fn metadata(state: text.Text) {
  let node_id = {
    use id <- decode.field("id", {
      use replica <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      decode.success(#(replica, counter))
    })
    decode.success(id)
  }
  state
  |> text.to_json()
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
  let assert Ok(base) = text.insert(text.new(rid("A")), 0, "a")
  let assert Ok(anchor) = text.anchor_at(base, 1, sequence.After)
  let assert Ok(#(remote, delta)) =
    text.merge(base, text.new(rid("B")), rid("B"))
    |> text.insert_with_delta(1, "b")

  list.each([remote, delta], fn(incoming) {
    let assert Ok(decoded) = round_trip(incoming)
    let forward = text.merge(base, decoded, rid("A"))
    let backward = text.merge(decoded, base, rid("A"))
    assert forward == backward
    assert text.merge_as(base, decoded, rid("A")) == forward
    assert text.merge_as(decoded, base, rid("A")) == forward

    list.each([forward, backward], fn(received) {
      text.resolve_anchor(received, anchor)
      |> fn(actual) {
        assert actual == Ok(1)
      }
      let assert Ok(#(local, local_delta)) =
        text.append_with_delta(received, "xy")
      let assert Ok(#(remote, remote_delta)) =
        text.append_with_delta(remote, "cd")
      let assert Ok(#(local_id, local_counter, local_ids)) =
        metadata(local_delta)
      let assert Ok(#(remote_id, remote_counter, remote_ids)) =
        metadata(remote_delta)
      assert #(local_id, local_counter) == #("A", 4)
      assert #(remote_id, remote_counter) == #("B", 4)
      assert list.all(local_ids, fn(id) { id.0 == "A" })
      assert list.all(remote_ids, fn(id) { id.0 == "B" })
      local_ids
      |> list.map(fn(id) { id.1 })
      |> list.sort(int.compare)
      |> fn(actual) {
        assert actual == [3, 4]
      }
      remote_ids
      |> list.map(fn(id) { id.1 })
      |> list.sort(int.compare)
      |> fn(actual) {
        assert actual == [3, 4]
      }
      let merged = text.merge(local, remote, rid("A"))
      merged
      |> fn(actual) {
        assert actual == text.merge(remote, local, rid("A"))
      }
      text.length(merged)
      |> fn(actual) {
        assert actual == 6
      }
      assert string.contains(text.value(merged), "xy")
      assert string.contains(text.value(merged), "cd")
      text.merge(decoded, merged, rid("A"))
      |> fn(actual) {
        assert actual == merged
      }
      let assert Ok(#(_, next_local_delta)) =
        text.append_with_delta(merged, "!")
      let assert Ok(#(_, next_remote_delta)) =
        text.merge(remote, local, rid("B")) |> text.append_with_delta("?")
      metadata(next_local_delta)
      |> fn(actual) {
        assert actual == Ok(#("A", 5, [#("A", 5)]))
      }
      metadata(next_remote_delta)
      |> fn(actual) {
        assert actual == Ok(#("B", 5, [#("B", 5)]))
      }
    })
  })
}

pub fn range_delta_folds_keep_the_editing_identity_test() {
  let assert Ok(remote) = text.insert(text.new(rid("B")), 0, "abcde")
  let base = text.merge(remote, text.new(rid("A")), rid("A"))
  let assert Ok(anchor) = text.anchor_at(base, 1, sequence.Before)
  let assert Ok(#(inserted, insert_delta)) =
    text.insert_with_delta(base, 1, "XY")
  let assert Ok(#(deleted, delete_delta)) =
    text.delete_range_with_delta(base, 1, 4)
  let assert Ok(#(replaced, replace_delta)) =
    text.replace_range_with_delta(base, 1, 4, "XY")
  let assert Ok(#(single_deleted, single_delta)) =
    text.delete_with_delta(base, 1)
  list.each(
    [
      #(inserted, insert_delta, "aXYbcde", 7, 3),
      #(deleted, delete_delta, "ae", 8, 1),
      #(replaced, replace_delta, "aXYe", 10, 3),
      #(single_deleted, single_delta, "acde", 6, 1),
    ],
    fn(edit) {
      let #(updated, delta, value, counter, anchor_index) = edit
      let assert Ok(decoded) = round_trip(delta)
      let assert Ok(#(id, actual_counter, _)) = metadata(decoded)
      assert #(id, actual_counter) == #("A", counter)
      text.value(updated)
      |> fn(actual) {
        assert actual == value
      }
      list.each(
        [
          text.merge(base, decoded, rid("A")),
          text.merge(decoded, base, rid("A")),
        ],
        fn(received) {
          received
          |> fn(actual) {
            assert actual == updated
          }
          text.resolve_anchor(received, anchor)
          |> fn(actual) {
            assert actual == Ok(anchor_index)
          }
          text.merge(decoded, received, rid("A"))
          |> fn(actual) {
            assert actual == updated
          }
          let assert Ok(#(_, next_delta)) =
            text.append_with_delta(received, "!")
          metadata(next_delta)
          |> fn(actual) {
            assert actual == Ok(#("A", counter + 1, [#("A", counter + 1)]))
          }
        },
      )
    },
  )
  // Deletion deltas retain the target's B node IDs, not the editor's A identity.
  let assert Ok(#(_, _, deleted_ids)) = metadata(delete_delta)
  assert list.all(deleted_ids, fn(id) { id.0 == "B" })
  deleted_ids
  |> list.map(fn(id) { id.1 })
  |> list.sort(int.compare)
  |> fn(actual) {
    assert actual == [2, 3, 4]
  }
  let assert Ok(#(_, _, replacement_ids)) = metadata(replace_delta)
  replacement_ids
  |> list.filter(fn(id) { id.0 == "A" })
  |> list.map(fn(id) { id.1 })
  |> list.sort(int.compare)
  |> fn(actual) {
    assert actual == [9, 10]
  }
}

pub fn serialized_empty_deltas_are_neutral_test() {
  let assert Ok(remote) = text.insert(text.new(rid("B")), 0, "abc")
  let base = text.merge(remote, text.new(rid("A")), rid("A"))
  let assert Ok(deleted) = text.delete_range(base, 0, 3)
  list.each([text.new(rid("A")), base, deleted], fn(state) {
    let index = text.length(state)
    list.each(
      [
        text.insert_with_delta(state, index, ""),
        text.append_with_delta(state, ""),
      ],
      fn(operation) {
        let assert Ok(#(updated, delta)) = operation
        updated
        |> fn(actual) {
          assert actual == state
        }
        let assert Ok(delta) = round_trip(delta)
        delta
        |> fn(actual) {
          assert actual == text.new(rid("A"))
        }
        text.merge(delta, state, rid("A"))
        |> fn(actual) {
          assert actual == state
        }
        text.merge(state, delta, rid("A"))
        |> fn(actual) {
          assert actual == state
        }
      },
    )
    list.each(
      [
        text.delete_range_with_delta(state, index, index),
        text.replace_range_with_delta(state, index, index, ""),
      ],
      fn(operation) {
        let assert Ok(#(updated, delta)) = operation
        updated
        |> fn(actual) {
          assert actual == state
        }
        let assert Ok(delta) = round_trip(delta)
        delta
        |> fn(actual) {
          assert actual == text.new(rid("A"))
        }
        text.merge(delta, state, rid("A"))
        |> fn(actual) {
          assert actual == state
        }
        text.merge(state, delta, rid("A"))
        |> fn(actual) {
          assert actual == state
        }
      },
    )
  })
}

pub fn complete_state_merge_laws_with_fixed_identity_test() {
  qcheck.run(
    qcheck.config(test_count: 1000, max_retries: 3, seed: qcheck.seed(42)),
    qcheck.bounded_int(0, 100),
    fn(n) {
      let assert Ok(a) = text.insert(text.new(rid("A")), 0, int.to_string(n))
      let assert Ok(b) =
        text.insert(text.new(rid("B")), 0, "bc")
        |> result.try(text.append(_, int.to_string(n + 1)))
      let assert Ok(b) = text.delete(b, 0)
      let assert Ok(c) = text.insert(text.new(rid("C")), 0, "c")
      let local = rid("local")
      text.merge(a, b, local)
      |> fn(actual) {
        assert actual == text.merge(b, a, local)
      }
      text.merge(text.merge(a, b, local), c, local)
      |> fn(actual) {
        assert actual == text.merge(a, text.merge(b, c, local), local)
      }
      text.merge(a, a, rid("A"))
      |> fn(actual) {
        assert actual == a
      }
      text.merge(b, b, rid("B"))
      |> fn(actual) {
        assert actual == b
      }
      text.merge(a, text.new(rid("B")), rid("A"))
      |> fn(actual) {
        assert actual == a
      }
      Nil
    },
  )
}
