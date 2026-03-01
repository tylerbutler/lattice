---
phase: 03-maps-serialization
plan: 03
type: execute
wave: 2
depends_on:
  - 01
  - 02
files_modified:
  - src/lattice/crdt.gleam
  - src/lattice/or_map.gleam
  - test/map/or_map_test.gleam
autonomous: true
requirements:
  - MAP-08
  - MAP-09
  - MAP-10
  - MAP-11
  - MAP-12
  - MAP-13
  - MAP-14

must_haves:
  truths:
    - "Crdt union type wraps all 8 leaf CRDT types (G-Counter through OR-Set)"
    - "CrdtSpec enum covers all 8 leaf types for OR-Map auto-creation"
    - "default_crdt(spec, replica_id) creates a new empty CRDT of the specified type"
    - "crdt.merge dispatches to type-specific merge for matching Crdt variants"
    - "crdt.merge handles type mismatch gracefully (returns first argument)"
    - "OR-Map new(replica_id, spec) creates empty map with specified CRDT type"
    - "OR-Map update(map, key, fn) applies function to existing or auto-created CRDT value"
    - "OR-Map get(map, key) returns Ok(crdt) for active keys, Error(Nil) for missing/removed"
    - "OR-Map remove(map, key) makes get(key) return Error(Nil)"
    - "OR-Map keys() returns only active keys (those in OR-Set)"
    - "OR-Map values() returns only CRDT values for active keys"
    - "OR-Map merge merges key OR-Sets (add-wins) and CRDT values per key"
    - "OR-Map concurrent update vs remove: update wins (add-wins semantics)"
  artifacts:
    - path: "src/lattice/crdt.gleam"
      provides: "Crdt tagged union, CrdtSpec enum, default_crdt, merge dispatch, generic to_json/from_json for leaf types"
      exports: ["Crdt", "CrdtSpec", "default_crdt", "merge", "to_json", "from_json"]
    - path: "src/lattice/or_map.gleam"
      provides: "OR-Map CRDT with add-wins key semantics and nested CRDT values"
      exports: ["new", "update", "get", "remove", "keys", "values", "merge"]
    - path: "test/map/or_map_test.gleam"
      provides: "OR-Map unit tests including add-wins and nested CRDT merge scenarios"
  key_links:
    - from: "src/lattice/crdt.gleam"
      to: "src/lattice/g_counter.gleam"
      via: "CrdtGCounter variant wraps GCounter type"
      pattern: "import lattice/g_counter.{type GCounter}"
    - from: "src/lattice/or_map.gleam"
      to: "src/lattice/crdt.gleam"
      via: "OR-Map values are Crdt union, uses CrdtSpec and merge dispatch"
      pattern: "import lattice/crdt.{type Crdt, type CrdtSpec}"
    - from: "src/lattice/or_map.gleam"
      to: "src/lattice/or_set.gleam"
      via: "OR-Map key tracking uses OR-Set for add-wins semantics"
      pattern: "import lattice/or_set.{type ORSet}"
---

<objective>
Create the Crdt tagged union type (central dispatch for 8 leaf types) and implement the OR-Map CRDT with add-wins key semantics and nested CRDT value merging. OR-Map is the most complex type in the library.

Purpose: Deliver the OR-Map CRDT (the flagship composite type) with type-safe nested CRDT value storage
Output: Working crdt.gleam module with union type/dispatch + OR-Map module with comprehensive tests
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

# Key type definitions needed (from Plans 01-02):
@src/lattice/g_counter.gleam
@src/lattice/or_set.gleam

<interfaces>
<!-- Existing types that Crdt union wraps -->

GCounter(dict: Dict(String, Int), self_id: String)
PNCounter(positive: GCounter, negative: GCounter)
LWWRegister(value: a, timestamp: Int)  -- constrained to String for Crdt
MVRegister(replica_id: String, entries: Dict(Tag, a), vclock: VersionVector)  -- constrained to String
GSet(elements: Set(a))  -- constrained to String
TwoPSet(added: Set(a), removed: Set(a))  -- constrained to String
ORSet(replica_id: String, counter: Int, entries: Dict(a, Set(Tag)))  -- constrained to String
VersionVector(dict: Dict(String, Int))

<!-- OR-Set API for key tracking -->
or_set.new(replica_id) -> ORSet(a)
or_set.add(orset, element) -> ORSet(a)
or_set.remove(orset, element) -> ORSet(a)
or_set.contains(orset, element) -> Bool
or_set.value(orset) -> Set(a)
or_set.merge(a, b) -> ORSet(a)
</interfaces>

