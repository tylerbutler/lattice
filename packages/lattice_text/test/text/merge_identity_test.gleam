import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence
import lattice_text/text

fn rid(id: String) {
  replica_id.new(id)
}

fn assert_insert_identity(
  state: text.Text,
  inserted_value: String,
  replica: String,
  counter: Int,
) {
  let assert Ok(#(_, index)) =
    text.values(state)
    |> list.index_map(fn(value, index) { #(value, index) })
    |> list.find(fn(pair) { pair.0 == inserted_value })
  let assert Ok(anchor) = text.anchor_at(state, index, sequence.Before)
  let id_decoder = {
    use replica <- decode.field("replica_id", decode.string)
    use counter <- decode.field("counter", decode.int)
    decode.success(#(replica, counter))
  }
  text.anchor_to_json(anchor)
  |> json.to_string()
  |> json.parse(decode.at(["anchor", "id"], id_decoder))
  |> fn(actual) {
    assert actual == Ok(#(replica, counter))
  }

  let state_decoder = {
    use replica <- decode.field("self_id", decode.string)
    use counter <- decode.field("counter", decode.int)
    decode.success(#(replica, counter))
  }
  text.to_json(state)
  |> json.to_string()
  |> json.parse(decode.at(["state"], state_decoder))
  |> fn(actual) {
    assert actual == Ok(#(replica, counter))
  }
}

pub fn canonical_and_alias_merge_preserve_explicit_identity_and_counters_test() {
  let assert Ok(base) = text.insert(text.new(rid("A")), 0, "abcd")
  let assert Ok(base) = text.delete(base, 1)
  let assert Ok(base) = text.move(base, 0, 2)
  let floor = version_vector.new() |> version_vector.set_max(rid("A"), 6)
  let #(compacted, forwardings) = text.compact(base, floor)
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == 1
  }
  text.value(compacted)
  |> fn(actual) {
    assert actual == "cda"
  }

  use local <- list.each([base, compacted])
  let peer = text.merge(base, text.new(rid("B")), rid("B"))
  let assert Ok(#(peer, delta)) =
    text.replace_range_with_delta(peer, 1, 3, "RS")
  assert_insert_identity(delta, "S", "B", 10)
  let assert Ok(decoded_state) =
    text.to_json(peer) |> json.to_string() |> text.from_json()
  let assert Ok(decoded_delta) =
    text.to_json(delta) |> json.to_string() |> text.from_json()
  decoded_state
  |> fn(actual) {
    assert actual == peer
  }
  decoded_delta
  |> fn(actual) {
    assert actual == delta
  }

  use incoming <- list.each([peer, delta, decoded_state, decoded_delta])
  use identity <- list.each(["A", "C"])
  let replica = rid(identity)
  let expected = text.merge(local, peer, replica)
  use merge <- list.each([text.merge, text.merge_as])
  use pair <- list.each([#(local, incoming), #(incoming, local)])
  let merged = merge(pair.0, pair.1, replica)
  merged
  |> fn(actual) {
    assert actual == expected
  }
  merge(merged, incoming, replica)
  |> fn(actual) {
    assert actual == merged
  }
  merge(incoming, merged, replica)
  |> fn(actual) {
    assert actual == merged
  }

  let assert Ok(edited) = text.append(merged, "x")
  let assert Ok(peer_edit) = text.append(peer, "y")
  assert_insert_identity(edited, "x", identity, 11)
  assert_insert_identity(peer_edit, "y", "B", 11)

  let joined = merge(edited, peer_edit, replica)
  merge(peer_edit, edited, replica)
  |> fn(actual) {
    assert actual == joined
  }
  text.length(joined)
  |> fn(actual) {
    assert actual == 5
  }
  text.values(joined)
  |> list.contains("x")
  |> fn(actual) {
    assert actual
  }
  text.values(joined)
  |> list.contains("y")
  |> fn(actual) {
    assert actual
  }
  let assert Ok(next) = text.append(joined, "z")
  assert_insert_identity(next, "z", identity, 12)
}

pub fn empty_deltas_match_new_and_preserve_compacted_moved_state_test() {
  let assert Ok(base) = text.insert(text.new(rid("A")), 0, "abcd")
  let assert Ok(base) = text.delete(base, 1)
  let assert Ok(base) = text.move(base, 0, 2)
  let floor = version_vector.new() |> version_vector.set_max(rid("A"), 6)
  let #(compacted, _) = text.compact(base, floor)

  list.each([base, compacted], fn(state) {
    list.each(
      [
        text.insert_with_delta(state, 1, "")
          |> fn(result) {
            let assert Ok(value) = result
            value
          },
        text.append_with_delta(state, "")
          |> fn(result) {
            let assert Ok(value) = result
            value
          },
        text.delete_range_with_delta(state, 1, 1)
          |> fn(result) {
            let assert Ok(value) = result
            value
          },
        text.replace_range_with_delta(state, 1, 1, "")
          |> fn(result) {
            let assert Ok(value) = result
            value
          },
      ],
      fn(pair) {
        let #(updated, delta) = pair
        updated
        |> fn(actual) {
          assert actual == state
        }
        delta
        |> fn(actual) {
          assert actual == text.new(rid("A"))
        }
        let assert Ok(decoded) =
          text.to_json(delta) |> json.to_string() |> text.from_json()
        decoded
        |> fn(actual) {
          assert actual == delta
        }

        list.each([text.merge, text.merge_as], fn(merge) {
          list.each([delta, decoded, text.new(rid("remote"))], fn(empty) {
            let left = merge(state, empty, rid("A"))
            let right = merge(empty, state, rid("A"))
            left
            |> fn(actual) {
              assert actual == state
            }
            right
            |> fn(actual) {
              assert actual == state
            }
            merge(left, empty, rid("A"))
            |> fn(actual) {
              assert actual == state
            }
            let assert Ok(next) = text.append(right, "x")
            assert_insert_identity(next, "x", "A", 7)
          })
        })
      },
    )
  })
}

pub fn bind_preserves_history_and_counter_without_rebuilding_test() {
  let assert Ok(base) = text.insert(text.new(rid("A")), 0, "abcd")
  let assert Ok(base) = text.delete(base, 1)
  let assert Ok(#(base, delta)) = text.move_with_delta(base, 0, 2)
  let floor = version_vector.new() |> version_vector.set_max(rid("A"), 6)
  let #(compacted, _) = text.compact(base, floor)
  let assert Ok(decoded) =
    text.to_json(compacted) |> json.to_string() |> text.from_json()

  use state <- list.each([base, compacted, decoded, delta])
  let bound = text.bind(state, rid("B"))
  text.bind(bound, rid("A"))
  |> fn(actual) {
    assert actual == state
  }
  text.bind(bound, rid("B"))
  |> fn(actual) {
    assert actual == bound
  }
  text.merge(bound, base, rid("B"))
  |> fn(actual) {
    assert actual == text.merge(state, base, rid("B"))
  }

  let assert Ok(edited) = text.append(bound, "x")
  assert_insert_identity(edited, "x", "B", 7)
}
