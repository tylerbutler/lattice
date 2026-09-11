import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_sequence/sequence

fn rid(id: String) {
  replica_id.new(id)
}

fn assert_insert_identity(
  state: sequence.Sequence(String),
  inserted_value: String,
  replica: String,
  counter: Int,
) {
  let assert Ok(#(_, index)) =
    sequence.values(state)
    |> list.index_map(fn(value, index) { #(value, index) })
    |> list.find(fn(pair) { pair.0 == inserted_value })
  let assert Ok(anchor) = sequence.anchor_at(state, index, sequence.Before)
  let id_decoder = {
    use replica <- decode.field("replica_id", decode.string)
    use counter <- decode.field("counter", decode.int)
    decode.success(#(replica, counter))
  }
  sequence.anchor_to_json(anchor)
  |> json.to_string()
  |> json.parse(decode.at(["anchor", "id"], id_decoder))
  |> fn(actual) {
    assert actual == { Ok(#(replica, counter)) }
  }

  sequence.to_json(state, json.string)
  |> json.to_string()
  |> json.parse(decode.at(["state", "counter"], decode.int))
  |> fn(actual) {
    assert actual == { Ok(counter) }
  }
  sequence.replica_id(state)
  |> fn(actual) {
    assert actual == { rid(replica) }
  }
}

pub fn canonical_and_alias_merge_preserve_explicit_identity_and_counters_test() {
  let assert Ok(base) =
    sequence.insert_many(sequence.new(rid("A")), 0, ["a", "b", "c", "d"])
  let assert Ok(moved_anchor) = sequence.anchor_at(base, 0, sequence.Before)
  let assert Ok(base) = sequence.delete(base, 1)
  let assert Ok(base) = sequence.move(base, 0, 2)
  let floor = version_vector.new() |> version_vector.set_max(rid("A"), 6)
  let #(compacted, forwardings) = sequence.compact(base, floor)
  sequence.forwarding_size(forwardings)
  |> fn(actual) {
    assert actual == { 1 }
  }
  sequence.values(compacted)
  |> fn(actual) {
    assert actual == { ["c", "d", "a"] }
  }

  use local <- list.each([base, compacted])
  let peer = sequence.merge(base, sequence.new(rid("B")), rid("B"))
  let assert Ok(#(peer, delta)) =
    sequence.insert_many_with_delta(peer, 1, ["r", "s"])
  let assert Ok(decoded_state) =
    sequence.to_json(peer, json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)
  let assert Ok(decoded_delta) =
    sequence.to_json(delta, json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)
  decoded_state
  |> fn(actual) {
    assert actual == { peer }
  }
  decoded_delta
  |> fn(actual) {
    assert actual == { delta }
  }

  use incoming <- list.each([peer, delta, decoded_state, decoded_delta])
  use identity <- list.each(["A", "C"])
  let replica = rid(identity)
  let expected = sequence.merge(local, peer, replica)
  use merge <- list.each([sequence.merge, sequence.merge_as])
  use pair <- list.each([#(local, incoming), #(incoming, local)])
  let merged = merge(pair.0, pair.1, replica)
  merged
  |> fn(actual) {
    assert actual == { expected }
  }
  sequence.replica_id(merged)
  |> fn(actual) {
    assert actual == { replica }
  }
  sequence.resolve(merged, moved_anchor)
  |> fn(actual) {
    assert actual == { Ok(4) }
  }
  merge(merged, incoming, replica)
  |> fn(actual) {
    assert actual == { merged }
  }
  merge(incoming, merged, replica)
  |> fn(actual) {
    assert actual == { merged }
  }
  sequence.replica_id(local)
  |> fn(actual) {
    assert actual == { rid("A") }
  }

  let assert Ok(edited) = sequence.insert(merged, 5, "local")
  let assert Ok(peer_edit) = sequence.insert(peer, 5, "remote")
  assert_insert_identity(edited, "local", identity, 9)
  assert_insert_identity(peer_edit, "remote", "B", 9)

  let joined = merge(edited, peer_edit, replica)
  merge(peer_edit, edited, replica)
  |> fn(actual) {
    assert actual == { joined }
  }
  sequence.length(joined)
  |> fn(actual) {
    assert actual == { 7 }
  }
  sequence.values(joined)
  |> list.contains("local")
  |> fn(value) {
    assert value
  }
  sequence.values(joined)
  |> list.contains("remote")
  |> fn(value) {
    assert value
  }
  let assert Ok(next) = sequence.insert(joined, 7, "next")
  assert_insert_identity(next, "next", identity, 10)
}

pub fn empty_delta_matches_new_and_preserves_compacted_moved_state_test() {
  let assert Ok(base) =
    sequence.insert_many(sequence.new(rid("A")), 0, ["a", "b", "c", "d"])
  let assert Ok(base) = sequence.delete(base, 1)
  let assert Ok(base) = sequence.move(base, 0, 2)
  let floor = version_vector.new() |> version_vector.set_max(rid("A"), 6)
  let #(compacted, _) = sequence.compact(base, floor)

  list.each([base, compacted], fn(state) {
    let assert Ok(#(updated, delta)) =
      sequence.insert_many_with_delta(state, 1, [])
    updated
    |> fn(actual) {
      assert actual == { state }
    }
    delta
    |> fn(actual) {
      assert actual == { sequence.new(sequence.replica_id(state)) }
    }
    let assert Ok(decoded) =
      sequence.to_json(delta, json.string)
      |> json.to_string()
      |> sequence.from_json(decode.string)
    decoded
    |> fn(actual) {
      assert actual == { delta }
    }

    list.each([sequence.merge, sequence.merge_as], fn(merge) {
      list.each([delta, decoded, sequence.new(rid("remote"))], fn(empty) {
        let left = merge(state, empty, rid("A"))
        let right = merge(empty, state, rid("A"))
        left
        |> fn(actual) {
          assert actual == { state }
        }
        right
        |> fn(actual) {
          assert actual == { state }
        }
        merge(left, empty, rid("A"))
        |> fn(actual) {
          assert actual == { state }
        }
        let assert Ok(next) = sequence.insert(right, 3, "next")
        assert_insert_identity(next, "next", "A", 7)
      })
    })
  })
}

pub fn bind_preserves_history_and_counter_without_rebuilding_test() {
  let assert Ok(base) =
    sequence.insert_many(sequence.new(rid("A")), 0, ["a", "b", "c", "d"])
  let assert Ok(base) = sequence.delete(base, 1)
  let assert Ok(#(base, delta)) = sequence.move_with_delta(base, 0, 2)
  let floor = version_vector.new() |> version_vector.set_max(rid("A"), 6)
  let #(compacted, _) = sequence.compact(base, floor)
  let assert Ok(decoded) =
    sequence.to_json(compacted, json.string)
    |> json.to_string()
    |> sequence.from_json(decode.string)

  use state <- list.each([base, compacted, decoded, delta])
  let bound = sequence.bind(state, rid("B"))
  sequence.replica_id(bound)
  |> fn(actual) {
    assert actual == { rid("B") }
  }
  sequence.bind(bound, rid("A"))
  |> fn(actual) {
    assert actual == { state }
  }
  sequence.bind(bound, rid("B"))
  |> fn(actual) {
    assert actual == { bound }
  }
  sequence.merge(bound, base, rid("B"))
  |> fn(actual) {
    assert actual == { sequence.merge(state, base, rid("B")) }
  }

  let assert Ok(edited) =
    sequence.insert(bound, sequence.length(bound), "local")
  assert_insert_identity(edited, "local", "B", 7)
}