# CRITICAL CONSTRAINT: Circular import avoidance
# crdt.gleam imports all 8 leaf modules (g_counter, pn_counter, etc.)
# or_map.gleam imports crdt.gleam for Crdt type + CrdtSpec + merge
# crdt.gleam must NOT import or_map.gleam or lww_map.gleam
# This means: Crdt union contains ONLY the 8 leaf types (no CrdtOrMap or CrdtLwwMap variants)
# Maps are composite/container types, not leaf CRDTs in the union

# DECISION: Crdt union covers 8 leaf types:
# CrdtGCounter, CrdtPnCounter, CrdtLwwRegister, CrdtMvRegister,
# CrdtGSet, CrdtTwoPSet, CrdtOrSet, CrdtVersionVector
# No map variants (avoids circular imports)

# DECISION: All parameterized types fixed to String in Crdt union (v1 simplification)
# CrdtLwwRegister(LWWRegister(String))
# CrdtMvRegister(MVRegister(String))
# CrdtGSet(GSet(String))
# CrdtTwoPSet(TwoPSet(String))
# CrdtOrSet(ORSet(String))
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Crdt union type + dispatch functions</name>
  <files>src/lattice/crdt.gleam</files>
  <behavior>
    - Crdt type has 8 variants wrapping each leaf CRDT type
    - CrdtSpec enum has 8 variants matching Crdt (without data)
    - default_crdt(GCounterSpec, "A") returns CrdtGCounter(g_counter.new("A"))
    - default_crdt(OrSetSpec, "A") returns CrdtOrSet(or_set.new("A"))
    - merge(CrdtGCounter(a), CrdtGCounter(b)) returns CrdtGCounter(g_counter.merge(a, b))
    - merge with mismatched types returns first argument
    - to_json dispatches to type-specific to_json for all 8 types
    - from_json reads "type" field and dispatches to correct type-specific from_json
  </behavior>
  <action>
Create src/lattice/crdt.gleam with:

Imports — all 8 leaf CRDT modules:
```gleam
import gleam/json
import gleam/dynamic/decode
import lattice/g_counter.{type GCounter}
import lattice/pn_counter.{type PNCounter}
import lattice/lww_register.{type LWWRegister}
import lattice/mv_register.{type MVRegister}
import lattice/g_set.{type GSet}
import lattice/two_p_set.{type TwoPSet}
import lattice/or_set.{type ORSet}
import lattice/version_vector.{type VersionVector}
```

Define the Crdt union (all parameterized types fixed to String):
```gleam
/// Tagged union for all leaf CRDT types.
/// Parameterized types are fixed to String for v1.
/// Maps (LWW-Map, OR-Map) are composite containers and NOT included
/// in this union to avoid circular module dependencies.
pub type Crdt {
  CrdtGCounter(GCounter)
  CrdtPnCounter(PNCounter)
  CrdtLwwRegister(LWWRegister(String))
  CrdtMvRegister(MVRegister(String))
  CrdtGSet(GSet(String))
  CrdtTwoPSet(TwoPSet(String))
  CrdtOrSet(ORSet(String))
  CrdtVersionVector(VersionVector)
}
```

Define CrdtSpec for OR-Map auto-creation:
```gleam
/// Specifies which CRDT type an OR-Map holds.
/// Used to auto-create default values for new keys.
pub type CrdtSpec {
  GCounterSpec
  PnCounterSpec
  LwwRegisterSpec
  MvRegisterSpec
  GSetSpec
  TwoPSetSpec
  OrSetSpec
}
```

NOTE: No VersionVectorSpec — VersionVector is infrastructure, not an OR-Map value type.

Implement default_crdt(spec, replica_id):
```gleam
pub fn default_crdt(spec: CrdtSpec, replica_id: String) -> Crdt {
  case spec {
    GCounterSpec -> CrdtGCounter(g_counter.new(replica_id))
    PnCounterSpec -> CrdtPnCounter(pn_counter.new(replica_id))
    LwwRegisterSpec -> CrdtLwwRegister(lww_register.new("", 0))
    MvRegisterSpec -> CrdtMvRegister(mv_register.new(replica_id))
    GSetSpec -> CrdtGSet(g_set.new())
    TwoPSetSpec -> CrdtTwoPSet(two_p_set.new())
    OrSetSpec -> CrdtOrSet(or_set.new(replica_id))
  }
}
```

NOTE: LWW-Register default is `new("", 0)` — empty string value at timestamp 0. This is the "bottom" element. G-Set and 2P-Set don't take replica_id.

