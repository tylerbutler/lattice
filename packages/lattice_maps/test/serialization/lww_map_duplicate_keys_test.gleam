import gleam/dynamic/decode
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option, None, Some}
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_registers/lww_register

fn rid(value: String) {
  replica_id.new(value)
}

fn embedded(value: Json) -> Json {
  json.string(json.to_string(value))
}

fn optional_json(value: Option(a), encode: fn(a) -> Json) -> Json {
  case value {
    Some(value) -> encode(value)
    None -> json.null()
  }
}

fn modern_entry(key: String, value: Option(String), timestamp: Int) -> Json {
  json.object([
    #("key", json.string(key)),
    #("timestamp", json.int(timestamp)),
    #(
      "provenance",
      json.object([
        #("kind", json.string("modern")),
        #("writer", json.string("writer")),
      ]),
    ),
    #(
      "value",
      optional_json(value, fn(value) {
        crdt.CrdtLwwRegister(lww_register.new(value, timestamp, rid("writer")))
        |> crdt.to_json
        |> embedded
      }),
    ),
  ])
}

fn modern_snapshot(entries: List(Json)) -> String {
  json.object([
    #("type", json.string("lww_map")),
    #("v", json.int(3)),
    #(
      "state",
      json.object([
        #("replica_id", json.string("writer")),
        #(
          "spec",
          crdt.spec_to_json_with(crdt.LwwRegisterSpec(""), json.string)
            |> embedded,
        ),
        #("pruned_timestamp", json.int(0)),
        #("entries", json.array(entries, fn(entry) { entry })),
      ]),
    ),
  ])
  |> json.to_string
}

fn legacy_entry(key: String, value: Option(String), timestamp: Int) -> Json {
  json.object([
    #("key", json.string(key)),
    #("value", optional_json(value, json.string)),
    #("timestamp", json.int(timestamp)),
  ])
}

fn legacy_snapshot(version: Int, entries: List(Json)) -> String {
  let state_fields = [
    #("entries", json.array(entries, fn(entry) { entry })),
  ]
  let state_fields = case version {
    1 -> state_fields
    _ -> [#("pruned_timestamp", json.int(7)), ..state_fields]
  }
  json.object([
    #("type", json.string("lww_map")),
    #("v", json.int(version)),
    #("state", json.object(state_fields)),
  ])
  |> json.to_string
}

fn expect_duplicate_error(result: Result(a, json.DecodeError)) {
  let assert Error(json.UnableToDecode([
    decode.DecodeError(expected, found, path),
  ])) = result
  expected
  |> fn(assertion_actual) {
    let assert True = assertion_actual == "unique keys"
  }
  found
  |> fn(assertion_actual) {
    let assert True = assertion_actual == "duplicate key"
  }
  path
  |> fn(assertion_actual) {
    let assert True = assertion_actual == ["entries"]
  }
}

fn expect_modern_paths_reject(entries: List(Json)) {
  let snapshot = modern_snapshot(entries)
  lww_map.from_json(snapshot) |> expect_duplicate_error
  lww_map.from_json_with(snapshot, decode.string) |> expect_duplicate_error
  crdt.from_json(snapshot) |> expect_duplicate_error
  crdt.from_json_with(snapshot, decode.string) |> expect_duplicate_error
}

pub fn modern_lww_map_snapshot_paths_reject_duplicate_keys_test() {
  let live = modern_entry("key", Some("value"), 10)
  let tombstone = modern_entry("key", None, 10)
  let scenarios = [
    [live, live],
    [
      modern_entry("key", Some("newer"), 20),
      modern_entry("key", Some("older"), 10),
    ],
    [
      modern_entry("key", Some("older"), 10),
      modern_entry("key", Some("newer"), 20),
    ],
    [
      modern_entry("key", Some("first"), 10),
      modern_entry("key", Some("second"), 10),
    ],
    [live, tombstone],
    [tombstone, live],
    [
      modern_entry("\u{e9}", Some("first"), 10),
      modern_entry("\u{e9}", Some("second"), 11),
    ],
  ]
  list.each(scenarios, expect_modern_paths_reject)
}

pub fn legacy_lww_map_snapshots_reject_duplicate_keys_test() {
  let live = legacy_entry("key", Some("value"), 10)
  let tombstone = legacy_entry("key", None, 10)
  let scenarios = [
    [live, live],
    [
      legacy_entry("key", Some("newer"), 20),
      legacy_entry("key", Some("older"), 10),
    ],
    [
      legacy_entry("key", Some("older"), 10),
      legacy_entry("key", Some("newer"), 20),
    ],
    [
      legacy_entry("key", Some("first"), 10),
      legacy_entry("key", Some("second"), 10),
    ],
    [live, tombstone],
    [tombstone, live],
    [
      legacy_entry("\u{e9}", Some("first"), 10),
      legacy_entry("\u{e9}", Some("second"), 11),
    ],
  ]
  list.each([1, 2], fn(version) {
    list.each(scenarios, fn(entries) {
      lww_map.import_legacy(
        legacy_snapshot(version, entries),
        crdt.LwwRegisterSpec(""),
        rid("importer"),
      )
      |> expect_duplicate_error
    })
  })
}

pub fn lww_map_snapshot_keys_are_not_unicode_normalized_test() {
  let composed = "\u{e9}"
  let decomposed = "e\u{301}"
  let modern =
    modern_snapshot([
      modern_entry(composed, Some("composed"), 10),
      modern_entry(decomposed, Some("decomposed"), 11),
    ])
  let assert Ok(modern) = lww_map.from_json(modern)
  lww_map.get(modern, composed)
  |> fn(actual) {
    let assert True =
      actual
      == Ok(
        crdt.CrdtLwwRegister(lww_register.new("composed", 10, rid("writer"))),
      )
  }
  lww_map.get(modern, decomposed)
  |> fn(actual) {
    let assert True =
      actual
      == Ok(
        crdt.CrdtLwwRegister(lww_register.new("decomposed", 11, rid("writer"))),
      )
  }

  list.each([1, 2], fn(version) {
    let snapshot =
      legacy_snapshot(version, [
        legacy_entry(composed, Some("composed"), 10),
        legacy_entry(decomposed, Some("decomposed"), 11),
      ])
    let assert Ok(legacy) =
      lww_map.import_legacy(snapshot, crdt.LwwRegisterSpec(""), rid("importer"))
    lww_map.keys(legacy)
    |> list.length
    |> fn(assertion_actual) {
      let assert True = assertion_actual == 2
    }
  })
}
