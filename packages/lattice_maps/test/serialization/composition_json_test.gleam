import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_registers/mv_register
import lattice_sequence/sequence
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import lattice_text/text
import support/composition_fixture as fixture

type Point {
  Point(x: Int, name: String)
}

fn encode_point(point: Point) {
  json.object([#("x", json.int(point.x)), #("name", json.string(point.name))])
}

fn point_decoder() {
  use x <- decode.field("x", decode.int)
  use name <- decode.field("name", decode.string)
  decode.success(Point(x, name))
}

fn rid(value) {
  replica_id.new(value)
}

pub fn generic_record_leaf_dispatch_and_recursive_map_codecs_test() {
  let initial = Point(0, "initial")
  let point = Point(42, "value")
  let assert Ok(seq) = sequence.insert(sequence.new(rid("A")), 0, point)
  let leaves = [
    crdt.CrdtLwwRegister(lww_register.new(point, 1, rid("A"))),
    crdt.CrdtMvRegister(mv_register.new(rid("A")) |> mv_register.set(point)),
    crdt.CrdtGSet(g_set.new() |> g_set.add(point)),
    crdt.CrdtTwoPSet(
      two_p_set.new() |> two_p_set.add(point) |> two_p_set.remove(point),
    ),
    crdt.CrdtOrSet(
      or_set.new(rid("A")) |> or_set.add(point) |> or_set.remove(point),
    ),
    crdt.CrdtSequence(seq),
  ]
  list.each(leaves, fn(leaf) {
    let encoded = crdt.to_json_with(leaf, encode_point) |> json.to_string
    crdt.from_json_with(encoded, point_decoder())
    |> fn(assertion_actual) {
      let assert True = assertion_actual == Ok(leaf)
    }
  })
  let map = or_map.new(rid("A"), crdt.OrMapSpec(crdt.LwwRegisterSpec(initial)))
  let assert Ok(map) =
    or_map.update(map, "doc", fn(child) {
      let assert crdt.CrdtOrMap(child) = child
      let assert Ok(child) =
        or_map.update(child, "value", fn(_) {
          crdt.CrdtLwwRegister(lww_register.new(point, 1, rid("A")))
        })
      crdt.CrdtOrMap(child)
    })
  let encoded = or_map.to_json_with(map, encode_point) |> json.to_string
  let assert Ok(decoded) = or_map.from_json_with(encoded, point_decoder())
  decoded
  |> fn(assertion_actual) {
    let assert True = assertion_actual == map
  }
  let assert Ok(crdt.CrdtOrMap(child)) = or_map.get(decoded, "doc")
  let assert Ok(child) = or_map.update(child, "new", fn(value) { value })
  let assert Ok(crdt.CrdtLwwRegister(value)) = or_map.get(child, "new")
  lww_register.value(value)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == initial
  }
  let assert Ok(atomic) =
    lww_map.set(
      lww_map.new(
        rid("A"),
        crdt.OrMapSpec(crdt.OrMapSpec(crdt.LwwRegisterSpec(initial))),
      ),
      "root",
      crdt.CrdtOrMap(map),
      1,
    )
  crdt.from_json_with(
    crdt.to_json_with(crdt.CrdtLwwMap(atomic), encode_point) |> json.to_string,
    point_decoder(),
  )
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(crdt.CrdtLwwMap(atomic))
  }
}

pub fn text_dispatch_does_not_alias_string_sequence_wire_format_test() {
  let assert Ok(value) = text.append(text.new(rid("A")), "hello")
  let text_json = crdt.to_json(crdt.CrdtText(value)) |> json.to_string
  let assert Ok(crdt.CrdtText(decoded)) = crdt.from_json(text_json)
  decoded
  |> fn(assertion_actual) {
    let assert True = assertion_actual == value
  }
  let assert Ok(crdt.CrdtSequence(decoded)) =
    crdt.from_json(text.to_json(value) |> json.to_string)
  sequence.values(decoded)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ["h", "e", "l", "l", "o"]
  }
  let delta = crdt.StateDelta(crdt.CrdtText(value))
  crdt.delta_from_json_with(
    crdt.delta_to_json_with(delta, json.int) |> json.to_string,
    decode.int,
  )
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(delta)
  }
}

