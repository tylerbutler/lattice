import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_text/text
import support/composition_fixture as fixture

fn rid() {
  replica_id.new("A")
}

fn schema(depth: Int, leaf: crdt.CrdtSpec(String)) {
  list.repeat(Nil, depth)
  |> list.fold(leaf, fn(child, _) { crdt.OrMapSpec(child) })
}

pub fn schema_encoded_bytes_grow_linearly_through_twenty_map_levels_test() {
  list.each([0, 1, 5, 10, 15, 20], fn(depth) {
    let spec = schema(depth, crdt.LwwRegisterSpec(""))
    let encoded = crdt.spec_to_json_with(spec, json.string) |> json.to_string
    // Each wrapper contributes one object, not another round of escaping.
    let assert True = string.byte_size(encoded) <= 64 * { depth + 1 }
    let assert Ok(decoded) = crdt.spec_from_json_with(encoded, decode.string)
    let assert True = decoded == spec
  })
}

fn mixed_snapshot(depth: Int, payload: String) {
  case depth {
    0 -> #(
      crdt.LwwRegisterSpec(payload),
      crdt.CrdtLwwRegister(lww_register.new(payload, 1, rid())),
    )
    _ -> {
      let #(spec, child) = mixed_snapshot(depth - 1, payload)
      case depth % 2 {
        0 -> {
          let assert Ok(map) =
            or_map.update(or_map.new(rid(), spec), "k", fn(_) { child })
          #(crdt.OrMapSpec(spec), crdt.CrdtOrMap(map))
        }
        _ -> {
          let assert Ok(map) =
            lww_map.set(lww_map.new(rid(), spec), "k", child, 1)
          #(crdt.LwwMapSpec(spec), crdt.CrdtLwwMap(map))
        }
      }
    }
  }
}

pub fn mixed_nested_snapshots_have_polynomial_encoded_size_test() {
  let payload = "{\"type\":\"or_map\",\"state\":\"\\\\quoted\"}"
  list.each([1, 2, 4, 8, 12], fn(depth) {
    let #(_, snapshot) = mixed_snapshot(depth, payload)
    let encoded = crdt.to_json(snapshot) |> json.to_string
    // Each stored child schema is repeated; that data is quadratic in depth.
    let assert True = string.byte_size(encoded) <= 2000 * depth * depth
    let assert Ok(decoded) = crdt.from_json(encoded)
    let assert True = decoded == snapshot
  })
}