Implement merge dispatch:
```gleam
pub fn merge(a: Crdt, b: Crdt) -> Crdt {
  case a, b {
    CrdtGCounter(ca), CrdtGCounter(cb) -> CrdtGCounter(g_counter.merge(ca, cb))
    CrdtPnCounter(ca), CrdtPnCounter(cb) -> CrdtPnCounter(pn_counter.merge(ca, cb))
    CrdtLwwRegister(ca), CrdtLwwRegister(cb) -> CrdtLwwRegister(lww_register.merge(ca, cb))
    CrdtMvRegister(ca), CrdtMvRegister(cb) -> CrdtMvRegister(mv_register.merge(ca, cb))
    CrdtGSet(ca), CrdtGSet(cb) -> CrdtGSet(g_set.merge(ca, cb))
    CrdtTwoPSet(ca), CrdtTwoPSet(cb) -> CrdtTwoPSet(two_p_set.merge(ca, cb))
    CrdtOrSet(ca), CrdtOrSet(cb) -> CrdtOrSet(or_set.merge(ca, cb))
    CrdtVersionVector(ca), CrdtVersionVector(cb) -> CrdtVersionVector(version_vector.merge(ca, cb))
    _, _ -> a  // Type mismatch: return first argument
  }
}
```

Implement generic to_json dispatcher:
```gleam
pub fn to_json(crdt: Crdt) -> json.Json {
  case crdt {
    CrdtGCounter(c) -> g_counter.to_json(c)
    CrdtPnCounter(c) -> pn_counter.to_json(c)
    CrdtLwwRegister(c) -> lww_register.to_json(c)
    CrdtMvRegister(c) -> mv_register.to_json(c)
    CrdtGSet(c) -> g_set.to_json(c)
    CrdtTwoPSet(c) -> two_p_set.to_json(c)
    CrdtOrSet(c) -> or_set.to_json(c)
    CrdtVersionVector(c) -> version_vector.to_json(c)
  }
}
```

Implement generic from_json dispatcher — reads "type" field first, then dispatches:
```gleam
pub fn from_json(json_string: String) -> Result(Crdt, json.DecodeError) {
  // First, extract the type tag
  let type_decoder = {
    use type_tag <- decode.field("type", decode.string)
    decode.success(type_tag)
  }
  case json.parse(from: json_string, using: type_decoder) {
    Error(e) -> Error(e)
    Ok(type_tag) -> dispatch_decode(type_tag, json_string)
  }
}

fn dispatch_decode(type_tag: String, json_string: String) -> Result(Crdt, json.DecodeError) {
  case type_tag {
    "g_counter" -> case g_counter.from_json(json_string) {
      Ok(c) -> Ok(CrdtGCounter(c))
      Error(e) -> Error(e)
    }
    "pn_counter" -> case pn_counter.from_json(json_string) {
      Ok(c) -> Ok(CrdtPnCounter(c))
      Error(e) -> Error(e)
    }
    "lww_register" -> case lww_register.from_json(json_string) {
      Ok(c) -> Ok(CrdtLwwRegister(c))
      Error(e) -> Error(e)
    }
    "mv_register" -> case mv_register.from_json(json_string) {
      Ok(c) -> Ok(CrdtMvRegister(c))
      Error(e) -> Error(e)
    }
    "g_set" -> case g_set.from_json(json_string) {
      Ok(c) -> Ok(CrdtGSet(c))
      Error(e) -> Error(e)
    }
    "two_p_set" -> case two_p_set.from_json(json_string) {
      Ok(c) -> Ok(CrdtTwoPSet(c))
      Error(e) -> Error(e)
    }
    "or_set" -> case or_set.from_json(json_string) {
      Ok(c) -> Ok(CrdtOrSet(c))
      Error(e) -> Error(e)
    }
    "version_vector" -> case version_vector.from_json(json_string) {
      Ok(c) -> Ok(CrdtVersionVector(c))
      Error(e) -> Error(e)
    }
    _ -> Error(json.UnexpectedFormat([decode.DecodeError(expected: "known CRDT type", found: type_tag, path: ["type"])]))
  }
}
```

NOTE: For the unknown type error, check the exact gleam_json error constructor. `json.UnexpectedFormat` takes a `List(decode.DecodeError)`. If that constructor doesn't exist, use what's available — check the gleam_json DecodeError type definition. It may be `json.UnableToDecode(List(decode.DecodeError))` or similar. Adapt to whatever compiles.

