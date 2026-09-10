import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_registers/mv_register
import lattice_sequence/sequence
import lattice_sets/or_set
import lattice_text/text
import startest/expect
import support/composition_fixture as fixture

fn rid(value) {
  replica_id.new(value)
}

pub fn all_recursive_defaults_and_nochange_identity_test() {
  let specs = [
    crdt.GCounterSpec,
    crdt.PnCounterSpec,
    crdt.LwwRegisterSpec(42),
    crdt.MvRegisterSpec,
    crdt.GSetSpec,
    crdt.TwoPSetSpec,
    crdt.OrSetSpec,
    crdt.SequenceSpec,
    crdt.TextSpec,
    crdt.OrMapSpec(crdt.LwwRegisterSpec(42)),
    crdt.LwwMapSpec(crdt.OrMapSpec(crdt.TextSpec)),
  ]
  list.each(specs, fn(spec) {
    let value = crdt.default_crdt(spec, rid("A"))
    crdt.matches_spec(value, spec) |> expect.to_be_true
    let delta = crdt.default_delta(spec, rid("A"))
    crdt.is_empty_delta(delta) |> expect.to_be_true
    crdt.apply_delta(value, delta, spec, rid("A")) |> expect.to_equal(Ok(value))
    let encoded = crdt.to_json_with(value, json.int) |> json.to_string
    crdt.from_json_with(encoded, decode.int) |> expect.to_equal(Ok(value))
  })
}

