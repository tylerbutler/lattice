---
phase: 03-maps-serialization
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - src/lattice/g_counter.gleam
  - src/lattice/pn_counter.gleam
  - src/lattice/version_vector.gleam
  - src/lattice/lww_register.gleam
  - src/lattice/mv_register.gleam
  - src/lattice/g_set.gleam
  - src/lattice/two_p_set.gleam
  - src/lattice/or_set.gleam
  - test/serialization/counter_json_test.gleam
  - test/serialization/register_json_test.gleam
  - test/serialization/set_json_test.gleam
  - test/serialization/version_vector_json_test.gleam
autonomous: true
requirements:
  - JSON-01
  - JSON-02
  - JSON-03
  - JSON-04
  - JSON-05
  - JSON-06
  - JSON-07
  - JSON-08
  - JSON-09
  - JSON-10
  - JSON-11
  - JSON-12
  - JSON-13
  - JSON-14
  - JSON-19
  - JSON-20

must_haves:
  truths:
    - "G-Counter to_json produces {type: 'g_counter', v: 1, state: {self_id, counts}}"
    - "G-Counter from_json reconstructs identical GCounter from JSON string"
    - "PN-Counter to_json encodes positive and negative G-Counter states"
    - "PN-Counter from_json reconstructs PNCounter from JSON string"
    - "Version Vector to_json encodes clocks as JSON dict"
    - "Version Vector from_json reconstructs VersionVector from JSON string"
    - "LWW-Register to_json encodes value and timestamp"
    - "LWW-Register from_json reconstructs LWWRegister from JSON string"
    - "MV-Register to_json encodes replica_id, entries with tags, and vclock"
    - "MV-Register from_json reconstructs MVRegister from JSON string"
    - "G-Set to_json encodes elements as JSON array"
    - "G-Set from_json reconstructs GSet from JSON string"
    - "2P-Set to_json encodes added and removed sets as JSON arrays"
    - "2P-Set from_json reconstructs TwoPSet from JSON string"
    - "OR-Set to_json encodes replica_id, counter, and entries with tag objects"
    - "OR-Set from_json reconstructs ORSet from JSON string"
    - "All to_json outputs include type tag and version field"
    - "Round-trip: from_json(json.to_string(to_json(x))) == Ok(x) for simple types"
  artifacts:
    - path: "src/lattice/g_counter.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/pn_counter.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/version_vector.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/lww_register.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/mv_register.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/g_set.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/two_p_set.gleam"
      provides: "to_json and from_json functions added"
    - path: "src/lattice/or_set.gleam"
      provides: "to_json and from_json functions added"
    - path: "test/serialization/counter_json_test.gleam"
      provides: "Round-trip tests for G-Counter and PN-Counter JSON"
    - path: "test/serialization/register_json_test.gleam"
      provides: "Round-trip tests for LWW-Register and MV-Register JSON"
    - path: "test/serialization/set_json_test.gleam"
      provides: "Round-trip tests for G-Set, 2P-Set, and OR-Set JSON"
    - path: "test/serialization/version_vector_json_test.gleam"
      provides: "Round-trip tests for Version Vector JSON"
  key_links:
    - from: "src/lattice/g_counter.gleam"
      to: "gleam/json"
      via: "json.object, json.string, json.int, json.dict for encoding"
      pattern: "import gleam/json"
    - from: "src/lattice/g_counter.gleam"
      to: "gleam/dynamic/decode"
      via: "decode.field, decode.string, decode.int, decode.dict for decoding"
      pattern: "import gleam/dynamic/decode"
---

<objective>
Add JSON serialization (to_json/from_json) to all 8 existing leaf CRDT types plus Version Vector. Each type gets a self-describing JSON format with type tag and version field. This is the bulk serialization work — formulaic across all types.

Purpose: Enable all existing CRDT types to serialize/deserialize to JSON for persistence and cross-target compatibility
Output: 8 modules updated with to_json/from_json, comprehensive round-trip unit tests
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

