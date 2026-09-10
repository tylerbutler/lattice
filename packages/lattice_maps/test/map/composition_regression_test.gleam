import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_sequence/sequence
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_text/text
import startest/expect

fn rid(value: String) {
  replica_id.new(value)
}

fn membership(map: or_map.ORMap(String), key: String) {
  let assert Ok(entries) =
    json.parse(or_map.to_json(map) |> json.to_string, {
      use entries <- decode.field("state", {
        use entries <- decode.field(
          "entries",
          decode.list({
            use key <- decode.field("key", decode.string)
            use membership <- decode.field("membership", decode.string)
            decode.success(#(key, membership))
          }),
        )
        decode.success(entries)
      })
      decode.success(entries)
    })
  let assert Ok(#(_, encoded)) =
    list.find(entries, fn(entry) { entry.0 == key })
  let assert Ok(membership) = or_set.from_json_with(encoded, decode.string)
  membership
}

pub fn lww_frozen_removed_or_map_child_round_trip_does_not_conflict_test() {
  let assert Ok(active) =
    or_map.update(or_map.new(rid("A"), crdt.GSetSpec), "key", fn(value) {
      let assert crdt.CrdtGSet(value) = value
      crdt.CrdtGSet(g_set.add(value, "retained"))
    })
  let #(_, stable) = or_set.remove_with_bound(membership(active, "key"), "key")
  let removed = active |> or_map.prune(stable) |> or_map.remove("key")
  let empty = lww_map.new(rid("A"), crdt.OrMapSpec(crdt.GSetSpec))
  let assert Ok(assigned) =
    lww_map.set(empty, "snapshot", crdt.CrdtOrMap(removed), 1)
  let assert Ok(edited) =
    lww_map.update(empty, "snapshot", 1, fn(_, _) {
      Ok(crdt.CrdtOrMap(removed))
    })
  list.each([assigned, edited], fn(original) {
    let assert Ok(loaded) =
      lww_map.from_json(lww_map.to_json(original) |> json.to_string)
    loaded |> expect.to_equal(original)
    lww_map.merge(original, loaded) |> expect.to_equal(Ok(original))
    lww_map.merge(loaded, original) |> expect.to_equal(Ok(original))
    let assert Ok(conflicting) =
      lww_map.set(empty, "snapshot", crdt.CrdtOrMap(active), 1)
    lww_map.merge(loaded, conflicting)
    |> expect.to_equal(Error(crdt.ConflictingWrite("snapshot", 1)))

    let assert Ok(outer) =
      lww_map.set(
        lww_map.new(
          rid("outer"),
          crdt.LwwMapSpec(crdt.OrMapSpec(crdt.GSetSpec)),
        ),
        "nested",
        crdt.CrdtLwwMap(original),
        2,
      )
    let assert Ok(loaded_outer) =
      lww_map.from_json(lww_map.to_json(outer) |> json.to_string)
    lww_map.merge(outer, loaded_outer) |> expect.to_equal(Ok(outer))
  })
}

fn register_value(map: or_map.ORMap(String)) {
  let assert Ok(crdt.CrdtLwwRegister(value)) = or_map.get(map, "key")
  lww_register.value(value)
}

pub fn lww_frozen_pruned_map_allocator_round_trip_is_stable_test() {
  let assert Ok(map) =
    or_map.update(or_map.new(rid("A"), crdt.GSetSpec), "key", fn(value) {
      value
    })
  let map =
    list.fold([1, 2, 3], map, fn(map, _) {
      let assert Ok(map) = or_map.update(map, "other", fn(value) { value })
      map
    })
  let #(_, key_bound) = or_set.remove_with_bound(membership(map, "key"), "key")
  let #(_, other_bound) =
    or_set.remove_with_bound(membership(map, "other"), "other")
  let stable = version_vector.merge(key_bound, other_bound)
  let child = map |> or_map.prune(stable) |> or_map.remove("key")
  let assert Ok(original) =
    lww_map.set(
      lww_map.new(rid("A"), crdt.OrMapSpec(crdt.GSetSpec)),
      "snapshot",
      crdt.CrdtOrMap(child),
      1,
    )
  let assert Ok(loaded) =
    lww_map.from_json(lww_map.to_json(original) |> json.to_string)
  loaded |> expect.to_equal(original)
  lww_map.merge(original, loaded) |> expect.to_equal(Ok(original))
}

pub fn binding_and_frozen_round_trips_preserve_sequence_text_compaction_history_test() {
  let author = rid("A")
  let stable = version_vector.new() |> version_vector.set_max(author, 4)
  let assert Ok(sequence) =
    sequence.insert_many(sequence.new(author), 0, ["a", "b", "c"])
  let assert Ok(sequence) = sequence.delete(sequence, 1)
  let #(sequence, sequence_forwardings) = sequence.compact(sequence, stable)
  sequence.forwarding_size(sequence_forwardings) |> expect.to_equal(1)
  let assert Ok(text) = text.append(text.new(author), "abc")
  let assert Ok(text) = text.delete(text, 1)
  let #(text, text_forwardings) = text.compact(text, stable)
  sequence.forwarding_size(text_forwardings) |> expect.to_equal(1)
  list.each(
    [
      #(crdt.SequenceSpec, crdt.CrdtSequence(sequence)),
      #(crdt.TextSpec, crdt.CrdtText(text)),
    ],
    fn(pair) {
      let #(spec, child) = pair
      child
      |> crdt.bind(rid("B"))
      |> crdt.bind(author)
      |> expect.to_equal(child)
      let assert Ok(direct) =
        lww_map.set(lww_map.new(author, spec), "snapshot", child, 1)
      let assert Ok(view) =
        lww_map.get(lww_map.bind(direct, rid("B")), "snapshot")
      crdt.bind(view, author) |> expect.to_equal(child)
      let assert Ok(nested) =
        or_map.update(or_map.new(author, spec), "history", fn(_) { child })
      let assert Ok(recursive) =
        lww_map.set(
          lww_map.new(author, crdt.OrMapSpec(spec)),
          "snapshot",
          crdt.CrdtOrMap(nested),
          1,
        )
      list.each([direct, recursive], fn(original) {
        let assert Ok(loaded) =
          lww_map.from_json(lww_map.to_json(original) |> json.to_string)
        loaded |> expect.to_equal(original)
        lww_map.merge(original, loaded) |> expect.to_equal(Ok(original))
        lww_map.merge(loaded, original) |> expect.to_equal(Ok(original))
      })
    },
  )
}

fn check_delivery(
  a: or_map.ORMap(String),
  da: or_map.ORMapDelta(String),
  b: or_map.ORMap(String),
  db: or_map.ORMapDelta(String),
) {
  let receiver = or_map.new(rid("R"), or_map.spec(a))
  let assert Ok(full) = or_map.merge_as(a, b, rid("R"))
  list.each([[da, db], [db, da], [db, da, db, da]], fn(delivery) {
    let assert Ok(delivered) =
      list.try_fold(delivery, receiver, or_map.apply_delta)
    delivered |> expect.to_equal(full)
  })
  list.each([#(da, db), #(db, da)], fn(pair) {
    let assert Ok(batch) = or_map.merge_deltas(pair.0, pair.1)
    let assert Ok(batch) =
      or_map.delta_from_json(or_map.delta_to_json(batch) |> json.to_string)
    or_map.apply_delta(receiver, batch) |> expect.to_equal(Ok(full))
    crdt.apply_delta(
      crdt.CrdtOrMap(receiver),
      crdt.OrMapChange(batch),
      crdt.OrMapSpec(or_map.spec(a)),
      rid("R"),
    )
    |> expect.to_equal(Ok(crdt.CrdtOrMap(full)))
    let assert Ok(dispatch_batch) =
      crdt.merge_deltas(
        crdt.OrMapChange(pair.0),
        crdt.OrMapChange(pair.1),
        crdt.OrMapSpec(or_map.spec(a)),
        rid("R"),
      )
    crdt.apply_delta(
      crdt.CrdtOrMap(receiver),
      dispatch_batch,
      crdt.OrMapSpec(or_map.spec(a)),
      rid("R"),
    )
    |> expect.to_equal(Ok(crdt.CrdtOrMap(full)))
  })
}

pub fn absent_nochange_register_initialization_converges_in_all_delivery_orders_test() {
  let spec = crdt.LwwRegisterSpec("seed")
  let empty = or_map.new(rid("A"), spec)
  let assert Ok(#(a, da)) =
    or_map.update_delta(empty, "key", fn(_, _) { Ok(crdt.NoChange(spec)) })
  list.each(["A", "zz"], fn(author) {
    let value = crdt.CrdtLwwRegister(lww_register.new("other", 0, rid(author)))
    let assert Ok(#(b, db)) =
      or_map.update_with_delta(or_map.new(rid("B"), spec), "key", fn(_) {
        value
      })
    check_delivery(a, da, b, db)
    let assert Ok(full) = or_map.merge(a, b)
    register_value(full)
    |> expect.to_equal(case author {
      "A" -> "seed"
      _ -> "other"
    })
    let assert Ok(local) =
      or_map.update(or_map.new(rid("B"), spec), "key", fn(_) { value })
    local |> expect.to_equal(b)
    or_map.apply_delta(or_map.new(rid("B"), spec), db) |> expect.to_equal(Ok(b))
    let assert Ok(#(sparse, sparse_delta)) =
      or_map.update_delta(or_map.new(rid("B"), spec), "key", fn(_, _) {
        Ok(crdt.StateDelta(value))
      })
    sparse |> expect.to_equal(b)
    check_delivery(a, da, sparse, sparse_delta)
  })
}

pub fn reset_nochange_register_initialization_is_carried_by_generation_delta_test() {
  let spec = crdt.LwwRegisterSpec("seed")
  let assert Ok(old) =
    or_map.update(or_map.new(rid("A"), spec), "key", fn(_) {
      crdt.CrdtLwwRegister(lww_register.new("old", 10, rid("A")))
    })
  let removed = or_map.remove(old, "key")
  let assert Ok(#(reset, delta)) =
    or_map.update_delta(removed, "key", fn(_, _) { Ok(crdt.NoChange(spec)) })
  let assert Ok(encoded_child) =
    json.parse(or_map.delta_to_json(delta) |> json.to_string, {
      use children <- decode.field("state", {
        use children <- decode.field(
          "entries",
          decode.list({
            use value <- decode.field("value", decode.string)
            decode.success(value)
          }),
        )
        decode.success(children)
      })
      decode.success(children)
    })
  let assert [encoded_child] = encoded_child
  let assert Ok(crdt.StateDelta(crdt.CrdtLwwRegister(initial))) =
    crdt.delta_from_json(encoded_child)
  lww_register.value(initial) |> expect.to_equal("seed")
  or_map.apply_delta(old, delta) |> expect.to_equal(Ok(reset))
  register_value(reset) |> expect.to_equal("seed")
}

pub fn nested_nochange_register_initialization_converges_through_sparse_parent_test() {
  let spec = crdt.LwwRegisterSpec("seed")
  let mutate = fn(writer, change) {
    let map = or_map.new(rid(writer), crdt.OrMapSpec(spec))
    let assert Ok(pair) =
      or_map.update_delta(map, "key", fn(value, _) {
        let assert crdt.CrdtOrMap(child) = value
        let assert Ok(#(_, delta)) =
          or_map.update_delta(child, "key", fn(_, _) { Ok(change) })
        Ok(crdt.OrMapChange(delta))
      })
    pair
  }
  let #(a, da) = mutate("A", crdt.NoChange(spec))
  let #(b, db) =
    mutate(
      "B",
      crdt.StateDelta(
        crdt.CrdtLwwRegister(lww_register.new("other", 0, rid("A"))),
      ),
    )
  check_delivery(a, da, b, db)
  let assert Ok(crdt.CrdtOrMap(child)) = or_map.get(a, "key")
  register_value(child) |> expect.to_equal("seed")
}

fn import_legacy_child(value: String, receiver: String) {
  let input =
    json.object([
      #("type", json.string("lww_map")),
      #("v", json.int(2)),
      #(
        "state",
        json.object([
          #("pruned_timestamp", json.int(0)),
          #(
            "entries",
            json.array(
              [
                json.object([
                  #("key", json.string("key")),
                  #("value", json.string(value)),
                  #("timestamp", json.int(10)),
                ]),
              ],
              fn(value) { value },
            ),
          ),
        ]),
      ),
    ])
    |> json.to_string
  let assert Ok(map) =
    lww_map.import_legacy(input, crdt.LwwRegisterSpec(""), rid(receiver))
  let assert Ok(child) = lww_map.get(map, "key")
  child
}

pub fn legacy_lww_imported_children_merge_commutatively_test() {
  let a = import_legacy_child("aaa", "A")
  let b = import_legacy_child("zzz", "B")
  import_legacy_child("aaa", "other-receiver") |> expect.to_equal(a)
  let assert Ok(ab) = crdt.merge(a, b, rid("R"))
  crdt.merge(b, a, rid("R")) |> expect.to_equal(Ok(ab))
  let assert crdt.CrdtLwwRegister(winner) = ab
  lww_register.value(winner) |> expect.to_equal("zzz")
  let assert Ok(ma) =
    or_map.update(or_map.new(rid("A"), crdt.LwwRegisterSpec("")), "key", fn(_) {
      a
    })
  let assert Ok(mb) =
    or_map.update(or_map.new(rid("B"), crdt.LwwRegisterSpec("")), "key", fn(_) {
      b
    })
  let assert Ok(merged) = or_map.merge_as(ma, mb, rid("R"))
  or_map.merge_as(mb, ma, rid("R")) |> expect.to_equal(Ok(merged))
  register_value(merged) |> expect.to_equal("zzz")
}

fn missing_value_snapshot(active: Bool, delta: Bool) {
  let membership = or_set.new(rid("A")) |> or_set.add("key")
  let membership = case active {
    True -> membership
    False -> or_set.remove(membership, "key")
  }
  json.object([
    #(
      "type",
      json.string(case delta {
        True -> "or_map_delta"
        False -> "or_map"
      }),
    ),
    #(
      "v",
      json.int(case delta {
        True -> 2
        False -> 3
      }),
    ),
    #(
      "state",
      json.object([
        #("replica_id", json.string("A")),
        #(
          "spec",
          json.string(
            crdt.spec_to_json_with(crdt.SequenceSpec, json.string)
            |> json.to_string,
          ),
        ),
        #("clock", json.int(1)),
        #(
          "entries",
          json.array(
            [
              json.object([
                #("key", json.string("key")),
                #(
                  "generation",
                  json.object([
                    #("clock", json.int(1)),
                    #("creator", json.string("A")),
                  ]),
                ),
                #(
                  "membership",
                  json.string(
                    or_set.to_json_with(membership, json.string)
                    |> json.to_string,
                  ),
                ),
                #("value", json.null()),
              ]),
            ],
            fn(value) { value },
          ),
        ),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn or_map_snapshot_rejects_active_membership_without_value_test() {
  let assert Error(_) = or_map.from_json(missing_value_snapshot(True, False))
  let assert Error(_) = crdt.from_json(missing_value_snapshot(True, False))
  let assert Ok(floor) = or_map.from_json(missing_value_snapshot(False, False))
  or_map.keys(floor) |> expect.to_equal([])
  or_map.from_json(or_map.to_json(floor) |> json.to_string)
  |> expect.to_equal(Ok(floor))
  let assert Ok(removal) =
    or_map.delta_from_json(missing_value_snapshot(False, True))
  let assert Ok(removed) =
    or_map.apply_delta(or_map.new(rid("A"), crdt.SequenceSpec), removal)
  or_map.keys(removed) |> expect.to_equal([])
}
