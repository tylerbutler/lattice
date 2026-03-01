---
phase: 03-maps-serialization
plan: 04
type: execute
wave: 3
depends_on:
  - 01
  - 02
  - 03
files_modified:
  - src/lattice/lww_map.gleam
  - src/lattice/or_map.gleam
  - test/serialization/lww_map_json_test.gleam
  - test/serialization/or_map_json_test.gleam
  - test/property/serialization_property_test.gleam
autonomous: true
requirements:
  - JSON-15
  - JSON-16
  - JSON-17
  - JSON-18

must_haves:
  truths:
    - "LWW-Map to_json produces self-describing JSON with type 'lww_map', v 1, and entries state"
    - "LWW-Map from_json reconstructs identical LWWMap from JSON string"
    - "LWW-Map round-trip preserves tombstones: removed keys stay removed after round-trip"
    - "OR-Map to_json encodes crdt_spec, key OR-Set, and values dict with nested CRDT JSON"
    - "OR-Map from_json reconstructs ORMap with correct nested CRDT values"
    - "OR-Map round-trip: active keys and their values preserved"
    - "Property test: from_json(json.to_string(to_json(x))) round-trip holds for all CRDT types"
    - "Property test: serialization preserves merge commutativity for counters"
  artifacts:
    - path: "src/lattice/lww_map.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/or_map.gleam"
      provides: "to_json and from_json functions added"
    - path: "test/serialization/lww_map_json_test.gleam"
      provides: "LWW-Map JSON round-trip tests"
    - path: "test/serialization/or_map_json_test.gleam"
      provides: "OR-Map JSON round-trip tests including nested CRDT values"
    - path: "test/property/serialization_property_test.gleam"
      provides: "Property-based round-trip tests for all CRDT types"
  key_links:
    - from: "src/lattice/lww_map.gleam"
      to: "gleam/json"
      via: "JSON encoding/decoding"
      pattern: "import gleam/json"
    - from: "src/lattice/or_map.gleam"
      to: "lattice/crdt"
      via: "crdt.to_json and crdt.from_json for nested CRDT values"
      pattern: "import lattice/crdt"
    - from: "src/lattice/or_map.gleam"
      to: "src/lattice/or_set.gleam"
      via: "or_set.to_json/from_json for key set serialization"
      pattern: "import lattice/or_set"
---

<objective>
Add JSON serialization to LWW-Map and OR-Map, then create property-based round-trip tests verifying serialization correctness across all CRDT types. OR-Map JSON is the most complex because it contains nested typed CRDT values.

Purpose: Complete the serialization story for all CRDT types and prove correctness with property tests
Output: Map types serialize/deserialize correctly, property tests verify round-trip for all types
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/03-maps-serialization/03-CONTEXT.md
@.planning/phases/03-maps-serialization/03-RESEARCH.md
@.planning/phases/03-maps-serialization/03-maps-serialization-01-SUMMARY.md
@.planning/phases/03-maps-serialization/03-maps-serialization-02-SUMMARY.md
@.planning/phases/03-maps-serialization/03-maps-serialization-03-SUMMARY.md

# Source files to modify:
@src/lattice/lww_map.gleam
@src/lattice/or_map.gleam
@src/lattice/crdt.gleam