fn append_nested(map: or_map.ORMap(String), depth: Int, content: String) {
  let assert Ok(pair) =
    or_map.update_delta(map, "k", fn(child, _) {
      case depth {
        1 -> {
          let assert crdt.CrdtText(value) = child
          let assert Ok(#(_, delta)) = text.append_with_delta(value, content)
          Ok(crdt.StateDelta(crdt.CrdtText(delta)))
        }
        _ -> {
          let assert crdt.CrdtOrMap(value) = child
          let #(_, delta) = append_nested(value, depth - 1, content)
          Ok(crdt.OrMapChange(delta))
        }
      }
    })
  pair
}

pub fn deep_sparse_delta_bytes_stay_bounded_and_apply_after_decode_test() {
  list.each([1, 2, 4, 8, 12], fn(depth) {
    let empty = or_map.new(rid(), schema(depth - 1, crdt.TextSpec))
    let #(before, _) = append_nested(empty, depth, string.repeat("x", 100))
    let #(after, delta) = append_nested(before, depth, "!")
    let wrapped = crdt.OrMapChange(delta)
    let encoded = crdt.delta_to_json(wrapped) |> json.to_string
    let assert True = string.byte_size(encoded) <= 3000 * depth * depth
    let assert Ok(decoded) = crdt.delta_from_json(encoded)
    let assert True = decoded == wrapped
    let assert Ok(decoded) =
      or_map.delta_from_json(or_map.delta_to_json(delta) |> json.to_string)
    let assert Ok(applied) = or_map.apply_delta(before, decoded)
    let assert True = applied == after
  })
}

fn field(input: decode.Dynamic, name: String) {
  let assert Ok(value) =
    decode.run(input, {
      use value <- decode.field(name, decode.dynamic)
      decode.success(value)
    })
  value
}

fn value_json(input: decode.Dynamic) {
  let assert Ok(value) = decode.run(input, fixture.json_decoder())
  value
}

fn fields_json(input, transform) {
  let assert Ok(fields) =
    decode.run(input, decode.dict(decode.string, decode.dynamic))
  dict.to_list(fields)
  |> list.map(fn(pair) { #(pair.0, transform(pair.0, pair.1)) })
  |> json.object
}

fn embedded(value: json.Json) {
  value |> json.to_string |> json.string
}

// Reproduce the old encoder only at known structural fields. In particular,
// register defaults and application record fields must not be transformed.
fn legacy_schema(input: decode.Dynamic) -> json.Json {
  let assert Ok(fields) =
    decode.run(input, decode.dict(decode.string, decode.dynamic))
  dict.to_list(fields)
  |> list.filter_map(fn(pair) {
    case pair {
      #("v", _) -> Error(Nil)
      #("child", child) -> Ok(#("child", embedded(legacy_schema(child))))
      #(key, value) -> Ok(#(key, value_json(value)))
    }
  })
  |> json.object
}

fn legacy_structure(input: decode.Dynamic) -> json.Json {
  let assert Ok(kind) = decode.run(field(input, "type"), decode.string)
  case kind {
    "or_map" | "or_map_delta" | "lww_map" -> {
      let state =
        fields_json(field(input, "state"), fn(key, value) {
          case key {
            "spec" -> embedded(legacy_schema(value))
            "entries" -> {
              let assert Ok(entries) =
                decode.run(value, decode.list(decode.dynamic))
              json.array(entries, fn(entry) {
                fields_json(entry, fn(key, value) {
                  case key {
                    "membership" -> embedded(value_json(value))
                    "value" -> {
                      let assert Ok(child) =
                        decode.run(value, decode.optional(decode.dynamic))
                      case child {
                        None -> json.null()
                        Some(child) -> embedded(legacy_structure(child))
                      }
                    }
                    _ -> value_json(value)
                  }
                })
              })
            }
            _ -> value_json(value)
          }
        })
      envelope(
        kind,
        case kind {
          "or_map_delta" -> 2
          _ -> 3
        },
        state,
      )
    }
    "crdt_delta" -> {
      let state = field(input, "state")
      let assert Ok(kind) = decode.run(field(state, "kind"), decode.string)
      let payload = field(state, "payload")
      envelope(
        "crdt_delta",
        1,
        json.object([
          #("kind", json.string(kind)),
          #(
            "payload",
            embedded(case kind {
              "none" -> legacy_schema(payload)
              _ -> legacy_structure(payload)
            }),
          ),
        ]),
      )
    }
    "text" -> envelope("text", 1, embedded(value_json(field(input, "state"))))
    _ -> value_json(input)
  }
}

fn envelope(kind, version, state) {
  json.object([
    #("type", json.string(kind)),
    #("v", json.int(version)),
    #("state", state),
  ])
}

fn old_wire(value: json.Json) {
  let assert Ok(input) = json.parse(json.to_string(value), decode.dynamic)
  legacy_structure(input) |> json.to_string
}

pub fn old_recursive_snapshots_and_schemas_keep_literal_application_strings_test() {
  let payload = "{\"type\":\"or_map\",\"child\":\"not a schema\"}"
  let #(spec, state) = mixed_snapshot(4, payload)
  let encoded = crdt.to_json(state) |> old_wire
  let assert Ok(decoded) = crdt.from_json(encoded)
  let assert True = decoded == state
  let assert Ok(schema_value) =
    json.parse(
      crdt.spec_to_json_with(spec, json.string) |> json.to_string,
      decode.dynamic,
    )
  let assert Ok(decoded_spec) =
    crdt.spec_from_json_with(
      legacy_schema(schema_value) |> json.to_string,
      decode.string,
    )
  let assert True = decoded_spec == spec
}

pub fn old_sparse_and_dispatch_delta_variants_decode_and_apply_test() {
  let before = or_map.new(rid(), schema(2, crdt.TextSpec))
  let #(after, delta) = append_nested(before, 3, "hello")
  let assert Ok(decoded) =
    or_map.delta_from_json(or_map.delta_to_json(delta) |> old_wire)
  let assert Ok(applied) = or_map.apply_delta(before, decoded)
  let assert True = applied == after
  list.each(
    [
      crdt.OrMapChange(delta),
      crdt.StateDelta(crdt.CrdtOrMap(after)),
      crdt.NoChange(schema(3, crdt.LwwRegisterSpec("\"literal\""))),
    ],
    fn(change) {
      let assert Ok(decoded) =
        crdt.delta_from_json(crdt.delta_to_json(change) |> old_wire)
      let assert True = decoded == change
    },
  )
  let assert Ok(plain) = text.append(text.new(rid()), "hello")
  let value = crdt.CrdtText(plain)
  let assert Ok(decoded) = crdt.from_json(crdt.to_json(value) |> old_wire)
  let assert True = decoded == value
}

pub fn optional_removed_children_survive_old_and_new_protocols_test() {
  let empty = lww_map.new(rid(), crdt.LwwRegisterSpec(""))
  let assert Ok(removed) = lww_map.remove(empty, "gone", 1)
  let empty_or = or_map.new(rid(), crdt.TextSpec)
  let #(active, _) = append_nested(empty_or, 1, "x")
  let #(removed_or, delta) = or_map.remove_with_delta(active, "k")
  list.each([crdt.CrdtLwwMap(removed), crdt.CrdtOrMap(removed_or)], fn(state) {
    let encoded = crdt.to_json(state)
    list.each([json.to_string(encoded), old_wire(encoded)], fn(input) {
      let assert Ok(decoded) = crdt.from_json(input)
      let assert True = decoded == state
    })
  })
  let encoded = or_map.delta_to_json(delta)
  list.each([json.to_string(encoded), old_wire(encoded)], fn(input) {
    let assert Ok(decoded) = or_map.delta_from_json(input)
    let assert Ok(applied) = or_map.apply_delta(active, decoded)
    let assert True = applied == removed_or
  })
}

fn wrong_schema(encoded: json.Json) {
  let assert Ok(input) = json.parse(json.to_string(encoded), decode.dynamic)
  fields_json(input, fn(key, value) {
    case key {
      "state" ->
        fields_json(value, fn(key, value) {
          case key {
            "spec" ->
              crdt.spec_to_json_with(crdt.LwwRegisterSpec(""), json.string)
            _ -> value_json(value)
          }
        })
      _ -> value_json(value)
    }
  })
  |> json.to_string
}

pub fn structured_snapshots_and_deltas_still_validate_child_schemas_test() {
  let empty = or_map.new(rid(), crdt.TextSpec)
  let #(active, delta) = append_nested(empty, 1, "x")
  let assert Error(_) = or_map.from_json(wrong_schema(or_map.to_json(active)))
  let assert Error(_) =
    or_map.delta_from_json(wrong_schema(or_map.delta_to_json(delta)))
  let assert Ok(text) = or_map.get(active, "k")
  let assert Ok(atomic) =
    lww_map.set(lww_map.new(rid(), crdt.TextSpec), "k", text, 1)
  let assert Error(_) = lww_map.from_json(wrong_schema(lww_map.to_json(atomic)))
  let assert Error(_) =
    crdt.spec_from_json_with("{\"type\":\"text\",\"v\":99}", decode.string)
  Nil
}