# Source files to modify:
@src/lattice/g_counter.gleam
@src/lattice/pn_counter.gleam
@src/lattice/version_vector.gleam
@src/lattice/lww_register.gleam
@src/lattice/mv_register.gleam
@src/lattice/g_set.gleam
@src/lattice/two_p_set.gleam
@src/lattice/or_set.gleam

<interfaces>
<!-- Current type definitions from existing modules -->

From src/lattice/g_counter.gleam:
  pub type GCounter { GCounter(dict: dict.Dict(String, Int), self_id: String) }

From src/lattice/pn_counter.gleam:
  pub type PNCounter { PNCounter(positive: g_counter.GCounter, negative: g_counter.GCounter) }

From src/lattice/version_vector.gleam:
  pub type VersionVector { VersionVector(dict: dict.Dict(String, Int)) }

From src/lattice/lww_register.gleam:
  pub type LWWRegister(a) { LWWRegister(value: a, timestamp: Int) }

From src/lattice/mv_register.gleam:
  pub type Tag { Tag(replica_id: String, counter: Int) }
  pub type MVRegister(a) { MVRegister(replica_id: String, entries: dict.Dict(Tag, a), vclock: VersionVector) }

From src/lattice/g_set.gleam:
  pub type GSet(a) { GSet(elements: set.Set(a)) }

From src/lattice/two_p_set.gleam:
  pub type TwoPSet(a) { TwoPSet(added: set.Set(a), removed: set.Set(a)) }

From src/lattice/or_set.gleam:
  pub type Tag { Tag(replica_id: String, counter: Int) }
  pub type ORSet(a) { ORSet(replica_id: String, counter: Int, entries: dict.Dict(a, set.Set(Tag))) }
</interfaces>

# JSON format: {"type": "<type_name>", "v": 1, "state": {...}}
# Use gleam/json for encoding, gleam/dynamic/decode for decoding
# Use json.parse(from: json_string, using: decoder) as entry point

# CRITICAL API patterns (verified in research):
# Encoding: json.object([#("key", json.string("val"))]), json.dict(d, keys: fn(k) -> k, values: json.int)
# Decoding: use self_id <- decode.field("self_id", decode.string) then decode.success(...)
# Sets: json.array(set.to_list(s), of: json.string) / decode.map(decode.list(decode.string), set.from_list)
# Output: json.to_string(json) -> String
# Parse: json.parse(from: string, using: decoder) -> Result(T, json.DecodeError)

# IMPORTANT: LWW-Register and G-Set/2P-Set/OR-Set are parameterized types.
# For JSON serialization in v1, constrain to String values:
# - LWWRegister(String) — to_json/from_json work with String values
# - GSet(String), TwoPSet(String), ORSet(String) — elements are Strings
# - MVRegister(String) — values are Strings
# This is a v1 simplification per research open question #2.

# PITFALL: MV-Register entries are Dict(Tag, a) where Tag is a custom type.
# Custom types can't be JSON dict keys directly. Encode entries as a JSON array
# of objects: [{"tag": {"r": "A", "c": 1}, "value": "hello"}, ...]
# Decode back by folding the array into a Dict(Tag, String).