<interfaces>
<!-- LWW-Map type (from Plan 01) -->
LWWMap(entries: Dict(String, #(Option(String), Int)))
  - entries: key -> (value_or_tombstone, timestamp)
  - Option(String): Some(val) = active, None = tombstoned

<!-- OR-Map type (from Plan 03) -->
ORMap(
  replica_id: String,
  crdt_spec: CrdtSpec,
  key_set: ORSet(String),
  values: Dict(String, Crdt),
)

<!-- CrdtSpec (from Plan 03) -->
GCounterSpec | PnCounterSpec | LwwRegisterSpec | MvRegisterSpec | GSetSpec | TwoPSetSpec | OrSetSpec

<!-- Available serialization functions (from Plan 02) -->
g_counter.to_json/from_json, pn_counter.to_json/from_json, version_vector.to_json/from_json
lww_register.to_json/from_json, mv_register.to_json/from_json
g_set.to_json/from_json, two_p_set.to_json/from_json, or_set.to_json/from_json

<!-- Generic dispatch (from Plan 03) -->
crdt.to_json(Crdt) -> json.Json
crdt.from_json(String) -> Result(Crdt, json.DecodeError)
</interfaces>

# JSON format: {"type": "<type_name>", "v": 1, "state": {...}}
# For LWW-Map, encode entries as a list of objects with key, value (nullable), timestamp
# For OR-Map:
#   - crdt_spec as a string tag
#   - key_set via or_set.to_json (includes full OR-Set state)
#   - values as dict of key -> nested CRDT JSON (each using crdt.to_json)
#   NOTE: Nested CRDTs include their own "type" tag so crdt.from_json can dispatch

# Property tests follow established qcheck pattern:
# small_test_config: test_count: 10, max_retries: 3, seed: qcheck.seed(42)
# Generate simple parameters, construct CRDTs in test body
# Compare on value() output for types where structural equality may differ
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: LWW-Map and OR-Map JSON serialization (JSON-15 to JSON-18)</name>
  <files>src/lattice/lww_map.gleam, src/lattice/or_map.gleam, test/serialization/lww_map_json_test.gleam, test/serialization/or_map_json_test.gleam</files>
  <behavior>
    LWW-Map JSON:
    - Test: to_json on map with active entries produces correct JSON structure
    - Test: to_json on map with tombstoned entries preserves tombstone info (None encoded as null)
    - Test: from_json round-trip on map with only active entries
    - Test: from_json round-trip on map with both active and tombstoned entries
    - Test: from_json on empty map

    OR-Map JSON:
    - Test: to_json on empty OR-Map produces correct structure with crdt_spec tag
    - Test: to_json on OR-Map with G-Counter values encodes nested CRDT JSON
    - Test: from_json round-trip on OR-Map with single key
    - Test: from_json round-trip on OR-Map with multiple keys — compare keys() and value of each
    - Test: from_json round-trip preserves crdt_spec
  </behavior>
  <action>
**LWW-Map JSON (JSON-15, JSON-16)** — Add to src/lattice/lww_map.gleam:

Add imports: `import gleam/json`, `import gleam/dynamic/decode`

Encode entries as a JSON array of objects. Each entry has key, value (nullable), and timestamp:
```gleam
pub fn to_json(map: LWWMap) -> json.Json {
  let LWWMap(entries) = map
  let entries_json = json.array(dict.to_list(entries), fn(pair) {
    let #(key, #(opt_value, timestamp)) = pair
    json.object([
      #("key", json.string(key)),
      #("value", case opt_value {
        Some(v) -> json.string(v)
        None -> json.null()
      }),
      #("timestamp", json.int(timestamp)),
    ])
  })
  json.object([
    #("type", json.string("lww_map")),
    #("v", json.int(1)),
    #("state", json.object([
      #("entries", entries_json),
    ])),
  ])
}
```

For from_json, decode the entries array and reconstruct Dict:
```gleam
pub fn from_json(json_string: String) -> Result(LWWMap, json.DecodeError) {
  let entry_decoder = {
    use key <- decode.field("key", decode.string)
    use opt_value <- decode.field("value", decode.optional(decode.string))
    use timestamp <- decode.field("timestamp", decode.int)
    decode.success(#(key, #(opt_value, timestamp)))
  }
  let decoder = {
    use state <- decode.field("state", {
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      decode.success(LWWMap(entries: dict.from_list(entries_list)))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

NOTE: `decode.optional(decode.string)` returns `Option(String)` — `Some(v)` for strings, `None` for JSON null. This maps directly to the tombstone representation.

**OR-Map JSON (JSON-17, JSON-18)** — Add to src/lattice/or_map.gleam:

Add imports: `import gleam/json`, `import gleam/dynamic/decode`

The OR-Map JSON must encode:
1. crdt_spec as a string tag (e.g., "g_counter")
2. key_set using or_set.to_json (the full OR-Set state as JSON)
3. values dict where each value uses crdt.to_json (which includes its own type tag)

```gleam
fn spec_to_string(spec: CrdtSpec) -> String {
  case spec {
    crdt.GCounterSpec -> "g_counter"
    crdt.PnCounterSpec -> "pn_counter"
    crdt.LwwRegisterSpec -> "lww_register"
    crdt.MvRegisterSpec -> "mv_register"
    crdt.GSetSpec -> "g_set"
    crdt.TwoPSetSpec -> "two_p_set"
    crdt.OrSetSpec -> "or_set"
  }
}

fn string_to_spec(s: String) -> Result(CrdtSpec, Nil) {
  case s {
    "g_counter" -> Ok(crdt.GCounterSpec)
    "pn_counter" -> Ok(crdt.PnCounterSpec)
    "lww_register" -> Ok(crdt.LwwRegisterSpec)
    "mv_register" -> Ok(crdt.MvRegisterSpec)
    "g_set" -> Ok(crdt.GSetSpec)
    "two_p_set" -> Ok(crdt.TwoPSetSpec)
    "or_set" -> Ok(crdt.OrSetSpec)
    _ -> Error(Nil)
  }
}

pub fn to_json(map: ORMap) -> json.Json {
  let ORMap(replica_id, crdt_spec, key_set, values) = map
  // Encode each value as its full typed JSON string, then embed as nested JSON
  // Since json.Json is the type, we can embed directly
  let values_json = json.array(dict.to_list(values), fn(pair) {
    let #(key, crdt_val) = pair
    json.object([
      #("key", json.string(key)),
      #("crdt", crdt.to_json(crdt_val)),
    ])
  })
  json.object([
    #("type", json.string("or_map")),
    #("v", json.int(1)),
    #("state", json.object([
      #("replica_id", json.string(replica_id)),
      #("crdt_spec", json.string(spec_to_string(crdt_spec))),
      #("key_set", or_set.to_json(key_set)),
      #("values", values_json),
    ])),
  ])
}
```

For from_json, OR-Map needs special handling because:
- key_set is a nested OR-Set JSON (with its own "type" wrapper)
- Each value in values array is a nested CRDT JSON (with its own "type" wrapper)

The nested JSON objects are embedded directly (not as strings). So the decoder needs to handle nested JSON objects, not nested JSON strings.

CRITICAL: The nested CRDTs (key_set and values) are embedded as JSON objects, NOT as JSON strings. This means we can't use `crdt.from_json(json_string)` directly — that expects a string. We need a different approach.

**Two options:**
(a) Embed nested CRDTs as JSON strings (double-encoded) — then crdt.from_json works
(b) Create internal decoders that work on the decoded Dynamic value, not on a String

Option (a) is simpler but produces ugly JSON. Option (b) is cleaner.

For v1, use option (a) with a helper: encode nested JSON as strings, decode by re-parsing.

Actually, the cleanest approach: the `or_set.to_json` returns a `json.Json` value. When embedded in the parent JSON object, it becomes a nested JSON object (not a string). So the decoder receives it as a nested object. We need to re-serialize the nested object to a string to pass to `or_set.from_json`.

This is awkward. Alternative: create `or_set.decoder()` that returns a `decode.Decoder(ORSet(String))` (works on Dynamic), and similarly `crdt.decoder()`. Then use those decoders directly in the parent decoder instead of going through string round-trip.

Let me recommend this approach: Add a `decoder()` function to each module that returns a `decode.Decoder(T)` (works on Dynamic), separate from `from_json(String)`. The `from_json` function becomes `json.parse(from: str, using: decoder())`.

BUT this is a significant refactor to all 8 modules. For v1 pragmatism, encode nested CRDTs as JSON STRINGS:

```gleam
// In or_map.to_json:
let values_json = json.array(dict.to_list(values), fn(pair) {
  let #(key, crdt_val) = pair
  json.object([
    #("key", json.string(key)),
    #("crdt", json.string(json.to_string(crdt.to_json(crdt_val)))),
  ])
})
// key_set similarly:
#("key_set", json.string(json.to_string(or_set.to_json(key_set)))),
```

Then in from_json:
```gleam
use key_set_str <- decode.field("key_set", decode.string)
// parse the string into an ORSet
let key_set_result = or_set.from_json(key_set_str)
```

This is the pragmatic v1 approach. The JSON is slightly less clean (nested objects are double-encoded as strings) but it works with the existing from_json(String) API without refactoring everything.

ALTERNATIVE (Claude's discretion — preferred if time allows): Embed as proper nested JSON objects and add a `decoder() -> decode.Decoder(T)` function to or_set and crdt modules. The from_json function calls `json.parse(from: str, using: decoder())`. Then or_map's from_json uses the decoder directly for nested fields. This is cleaner JSON and a better API pattern. The existing from_json functions simply become wrappers around decoder().

Choose whichever approach compiles and passes tests. The double-encoding approach is guaranteed to work with existing APIs. The decoder() approach is cleaner but requires touching more files (or_set and crdt modules).

**Tests** — test/serialization/lww_map_json_test.gleam, or_map_json_test.gleam:

LWW-Map tests:
```gleam
pub fn lww_map_round_trip_active__test() {
  let map = lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.set("age", "30", 2)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      lww_map.get(d, "name") |> expect.to_equal(Ok("Alice"))
      lww_map.get(d, "age") |> expect.to_equal(Ok("30"))
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn lww_map_round_trip_tombstone__test() {
  let map = lww_map.new()
    |> lww_map.set("name", "Alice", 1)
    |> lww_map.remove("name", 5)
  let json_str = json.to_string(lww_map.to_json(map))
  let decoded = lww_map.from_json(json_str)
  case decoded {
    Ok(d) -> lww_map.get(d, "name") |> expect.to_equal(Error(Nil))
    Error(_) -> expect.to_be_true(False)
  }
}
```

OR-Map tests:
```gleam
pub fn or_map_round_trip__test() {
  let map = or_map.new("A", crdt.GCounterSpec)
  let map = or_map.update(map, "score", fn(c) {
    case c {
      crdt.CrdtGCounter(counter) -> crdt.CrdtGCounter(g_counter.increment(counter, 5))
      _ -> c
    }
  })
  let json_str = json.to_string(or_map.to_json(map))
  let decoded = or_map.from_json(json_str)
  case decoded {
    Ok(d) -> {
      // Check keys match
      set.from_list(or_map.keys(d)) |> expect.to_equal(set.from_list(or_map.keys(map)))
      // Check value
      case or_map.get(d, "score") {
        Ok(crdt.CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(5)
        _ -> expect.to_be_true(False)
      }
    }
    Error(_) -> expect.to_be_true(False)
  }
}
```
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>LWW-Map to_json/from_json round-trip works for active and tombstoned entries; OR-Map to_json/from_json round-trip works with nested CRDT values; crdt_spec preserved in OR-Map round-trip; all JSON round-trip tests pass</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Serialization property tests (round-trip for all types)</name>
  <files>test/property/serialization_property_test.gleam</files>
  <behavior>
    - Property: G-Counter round-trip: from_json(json.to_string(to_json(c))) produces Ok with same value()
    - Property: PN-Counter round-trip: same pattern
    - Property: LWW-Register round-trip
    - Property: G-Set round-trip: compare value() sets
    - Property: 2P-Set round-trip: compare value() sets
    - Property: OR-Set round-trip: compare value() sets
    - Property: LWW-Map round-trip: compare get() for same keys
    - Property: Serialization preserves merge: to_json(merge(a,b)) decoded equals merge of decoded a and b (for G-Counter)
  </behavior>
  <action>
Create test/property/serialization_property_test.gleam.

Follow the established qcheck pattern from test/property/counter_property_test.gleam:

```gleam
import gleam/json
import gleam/list
import gleam/set
import lattice/g_counter
import lattice/pn_counter
import lattice/lww_register
import lattice/g_set
import lattice/two_p_set
import lattice/or_set
import lattice/lww_map
import qcheck
import startest/expect

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}
```

**G-Counter round-trip property:**
```gleam
pub fn g_counter_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a_delta, b_delta) = pair
      let counter = g_counter.new("A") |> g_counter.increment(a_delta)
      let counter2 = g_counter.new("B") |> g_counter.increment(b_delta)
      let merged = g_counter.merge(counter, counter2)
      let json_str = json.to_string(g_counter.to_json(merged))
      let decoded = g_counter.from_json(json_str)
      case decoded {
        Ok(d) -> g_counter.value(d) |> expect.to_equal(g_counter.value(merged))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```

**PN-Counter round-trip property:**
```gleam
pub fn pn_counter_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 50),
      qcheck.bounded_int(0, 50),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(inc, dec) = pair
      let counter = pn_counter.new("A")
        |> pn_counter.increment(inc)
        |> pn_counter.decrement(dec)
      let json_str = json.to_string(pn_counter.to_json(counter))
      let decoded = pn_counter.from_json(json_str)
      case decoded {
        Ok(d) -> pn_counter.value(d) |> expect.to_equal(pn_counter.value(counter))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```

**LWW-Register round-trip property:**
```gleam
pub fn lww_register_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 100),
    fn(ts) {
      let reg = lww_register.new("value_" <> int.to_string(ts), ts)
      let json_str = json.to_string(lww_register.to_json(reg))
      let decoded = lww_register.from_json(json_str)
      case decoded {
        Ok(d) -> {
          lww_register.value(d) |> expect.to_equal(lww_register.value(reg))
        }
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```
NOTE: Need `import gleam/int` for `int.to_string`.

**G-Set round-trip property:**
```gleam
pub fn g_set_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let s = g_set.new()
        |> g_set.add(int.to_string(a))
        |> g_set.add(int.to_string(b))
      let json_str = json.to_string(g_set.to_json(s))
      let decoded = g_set.from_json(json_str)
      case decoded {
        Ok(d) -> g_set.value(d) |> expect.to_equal(g_set.value(s))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```

**2P-Set round-trip property:**
```gleam
pub fn two_p_set_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 10),
    fn(n) {
      let s = two_p_set.new()
        |> two_p_set.add(int.to_string(n))
        |> two_p_set.add(int.to_string(n + 1))
        |> two_p_set.remove(int.to_string(n))
      let json_str = json.to_string(two_p_set.to_json(s))
      let decoded = two_p_set.from_json(json_str)
      case decoded {
        Ok(d) -> two_p_set.value(d) |> expect.to_equal(two_p_set.value(s))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```

**OR-Set round-trip property:**
```gleam
pub fn or_set_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 10),
    fn(n) {
      let s = or_set.new("A")
        |> or_set.add(int.to_string(n))
        |> or_set.add(int.to_string(n + 1))
      let json_str = json.to_string(or_set.to_json(s))
      let decoded = or_set.from_json(json_str)
      case decoded {
        Ok(d) -> or_set.value(d) |> expect.to_equal(or_set.value(s))
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```

**LWW-Map round-trip property:**
```gleam
pub fn lww_map_json_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(1, 100),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(val, ts) = pair
      let map = lww_map.new()
        |> lww_map.set("key1", int.to_string(val), ts)
        |> lww_map.set("key2", "fixed", ts + 1)
      let json_str = json.to_string(lww_map.to_json(map))
      let decoded = lww_map.from_json(json_str)
      case decoded {
        Ok(d) -> {
          lww_map.get(d, "key1") |> expect.to_equal(lww_map.get(map, "key1"))
          lww_map.get(d, "key2") |> expect.to_equal(lww_map.get(map, "key2"))
        }
        Error(_) -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```

**Merge-preserving property (G-Counter):**
```gleam
pub fn g_counter_merge_after_serialize__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a_delta, b_delta) = pair
      let ca = g_counter.new("A") |> g_counter.increment(a_delta)
      let cb = g_counter.new("B") |> g_counter.increment(b_delta)
      // Serialize both, deserialize, merge deserialized
      let ca_json = json.to_string(g_counter.to_json(ca))
      let cb_json = json.to_string(g_counter.to_json(cb))
      case g_counter.from_json(ca_json), g_counter.from_json(cb_json) {
        Ok(da), Ok(db) -> {
          let merged_original = g_counter.merge(ca, cb)
          let merged_deserialized = g_counter.merge(da, db)
          g_counter.value(merged_deserialized)
          |> expect.to_equal(g_counter.value(merged_original))
        }
        _, _ -> expect.to_be_true(False)
      }
      Nil
    },
  )
}
```

PITFALL: Always use small_test_config to prevent qcheck timeout.
PITFALL: Keep generators simple — bounded_int, small_non_negative_int. Construct CRDTs in test body.
PITFALL: Compare on value() / get() output, not structural equality, for types with non-deterministic internal ordering (sets, OR-Set, MV-Register).
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>Property tests pass for G-Counter, PN-Counter, LWW-Register, G-Set, 2P-Set, OR-Set, LWW-Map round-trip; merge-preserving property passes for G-Counter; all property tests complete without timeout using small_test_config</done>
</task>

</tasks>

<verification>
Run `gleam test` - ALL tests pass (maps, serialization, property tests, plus all prior tests)
Run `gleam check` - no type errors
Confirm all 10 CRDT types + Version Vector have working to_json/from_json
Confirm property tests run without timeout
</verification>

<success_criteria>
- LWW-Map to_json/from_json works including tombstoned entries
- OR-Map to_json/from_json works with nested CRDT values
- OR-Map preserves crdt_spec and active keys through serialization
- Property-based round-trip tests pass for G-Counter, PN-Counter, LWW-Register, G-Set, 2P-Set, OR-Set, LWW-Map
- Merge-preserving serialization property verified for G-Counter
- All property tests complete within timeout (small_test_config)
- All prior tests continue to pass
- Type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/03-maps-serialization/03-maps-serialization-04-SUMMARY.md`
</output>