pub fn direct_recursive_dispatch_deltas_round_trip_and_apply_test() {
  let before = fixture.nested("A", [1, 2, 3])
  let #(after, delta) =
    fixture.edit(before, fn(value) {
      let assert Ok(#(_, delta)) = sequence.move_with_delta(value, 2, 0)
      delta
    })
  let wrapped = crdt.OrMapChange(delta)
  let encoded = crdt.delta_to_json_with(wrapped, json.int) |> json.to_string
  let assert Ok(decoded) = crdt.delta_from_json_with(encoded, decode.int)
  decoded
  |> fn(assertion_actual) {
    let assert True = assertion_actual == wrapped
  }
  let assert Ok(applied) =
    crdt.apply_delta(
      crdt.CrdtOrMap(before),
      decoded,
      crdt.OrMapSpec(crdt.OrMapSpec(crdt.SequenceSpec)),
      rid("A"),
    )
  applied
  |> fn(assertion_actual) {
    let assert True = assertion_actual == crdt.CrdtOrMap(after)
  }
  let nochange = crdt.NoChange(crdt.OrMapSpec(crdt.LwwRegisterSpec(42)))
  crdt.delta_from_json_with(
    crdt.delta_to_json_with(nochange, json.int) |> json.to_string,
    decode.int,
  )
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(nochange)
  }
  let state = crdt.StateDelta(crdt.CrdtOrMap(after))
  crdt.delta_from_json_with(
    crdt.delta_to_json_with(state, json.int) |> json.to_string,
    decode.int,
  )
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(state)
  }
}

fn legacy_lww(value: json.Json) -> String {
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
                #("value", value),
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
}

fn legacy_import(value, writer) {
  let assert Ok(map) =
    lww_map.import_legacy(
      legacy_lww(value),
      crdt.LwwRegisterSpec("initial"),
      rid(writer),
    )
  map
}

pub fn legacy_lww_ties_provenance_and_modern_rank_survive_round_trip_test() {
  let a = legacy_import(json.string("aaa"), "Z")
  let b = legacy_import(json.string("zzz"), "A")
  let assert Ok(ab) = lww_map.merge_as(a, b, rid("R"))
  let assert Ok(ba) = lww_map.merge_as(b, a, rid("R"))
  ab
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ba
  }
  let assert Ok(crdt.CrdtLwwRegister(value)) = lww_map.get(ab, "key")
  lww_register.value(value)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == "zzz"
  }
  let assert Ok(loaded) =
    lww_map.from_json(lww_map.to_json(ab) |> json.to_string)
  loaded
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ab
  }
  let modern = lww_map.new(rid("0"), crdt.LwwRegisterSpec("initial"))
  let assert Ok(modern) =
    lww_map.set(
      modern,
      "key",
      crdt.CrdtLwwRegister(lww_register.new("modern", 10, rid("0"))),
      10,
    )
  let assert Ok(merged) = lww_map.merge(loaded, modern)
  let assert Ok(crdt.CrdtLwwRegister(value)) = lww_map.get(merged, "key")
  lww_register.value(value)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == "modern"
  }
  let tombstone = legacy_import(json.null(), "old")
  let assert Ok(merged) = lww_map.merge(modern, tombstone)
  lww_map.get(merged, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
}

fn legacy_or_snapshot() -> String {
  let keys = or_set.new(rid("old")) |> or_set.add("key")
  let value = crdt.CrdtOrSet(or_set.new(rid("old")) |> or_set.add("item"))
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(2)),
    #(
      "state",
      json.object([
        #("replica_id", json.string("old")),
        #("crdt_spec", json.string("or_set")),
        #("key_set", json.string(or_set.to_json(keys) |> json.to_string)),
        #(
          "values",
          json.array(
            [
              json.object([
                #("key", json.string("key")),
                #("crdt", json.string(crdt.to_json(value) |> json.to_string)),
              ]),
            ],
            fn(value) { value },
          ),
        ),
        #("remove_bounds", json.object([])),
      ]),
    ),
  ])
  |> json.to_string
}

pub fn legacy_or_map_import_is_explicit_and_readd_resets_initial_generation_test() {
  let input = legacy_or_snapshot()
  let assert Error(_) = or_map.from_json(input)
  let assert Ok(map) =
    or_map.import_legacy(input, crdt.OrSetSpec, decode.string, rid("fresh"))
  let assert Ok(crdt.CrdtOrSet(value)) = or_map.get(map, "key")
  or_set.contains(value, "item")
  |> fn(value) {
    let assert True = value
  }
  let assert Ok(fresh) =
    or_map.update(or_map.remove(map, "key"), "key", fn(value) { value })
  let assert Ok(merged) = or_map.merge(map, fresh)
  let assert Ok(crdt.CrdtOrSet(value)) = or_map.get(merged, "key")
  or_set.contains(value, "item")
  |> fn(value) {
    let assert True = !value
  }
  let assert Error(_) =
    or_map.import_legacy(input, crdt.GSetSpec, decode.string, rid("fresh"))
  let delta_v1 = "{\"type\":\"or_map_delta\",\"v\":1,\"state\":{}}"
  let assert Error(_) = or_map.delta_from_json(delta_v1)
  let assert Error(_) = lww_map.from_json(legacy_lww(json.string("x")))
  Nil
}