# PITFALL: OR-Set entries are Dict(a, set.Set(Tag)).
# Encode as a JSON dict (String keys) where values are arrays of tag objects.
# Use json.dict for the outer dict, json.array for tag sets.
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: JSON for counters, clock, and registers (JSON-01 to JSON-08, JSON-19, JSON-20)</name>
  <files>src/lattice/g_counter.gleam, src/lattice/pn_counter.gleam, src/lattice/version_vector.gleam, src/lattice/lww_register.gleam, src/lattice/mv_register.gleam, test/serialization/counter_json_test.gleam, test/serialization/register_json_test.gleam, test/serialization/version_vector_json_test.gleam</files>
  <behavior>
    G-Counter JSON round-trip:
    - Test: to_json(new("A") |> increment(5)) produces JSON with type "g_counter", v 1, state with self_id and counts
    - Test: from_json(json.to_string(to_json(counter))) == Ok(counter) for a counter with multiple replicas

    PN-Counter JSON round-trip:
    - Test: to_json encodes positive and negative G-Counter states nested
    - Test: from_json(json.to_string(to_json(pn))) == Ok(pn) for incremented+decremented counter

    Version Vector JSON round-trip:
    - Test: to_json(vv) produces JSON with type "version_vector" and clocks dict
    - Test: from_json(json.to_string(to_json(vv))) == Ok(vv) for multi-replica vector

    LWW-Register JSON round-trip:
    - Test: to_json(new("hello", 42)) produces JSON with type, v, state containing value and timestamp
    - Test: from_json(json.to_string(to_json(reg))) == Ok(reg)

    MV-Register JSON round-trip:
    - Test: to_json encodes replica_id, entries (as array of tag+value objects), vclock
    - Test: Round-trip produces MV-Register with same value() output (compare sorted value lists)
  </behavior>
  <action>
Create test/serialization/ directory and test files.

Add `import gleam/json` and `import gleam/dynamic/decode` to each source module.

**G-Counter (JSON-01, JSON-02)** — Add to src/lattice/g_counter.gleam:

```gleam
pub fn to_json(counter: GCounter) -> json.Json {
  let GCounter(d, self_id) = counter
  json.object([
    #("type", json.string("g_counter")),
    #("v", json.int(1)),
    #("state", json.object([
      #("self_id", json.string(self_id)),
      #("counts", json.dict(d, fn(k) { k }, json.int)),
    ])),
  ])
}

pub fn from_json(json_string: String) -> Result(GCounter, json.DecodeError) {
  let decoder = {
    use self_id <- decode.field("state", decode.field("self_id", decode.string, _))
    use counts <- decode.field("state", decode.field("counts", decode.dict(decode.string, decode.int), _))
    decode.success(GCounter(dict: counts, self_id: self_id))
  }
  json.parse(from: json_string, using: decoder)
}
```

NOTE: The nested field access pattern may need adjustment. The verified pattern from research is:
```gleam
let decoder = {
  use state <- decode.field("state", {
    use self_id <- decode.field("self_id", decode.string)
    use counts <- decode.field("counts", decode.dict(decode.string, decode.int))
    decode.success(GCounter(dict: counts, self_id: self_id))
  })
  decode.success(state)
}
```

**PN-Counter (JSON-03, JSON-04)** — Add to src/lattice/pn_counter.gleam:

The PN-Counter contains two GCounters. Encode each inline (not via g_counter.to_json — avoid the type wrapper for nested state). Encode the positive and negative dicts and self_ids directly:

```gleam
pub fn to_json(counter: PNCounter) -> json.Json {
  let PNCounter(positive, negative) = counter
  let GCounter(pos_dict, pos_id) = positive
  let GCounter(neg_dict, neg_id) = negative
  json.object([
    #("type", json.string("pn_counter")),
    #("v", json.int(1)),
    #("state", json.object([
      #("positive", json.object([
        #("self_id", json.string(pos_id)),
        #("counts", json.dict(pos_dict, fn(k) { k }, json.int)),
      ])),
      #("negative", json.object([
        #("self_id", json.string(neg_id)),
        #("counts", json.dict(neg_dict, fn(k) { k }, json.int)),
      ])),
    ])),
  ])
}
```