pub fn recursive_register_default_is_schema_not_current_value_test() {
  let map = or_map.new(rid("A"), crdt.OrMapSpec(crdt.LwwRegisterSpec(42)))
  let assert Ok(map) =
    or_map.update(map, "doc", fn(value) {
      let assert crdt.CrdtOrMap(child) = value
      let assert Ok(#(child, _)) =
        or_map.update_delta(child, "number", fn(value, context) {
          let assert crdt.CrdtLwwRegister(register) = value
          lww_register.value(register) |> expect.to_equal(42)
          Ok(
            crdt.StateDelta(
              crdt.CrdtLwwRegister(lww_register.set(
                register,
                100,
                1,
                context.replica_id,
              )),
            ),
          )
        })
      crdt.CrdtOrMap(child)
    })
  let assert Ok(loaded) =
    or_map.from_json_with(
      or_map.to_json_with(map, json.int) |> json.to_string,
      decode.int,
    )
  let assert Ok(crdt.CrdtOrMap(child)) = or_map.get(loaded, "doc")
  let assert Ok(child) = or_map.update(child, "other", fn(value) { value })
  let assert Ok(crdt.CrdtLwwRegister(other)) = or_map.get(child, "other")
  lww_register.value(other) |> expect.to_equal(42)
  let assert Ok(crdt.CrdtLwwRegister(current)) = or_map.get(child, "number")
  lww_register.value(current) |> expect.to_equal(100)
  or_map.merge(
    map,
    or_map.new(rid("B"), crdt.OrMapSpec(crdt.LwwRegisterSpec(0))),
  )
  |> expect.to_equal(Error(crdt.SchemaMismatch))
}

fn append_text(map: or_map.ORMap(Int), content: String) {
  let assert Ok(pair) =
    or_map.update_delta(map, "doc", fn(child, _) {
      let assert crdt.CrdtOrMap(child) = child
      let assert Ok(#(_, delta)) =
        or_map.update_delta(child, "text", fn(value, _) {
          let assert crdt.CrdtText(value) = value
          let assert Ok(#(_, delta)) = text.append_with_delta(value, content)
          Ok(crdt.StateDelta(crdt.CrdtText(delta)))
        })
      Ok(crdt.OrMapChange(delta))
    })
  pair
}

fn text_value(map) {
  let assert Ok(crdt.CrdtOrMap(child)) = or_map.get(map, "doc")
  let assert Ok(crdt.CrdtText(value)) = or_map.get(child, "text")
  value
}

pub fn nested_text_remote_only_snapshot_adoption_preserves_ids_and_rebinds_writer_test() {
  let #(baseline, _) =
    append_text(or_map.new(rid("A"), crdt.OrMapSpec(crdt.TextSpec)), "hi")
  let assert Ok(loaded) =
    or_map.from_json_with(
      or_map.to_json_with(baseline, json.int) |> json.to_string,
      decode.int,
    )
  let b = or_map.bind(loaded, rid("B"))
  let #(a, da) = append_text(baseline, "A")
  let #(b, db) = append_text(b, "B")
  let assert Ok(full) = or_map.merge_as(a, b, rid("R"))
  text_value(full) |> text.length |> expect.to_equal(4)
  let assert Ok(remote) =
    list.try_fold(
      [db, da, db],
      or_map.bind(baseline, rid("R")),
      or_map.apply_delta,
    )
  remote |> expect.to_equal(full)
  let #(next, _) = append_text(remote, "R")
  text_value(next) |> text.length |> expect.to_equal(5)
}

pub fn mv_register_and_or_set_joining_writer_does_not_reuse_remote_tags_test() {
  let assert Ok(a) =
    or_map.update(or_map.new(rid("A"), crdt.MvRegisterSpec), "key", fn(value) {
      let assert crdt.CrdtMvRegister(value) = value
      crdt.CrdtMvRegister(mv_register.set(value, 1))
    })
  let b = or_map.bind(a, rid("B"))
  let write = fn(value, n) {
    let assert crdt.CrdtMvRegister(value) = value
    crdt.CrdtMvRegister(mv_register.set(value, n))
  }
  let assert Ok(a) = or_map.update(a, "key", write(_, 2))
  let assert Ok(b) = or_map.update(b, "key", write(_, 3))
  let assert Ok(merged) = or_map.merge(a, b)
  let assert Ok(crdt.CrdtMvRegister(value)) = or_map.get(merged, "key")
  list.length(mv_register.value(value)) |> expect.to_equal(2)

  let assert Ok(a) =
    or_map.update(or_map.new(rid("A"), crdt.OrSetSpec), "key", fn(value) {
      let assert crdt.CrdtOrSet(value) = value
      crdt.CrdtOrSet(or_set.add(value, 1))
    })
  let b = or_map.bind(a, rid("B"))
  let assert Ok(a) =
    or_map.update(a, "key", fn(value) {
      let assert crdt.CrdtOrSet(value) = value
      crdt.CrdtOrSet(or_set.remove(value, 1))
    })
  let assert Ok(b) =
    or_map.update(b, "key", fn(value) {
      let assert crdt.CrdtOrSet(value) = value
      crdt.CrdtOrSet(or_set.add(value, 1))
    })
  let assert Ok(merged) = or_map.merge(a, b)
  let assert Ok(crdt.CrdtOrSet(value)) = or_map.get(merged, "key")
  or_set.contains(value, 1) |> expect.to_be_true
}

pub fn binding_never_rewrites_historical_lww_register_author_test() {
  let register = lww_register.new(99, 10, rid("historical"))
  let assert Ok(map) =
    or_map.update(or_map.new(rid("A"), crdt.LwwRegisterSpec(0)), "key", fn(_) {
      crdt.CrdtLwwRegister(register)
    })
  let assert Ok(crdt.CrdtLwwRegister(received)) =
    or_map.get(or_map.bind(map, rid("B")), "key")
  received |> expect.to_equal(register)
  let assert Ok(#(updated, _)) =
    or_map.update_delta(or_map.bind(map, rid("B")), "key", fn(value, context) {
      let assert crdt.CrdtLwwRegister(value) = value
      Ok(
        crdt.StateDelta(
          crdt.CrdtLwwRegister(lww_register.set(
            value,
            100,
            11,
            context.replica_id,
          )),
        ),
      )
    })
  let assert Ok(crdt.CrdtLwwRegister(written)) = or_map.get(updated, "key")
  { lww_register.replica_id(written) != rid("historical") } |> expect.to_be_true
}

fn atomic_edit(map, timestamp, value) {
  let assert Ok(map) =
    or_map.update(map, "doc", fn(value_map) {
      let assert crdt.CrdtLwwMap(assignments) = value_map
      let assert Ok(assignments) =
        lww_map.update(assignments, "revision", timestamp, fn(child, _) {
          let assert crdt.CrdtOrMap(child) = child
          let assert Ok(child) =
            or_map.update(child, "body", fn(value_map) {
              let assert crdt.CrdtSequence(state) = value_map
              let assert Ok(state) =
                sequence.insert(state, sequence.length(state), value)
              crdt.CrdtSequence(state)
            })
          Ok(crdt.CrdtOrMap(child))
        })
      crdt.CrdtLwwMap(assignments)
    })
  map
}

pub fn or_lww_or_nesting_keeps_atomic_assignment_boundary_test() {
  let spec = crdt.LwwMapSpec(crdt.OrMapSpec(crdt.SequenceSpec))
  let base = atomic_edit(or_map.new(rid("A"), spec), 1, 0)
  let a = atomic_edit(base, 2, 1)
  let b = atomic_edit(or_map.bind(base, rid("B")), 2, 2)
  let assert Ok(merged) = or_map.merge_as(a, b, rid("R"))
  let assert Ok(crdt.CrdtLwwMap(assignments)) = or_map.get(merged, "doc")
  let assert Ok(crdt.CrdtOrMap(child)) = lww_map.get(assignments, "revision")
  let assert Ok(crdt.CrdtSequence(value)) = or_map.get(child, "body")
  sequence.values(value) |> expect.to_equal([0, 2])
  let assert Ok(reverse) = or_map.merge_as(b, a, rid("R"))
  merged |> expect.to_equal(reverse)
  let encoded = or_map.to_json_with(merged, json.int) |> json.to_string
  or_map.from_json_with(encoded, decode.int) |> expect.to_equal(Ok(merged))
}

pub fn outer_pruning_preserves_inner_compaction_frontier_and_forwardings_test() {
  let map = fixture.nested("A", [1, 2, 3])
  let value = fixture.sequence(map)
  let assert Ok(value) = sequence.delete(value, 1)
  let stable =
    version_vector.from_dict(dict.from_list([#(sequence.replica_id(value), 4)]))
  let #(compacted, forwardings) = sequence.compact(value, stable)
  sequence.forwarding_size(forwardings) |> expect.to_equal(1)
  let #(map, _) = fixture.edit(map, fn(_) { compacted })
  let before = fixture.sequence(map)
  let pruned =
    or_map.prune(
      map,
      version_vector.from_dict(dict.from_list([#(rid("A"), 1000)])),
    )
  fixture.sequence(pruned) |> expect.to_equal(before)
  sequence.frontier(fixture.sequence(pruned)) |> expect.to_equal(stable)
}

pub fn text_insert_delete_move_duplicate_delivery_preserves_all_metadata_test() {
  let #(baseline, _) =
    append_text(or_map.new(rid("A"), crdt.OrMapSpec(crdt.TextSpec)), "abcd")
  let mutate = fn(map, callback) {
    let assert Ok(pair) =
      or_map.update_delta(map, "doc", fn(child, _) {
        let assert crdt.CrdtOrMap(child) = child
        let assert Ok(#(_, delta)) =
          or_map.update_delta(child, "text", fn(value, _) {
            let assert crdt.CrdtText(value) = value
            Ok(crdt.StateDelta(crdt.CrdtText(callback(value))))
          })
        Ok(crdt.OrMapChange(delta))
      })
    pair
  }
  let #(a, da) = append_text(baseline, "A")
  let #(b, db) =
    mutate(or_map.bind(baseline, rid("B")), fn(value) {
      let assert Ok(#(_, delta)) = text.delete_with_delta(value, 1)
      delta
    })
  let #(c, dc) =
    mutate(or_map.bind(baseline, rid("C")), fn(value) {
      let assert Ok(#(_, delta)) = text.move_with_delta(value, 3, 0)
      delta
    })
  let assert Ok(ab) = or_map.merge_as(a, b, rid("R"))
  let assert Ok(full) = or_map.merge(ab, c)
  let assert Ok(reordered) =
    list.try_fold(
      [dc, db, da, dc, da],
      or_map.bind(baseline, rid("R")),
      or_map.apply_delta,
    )
  reordered |> expect.to_equal(full)
  text_value(full) |> text.length |> expect.to_equal(4)
  let #(next, _) = append_text(reordered, "R")
  text_value(next) |> text.length |> expect.to_equal(5)
}