This module should compile with `gleam check` and NOT import lww_map or or_map (no circular deps).
  </action>
  <verify>
    <automated>gleam check</automated>
  </verify>
  <done>crdt.gleam compiles; Crdt union has 8 leaf variants; CrdtSpec has 7 variants; default_crdt creates correct defaults; merge dispatches to type-specific merge; to_json/from_json dispatch correctly; no circular import errors</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: OR-Map implementation with TDD (MAP-08 to MAP-14)</name>
  <files>src/lattice/or_map.gleam, test/map/or_map_test.gleam</files>
  <behavior>
    - Test: new("A", GCounterSpec) creates empty map; keys() returns []; get("any") returns Error(Nil)
    - Test: update(map, "score", fn(c) { ... }) auto-creates a G-Counter and applies function
    - Test: update then get("score") returns Ok(CrdtGCounter(...))
    - Test: update twice on same key — second update modifies existing value
    - Test: Multiple keys — keys() returns all active key names; values() returns all values
    - Test: remove(map, "score") — get("score") returns Error(Nil); keys() excludes "score"
    - Test: Update after remove — key is re-added (add-wins from OR-Set semantics)
    - Test: Concurrent update vs remove scenario:
      - replica_a updates key "x"
      - replica_b = merge(new("B", spec), replica_a) then removes "x"
      - replica_a updates "x" again concurrently
      - merged = merge(replica_a, replica_b)
      - get(merged, "x") returns Ok(...) — update wins
    - Test: merge two maps with same key — nested CRDT values are merged via crdt.merge
    - Test: merge two maps with disjoint keys — merged map has all keys
    - Test: values from merge reflect merged CRDT state (e.g., two G-Counters merged)
  </behavior>
  <action>
Create src/lattice/or_map.gleam and test/map/or_map_test.gleam.

Imports for or_map.gleam:
```gleam
import gleam/dict
import gleam/list
import gleam/set
import lattice/crdt.{type Crdt, type CrdtSpec}
import lattice/or_set.{type ORSet}
```

Define OR-Map type:
```gleam
pub type ORMap {
  ORMap(
    replica_id: String,
    crdt_spec: CrdtSpec,
    key_set: ORSet(String),
    values: dict.Dict(String, Crdt),
  )
}
```

Implement functions:

- `new(replica_id: String, crdt_spec: CrdtSpec) -> ORMap`:
  ```gleam
  ORMap(
    replica_id: replica_id,
    crdt_spec: crdt_spec,
    key_set: or_set.new(replica_id),
    values: dict.new(),
  )
  ```

- `update(map: ORMap, key: String, f: fn(Crdt) -> Crdt) -> ORMap`:
  Auto-create CRDT value if key doesn't exist, then apply function:
  ```gleam
  let current = case dict.get(map.values, key) {
    Ok(crdt_val) -> crdt_val
    Error(_) -> crdt.default_crdt(map.crdt_spec, map.replica_id)
  }
  let updated = f(current)
  ORMap(
    replica_id: map.replica_id,
    crdt_spec: map.crdt_spec,
    key_set: or_set.add(map.key_set, key),
    values: dict.insert(map.values, key, updated),
  )
  ```

- `get(map: ORMap, key: String) -> Result(Crdt, Nil)`:
  Only return value if key is active in the OR-Set:
  ```gleam
  case or_set.contains(map.key_set, key) {
    True -> case dict.get(map.values, key) {
      Ok(val) -> Ok(val)
      Error(_) -> Error(Nil)
    }
    False -> Error(Nil)
  }
  ```

- `remove(map: ORMap, key: String) -> ORMap`:
  Remove from OR-Set only. Keep value in values dict (will be merged if re-added):
  ```gleam
  ORMap(..map, key_set: or_set.remove(map.key_set, key))
  ```
  NOTE: Gleam's record update syntax is `ORMap(..map, field: new_value)`.

- `keys(map: ORMap) -> List(String)`:
  Return active keys from OR-Set:
  ```gleam
  set.to_list(or_set.value(map.key_set))
  ```

- `values(map: ORMap) -> List(Crdt)`:
  Return values only for active keys:
  ```gleam
  let active_keys = or_set.value(map.key_set)
  dict.fold(map.values, [], fn(acc, key, val) {
    case set.contains(active_keys, key) {
      True -> [val, ..acc]
      False -> acc
    }
  })
  ```