For from_json, decode each nested G-Counter state and construct PNCounter:
```gleam
pub fn from_json(json_string: String) -> Result(PNCounter, json.DecodeError) {
  let g_counter_decoder = fn(field_name) {
    decode.field(field_name, {
      use self_id <- decode.field("self_id", decode.string)
      use counts <- decode.field("counts", decode.dict(decode.string, decode.int))
      decode.success(g_counter.GCounter(dict: counts, self_id: self_id))
    })
  }
  let decoder = {
    use state <- decode.field("state", {
      use positive <- g_counter_decoder("positive")
      use negative <- g_counter_decoder("negative")
      decode.success(PNCounter(positive: positive, negative: negative))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

NOTE: pn_counter.gleam imports `lattice/g_counter` already. Access GCounter constructor via `g_counter.GCounter(...)`.

**Version Vector (JSON-19, JSON-20)** — Add to src/lattice/version_vector.gleam:

```gleam
pub fn to_json(vv: VersionVector) -> json.Json {
  let VersionVector(d) = vv
  json.object([
    #("type", json.string("version_vector")),
    #("v", json.int(1)),
    #("state", json.object([
      #("clocks", json.dict(d, fn(k) { k }, json.int)),
    ])),
  ])
}

pub fn from_json(json_string: String) -> Result(VersionVector, json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use clocks <- decode.field("clocks", decode.dict(decode.string, decode.int))
      decode.success(VersionVector(dict: clocks))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

**LWW-Register (JSON-05, JSON-06)** — Add to src/lattice/lww_register.gleam:

Constrained to LWWRegister(String) for serialization:
```gleam
pub fn to_json(register: LWWRegister(String)) -> json.Json {
  json.object([
    #("type", json.string("lww_register")),
    #("v", json.int(1)),
    #("state", json.object([
      #("value", json.string(register.value)),
      #("timestamp", json.int(register.timestamp)),
    ])),
  ])
}

pub fn from_json(json_string: String) -> Result(LWWRegister(String), json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use value <- decode.field("value", decode.string)
      use timestamp <- decode.field("timestamp", decode.int)
      decode.success(LWWRegister(value: value, timestamp: timestamp))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

**MV-Register (JSON-07, JSON-08)** — Add to src/lattice/mv_register.gleam:

MV-Register has Dict(Tag, a) entries where Tag is a custom type. Cannot use json.dict because Tag isn't a String key. Encode entries as a JSON array of objects:

```gleam
pub fn to_json(register: MVRegister(String)) -> json.Json {
  let MVRegister(replica_id, entries, vclock) = register
  let entries_json = json.array(dict.to_list(entries), fn(pair) {
    let #(Tag(rid, counter), value) = pair
    json.object([
      #("tag", json.object([
        #("r", json.string(rid)),
        #("c", json.int(counter)),
      ])),
      #("value", json.string(value)),
    ])
  })
  let VersionVector(vclock_dict) = vclock
  json.object([
    #("type", json.string("mv_register")),
    #("v", json.int(1)),
    #("state", json.object([
      #("replica_id", json.string(replica_id)),
      #("entries", entries_json),
      #("vclock", json.dict(vclock_dict, fn(k) { k }, json.int)),
    ])),
  ])
}
```

For from_json, decode the entries array and reconstruct Dict(Tag, String):
```gleam
pub fn from_json(json_string: String) -> Result(MVRegister(String), json.DecodeError) {
  let entry_decoder = {
    use tag <- decode.field("tag", {
      use r <- decode.field("r", decode.string)
      use c <- decode.field("c", decode.int)
      decode.success(Tag(replica_id: r, counter: c))
    })
    use value <- decode.field("value", decode.string)
    decode.success(#(tag, value))
  }
  let decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use entries_list <- decode.field("entries", decode.list(entry_decoder))
      use vclock_dict <- decode.field("vclock", decode.dict(decode.string, decode.int))
      let entries = dict.from_list(entries_list)
      let vclock = version_vector.VersionVector(dict: vclock_dict)
      decode.success(MVRegister(replica_id: replica_id, entries: entries, vclock: vclock))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

NOTE: MV-Register imports `lattice/version_vector.{type VersionVector}` already. Use `version_vector.VersionVector(dict: ...)` to construct.

**Tests** — Create test/serialization/counter_json_test.gleam, register_json_test.gleam, version_vector_json_test.gleam:

Each test file follows this pattern:
```gleam
import gleam/json
import lattice/g_counter
import startest/expect

pub fn g_counter_round_trip__test() {
  let counter = g_counter.new("A") |> g_counter.increment(5)
  let json_str = json.to_string(g_counter.to_json(counter))
  g_counter.from_json(json_str)
  |> expect.to_equal(Ok(counter))
}
```

Write at least 2 round-trip tests per type:
1. Simple case (single replica, one operation)
2. Complex case (multiple replicas/operations merged)

For MV-Register round-trip, compare sorted value lists instead of structural equality if direct equality fails:
```gleam
let decoded = mv_register.from_json(json_str)
case decoded {
  Ok(reg) -> {
    list.sort(mv_register.value(reg), string.compare)
    |> expect.to_equal(list.sort(mv_register.value(original), string.compare))
  }
  Error(_) -> expect.to_be_true(False)  // should not happen
}
```

PITFALL: `json.dict` `keys` parameter is `fn(k) -> String`. For Dict(String, Int), use `fn(k) { k }` (identity function on String keys).

PITFALL: Import `gleam/json` in source files for `json.Json` return type and `json.DecodeError` error type. Import `gleam/dynamic/decode` for decoder combinators. These are SEPARATE imports.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>G-Counter, PN-Counter, Version Vector, LWW-Register, MV-Register all have working to_json/from_json; round-trip tests pass for each type; JSON format includes type tag and version; type checking passes</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: JSON for sets (JSON-09 to JSON-14)</name>
  <files>src/lattice/g_set.gleam, src/lattice/two_p_set.gleam, src/lattice/or_set.gleam, test/serialization/set_json_test.gleam</files>
  <behavior>
    G-Set JSON round-trip:
    - Test: to_json(g_set with elements) produces JSON array of elements in state
    - Test: from_json round-trip preserves elements (compare value() sets)

    2P-Set JSON round-trip:
    - Test: to_json encodes both added and removed sets as arrays
    - Test: from_json round-trip preserves active elements (compare value() sets)

    OR-Set JSON round-trip:
    - Test: to_json encodes replica_id, counter, and entries dict with tag arrays
    - Test: from_json round-trip preserves elements (compare value() sets)
  </behavior>
  <action>
Create test/serialization/set_json_test.gleam.

**G-Set (JSON-09, JSON-10)** — Add to src/lattice/g_set.gleam:

```gleam
import gleam/json
import gleam/dynamic/decode

pub fn to_json(g_set: GSet(String)) -> json.Json {
  json.object([
    #("type", json.string("g_set")),
    #("v", json.int(1)),
    #("state", json.object([
      #("elements", json.array(set.to_list(g_set.elements), json.string)),
    ])),
  ])
}

pub fn from_json(json_string: String) -> Result(GSet(String), json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use elements <- decode.field("elements", decode.list(decode.string))
      decode.success(GSet(elements: set.from_list(elements)))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

**2P-Set (JSON-11, JSON-12)** — Add to src/lattice/two_p_set.gleam:

```gleam
import gleam/json
import gleam/dynamic/decode

pub fn to_json(tpset: TwoPSet(String)) -> json.Json {
  json.object([
    #("type", json.string("two_p_set")),
    #("v", json.int(1)),
    #("state", json.object([
      #("added", json.array(set.to_list(tpset.added), json.string)),
      #("removed", json.array(set.to_list(tpset.removed), json.string)),
    ])),
  ])
}