fn modern_or_wire(
  clock: Int,
  generation_clock: Int,
  child: json.Json,
) -> String {
  let membership =
    or_set.new(rid("A")) |> or_set.add("key") |> or_set.remove("key")
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(3)),
    #(
      "state",
      json.object([
        #("replica_id", json.string("A")),
        #(
          "spec",
          json.string(
            crdt.spec_to_json_with(crdt.SequenceSpec, json.int)
            |> json.to_string,
          ),
        ),
        #("clock", json.int(clock)),
        #(
          "entries",
          json.array(
            [
              json.object([
                #("key", json.string("key")),
                #(
                  "generation",
                  json.object([
                    #("clock", json.int(generation_clock)),
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
                #("value", child),
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

pub fn protocol_rejects_unsupported_versions_schema_and_allocator_corruption_test() {
  let assert Error(_) =
    or_map.from_json_with(modern_or_wire(0, 1, json.null()), decode.int)
  let assert Error(_) =
    or_map.from_json_with(modern_or_wire(-1, 1, json.null()), decode.int)
  let assert Error(_) =
    or_map.from_json_with(modern_or_wire(1, -1, json.null()), decode.int)
  let wrong = crdt.CrdtGSet(g_set.new() |> g_set.add(1))
  let wrong =
    crdt.to_json_with(wrong, json.int) |> json.to_string |> json.string
  let assert Error(_) =
    or_map.from_json_with(modern_or_wire(1, 1, wrong), decode.int)
  let assert Ok(floor) =
    or_map.from_json_with(modern_or_wire(1, 1, json.null()), decode.int)
  or_map.keys(floor)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == []
  }
  let assert Ok(exhausted) =
    or_map.from_json_with(
      modern_or_wire(9_007_199_254_740_991, 9_007_199_254_740_991, json.null()),
      decode.int,
    )
  or_map.update(exhausted, "key", fn(value) { value })
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(crdt.ClockExhausted("key"))
  }
  or_map.from_json_with(
    or_map.to_json_with(floor, json.int) |> json.to_string,
    decode.int,
  )
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(floor)
  }
  list.each(
    ["or_map", "or_map_delta", "lww_map", "text", "crdt_delta"],
    fn(kind) {
      let unknown =
        json.object([#("type", json.string(kind)), #("v", json.int(99))])
        |> json.to_string
      crdt.from_json_with(unknown, decode.int)
      |> fn(result) {
        let assert Error(_) = result
      }
    },
  )
}

pub fn direct_dispatch_handles_same_immutable_lww_stamp_conflicts_test() {
  let map = lww_map.new(rid("A"), crdt.LwwRegisterSpec(0))
  let child = fn(n) { crdt.CrdtLwwRegister(lww_register.new(n, 1, rid("A"))) }
  let assert Ok(a) = lww_map.set(map, "key", child(1), 1)
  let assert Ok(b) = lww_map.set(map, "key", child(2), 1)
  let assert Ok(b) =
    crdt.from_json_with(
      crdt.to_json_with(crdt.CrdtLwwMap(b), json.int) |> json.to_string,
      decode.int,
    )
  crdt.merge(crdt.CrdtLwwMap(a), b, rid("R"))
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(crdt.ConflictingWrite("key", 1))
  }
  let assert Ok(tombstone) = lww_map.remove(map, "key", 1)
  let assert Ok(merged) = lww_map.merge(a, tombstone)
  let assert Ok(reverse) = lww_map.merge(tombstone, a)
  merged
  |> fn(assertion_actual) {
    let assert True = assertion_actual == reverse
  }
  lww_map.get(merged, "key")
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Error(Nil)
  }
}

pub fn legacy_string_leaf_dispatch_fixture_keeps_original_format_test() {
  let legacy =
    "{\"type\":\"g_set\",\"v\":1,\"state\":{\"elements\":[\"one\",\"two\"]}}"
  let actual =
    crdt.CrdtGSet(g_set.new() |> g_set.add("one") |> g_set.add("two"))
  let encoded = crdt.to_json(actual) |> json.to_string
  fixture.version(encoded)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == 1
  }
  crdt.from_json(encoded)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(actual)
  }
  crdt.from_json(legacy)
  |> fn(assertion_actual) {
    let assert True = assertion_actual == Ok(actual)
  }
}