- `merge(a: ORMap, b: ORMap) -> ORMap`:
  Merge key OR-Sets + merge CRDT values per key:
  ```gleam
  let merged_key_set = or_set.merge(a.key_set, b.key_set)
  let all_value_keys = list.unique(list.append(dict.keys(a.values), dict.keys(b.values)))
  let merged_values = list.fold(all_value_keys, dict.new(), fn(acc, key) {
    let merged_crdt = case dict.get(a.values, key), dict.get(b.values, key) {
      Ok(ca), Ok(cb) -> crdt.merge(ca, cb)
      Ok(ca), Error(_) -> ca
      Error(_), Ok(cb) -> cb
      Error(_), Error(_) -> panic as "unreachable"
    }
    dict.insert(acc, key, merged_crdt)
  })
  ORMap(
    replica_id: a.replica_id,
    crdt_spec: a.crdt_spec,
    key_set: merged_key_set,
    values: merged_values,
  )
  ```

**Tests** — test/map/or_map_test.gleam:

Import:
```gleam
import lattice/or_map
import lattice/crdt.{CrdtGCounter, GCounterSpec}
import lattice/g_counter
import gleam/set
import startest/expect
```

Write all tests from the behavior list. Key test patterns:

For the update function test, the callback receives a Crdt and must return a Crdt:
```gleam
pub fn or_map_update__test() {
  let map = or_map.new("A", GCounterSpec)
  let map = or_map.update(map, "score", fn(c) {
    case c {
      CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 5))
      _ -> c
    }
  })
  case or_map.get(map, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(5)
    _ -> expect.to_be_true(False)
  }
}
```

For the concurrent update-vs-remove test:
```gleam
pub fn or_map_concurrent_update_wins__test() {
  let map_a = or_map.new("A", GCounterSpec)
  let map_a = or_map.update(map_a, "x", fn(c) {
    case c { CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 1)) _ -> c }
  })
  // B syncs with A then removes
  let map_b = or_map.merge(or_map.new("B", GCounterSpec), map_a)
  let map_b = or_map.remove(map_b, "x")
  // A concurrently updates x again
  let map_a = or_map.update(map_a, "x", fn(c) {
    case c { CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 1)) _ -> c }
  })
  // Merge: A's concurrent update should win
  let merged = or_map.merge(map_a, map_b)
  or_set.contains(merged.key_set, "x") |> expect.to_be_true()
  // ... or use or_map.get(merged, "x") and check it's Ok
}
```

Wait — or_map.key_set is a field access on a non-opaque type. Since ORMap is pub with named fields, `merged.key_set` should work. Alternatively use `or_map.keys(merged)` to check "x" is present.

For the merge-merges-nested-values test:
```gleam
pub fn or_map_merge_nested_values__test() {
  let map_a = or_map.new("A", GCounterSpec)
  let map_a = or_map.update(map_a, "score", fn(c) {
    case c { CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 3)) _ -> c }
  })
  let map_b = or_map.new("B", GCounterSpec)
  let map_b = or_map.update(map_b, "score", fn(c) {
    case c { CrdtGCounter(counter) -> CrdtGCounter(g_counter.increment(counter, 7)) _ -> c }
  })
  let merged = or_map.merge(map_a, map_b)
  case or_map.get(merged, "score") {
    Ok(CrdtGCounter(counter)) -> g_counter.value(counter) |> expect.to_equal(10)
    _ -> expect.to_be_true(False)
  }
}
```

PITFALL: The OR-Set used for key tracking works with String keys. Make sure all test keys are strings.

PITFALL: When testing keys() and values(), the order is non-deterministic. Sort before comparing or use set.from_list.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>crdt.gleam: Crdt union with 8 variants, CrdtSpec with 7 variants, default_crdt, merge dispatch, generic to_json/from_json all work; OR-Map: new, update, get, remove, keys, values, merge all work; OR-Map add-wins semantics verified; nested CRDT merge verified (G-Counter values combined); all tests pass</done>
</task>

</tasks>

<verification>
Run `gleam test` - all OR-Map tests pass + all prior tests still pass
Run `gleam check` - no type errors, no circular import errors
Verify crdt.gleam does NOT import lww_map or or_map (check imports)
Verify or_map.gleam imports crdt.gleam (one-directional dependency)
</verification>

<success_criteria>
- Crdt union type compiles with 8 leaf variants (no map variants)
- CrdtSpec covers all 7 OR-Map-compatible leaf types
- default_crdt creates correct empty CRDT for each spec
- crdt.merge dispatches correctly for all 8 types
- No circular import errors
- OR-Map: new, update, get, remove, keys, values, merge all work
- OR-Map update auto-creates CRDT value from spec for new keys
- OR-Map remove only affects key_set (values preserved for merge)
- OR-Map merge uses OR-Set add-wins for keys + crdt.merge for values
- Concurrent update vs remove: update wins
- All tests pass, type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/03-maps-serialization/03-maps-serialization-03-SUMMARY.md`
</output>