pub fn from_json(json_string: String) -> Result(TwoPSet(String), json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use added <- decode.field("added", decode.list(decode.string))
      use removed <- decode.field("removed", decode.list(decode.string))
      decode.success(TwoPSet(added: set.from_list(added), removed: set.from_list(removed)))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

**OR-Set (JSON-13, JSON-14)** — Add to src/lattice/or_set.gleam:

OR-Set has Dict(a, set.Set(Tag)) entries. Encode as a JSON dict where keys are element strings and values are arrays of tag objects:

```gleam
import gleam/json
import gleam/dynamic/decode

pub fn to_json(orset: ORSet(String)) -> json.Json {
  json.object([
    #("type", json.string("or_set")),
    #("v", json.int(1)),
    #("state", json.object([
      #("replica_id", json.string(orset.replica_id)),
      #("counter", json.int(orset.counter)),
      #("entries", json.dict(orset.entries, fn(k) { k }, fn(tag_set) {
        json.array(set.to_list(tag_set), fn(tag) {
          let Tag(rid, c) = tag
          json.object([#("r", json.string(rid)), #("c", json.int(c))])
        })
      })),
    ])),
  ])
}

pub fn from_json(json_string: String) -> Result(ORSet(String), json.DecodeError) {
  let tag_decoder = {
    use r <- decode.field("r", decode.string)
    use c <- decode.field("c", decode.int)
    decode.success(Tag(replica_id: r, counter: c))
  }
  let tag_set_decoder = decode.map(decode.list(tag_decoder), set.from_list)
  let decoder = {
    use state <- decode.field("state", {
      use replica_id <- decode.field("replica_id", decode.string)
      use counter <- decode.field("counter", decode.int)
      use entries <- decode.field("entries", decode.dict(decode.string, tag_set_decoder))
      decode.success(ORSet(replica_id: replica_id, counter: counter, entries: entries))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

**Tests** — test/serialization/set_json_test.gleam:

For each set type, write round-trip tests. For sets with non-deterministic internal ordering, compare using value() output:

```gleam
// G-Set: structural equality should work since set.from_list is deterministic
pub fn g_set_round_trip__test() {
  let s = g_set.new() |> g_set.add("alpha") |> g_set.add("beta")
  let json_str = json.to_string(g_set.to_json(s))
  let decoded = g_set.from_json(json_str)
  case decoded {
    Ok(d) -> g_set.value(d) |> expect.to_equal(g_set.value(s))
    Error(_) -> expect.to_be_true(False)
  }
}
```

For OR-Set round-trip, compare on value() (observable state) since Tag dict ordering may differ:
```gleam
pub fn or_set_round_trip__test() {
  let s = or_set.new("A") |> or_set.add("x") |> or_set.add("y")
  let json_str = json.to_string(or_set.to_json(s))
  let decoded = or_set.from_json(json_str)
  case decoded {
    Ok(d) -> or_set.value(d) |> expect.to_equal(or_set.value(s))
    Error(_) -> expect.to_be_true(False)
  }
}
```

Write 2 tests per type: simple case + case with multiple elements/operations.
For 2P-Set, include a test with both added and removed elements.

PITFALL: `json.array` second argument is `of: fn(a) -> json.Json`. For `json.array(list, json.string)`, the `json.string` IS the function. But for set-based encoding, you need `json.array(set.to_list(s), json.string)`.

PITFALL: Set round-trip equality — `set.from_list(set.to_list(s))` should equal `s` in Gleam since gleam/set uses Erlang maps internally with content equality. If structural equality fails, fall back to comparing `set.to_list |> list.sort`.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>G-Set, 2P-Set, OR-Set all have working to_json/from_json; round-trip tests pass for each type; JSON format includes type tag and version; OR-Set entries encode tags correctly; type checking passes</done>
</task>

</tasks>

<verification>
Run `gleam test` - all JSON round-trip tests pass for all 8 leaf types + Version Vector
Run `gleam check` - no type errors
Verify each to_json output includes "type" and "v" fields
</verification>

<success_criteria>
- All 8 leaf CRDT types + Version Vector have to_json and from_json functions
- JSON format is self-describing: {"type": "...", "v": 1, "state": {...}}
- Round-trip from_json(json.to_string(to_json(x))) reconstructs the original value
- MV-Register entries encoded as array of tag+value objects (not dict with custom keys)
- OR-Set entries encoded as dict of element -> array of tag objects
- Set types encoded via set.to_list -> json.array, decoded via decode.list -> set.from_list
- All tests pass, type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/03-maps-serialization/03-maps-serialization-02-SUMMARY.md`
</output>
