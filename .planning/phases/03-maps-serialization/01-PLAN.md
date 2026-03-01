---
phase: 03-maps-serialization
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - gleam.toml
  - src/lattice/lww_map.gleam
  - test/map/lww_map_test.gleam
autonomous: true
requirements:
  - MAP-01
  - MAP-02
  - MAP-03
  - MAP-04
  - MAP-05
  - MAP-06
  - MAP-07

must_haves:
  truths:
    - "gleam_json is listed as a runtime dependency in gleam.toml [dependencies]"
    - "LWW-Map new() creates an empty map"
    - "LWW-Map set(map, key, value, timestamp) stores a key-value pair"
    - "LWW-Map get(map, key) returns Ok(value) for existing key, Error(Nil) for missing"
    - "LWW-Map set with lower timestamp does not overwrite existing higher-timestamp entry"
    - "LWW-Map remove(map, key, timestamp) makes get(key) return Error(Nil)"
    - "LWW-Map remove with tombstone semantics: remove at ts=10 wins over set at ts=5"
    - "LWW-Map keys() returns all active (non-tombstoned) keys"
    - "LWW-Map values() returns all active (non-tombstoned) values"
    - "LWW-Map merge resolves per-key by highest timestamp (pairwise LWW)"
    - "LWW-Map merge preserves tombstones: removed key stays removed if tombstone ts is highest"
  artifacts:
    - path: "gleam.toml"
      provides: "gleam_json added as runtime dependency"
    - path: "src/lattice/lww_map.gleam"
      provides: "LWW-Map CRDT implementation with tombstone-based remove"
      exports: ["new", "set", "get", "remove", "keys", "values", "merge"]
    - path: "test/map/lww_map_test.gleam"
      provides: "LWW-Map unit tests covering all operations and merge semantics"
  key_links:
    - from: "src/lattice/lww_map.gleam"
      to: "gleam/dict"
      via: "internal storage Dict(String, #(Option(String), Int))"
      pattern: "import gleam/dict"
    - from: "test/map/lww_map_test.gleam"
      to: "src/lattice/lww_map.gleam"
      via: "import and function calls"
      pattern: "import lattice/lww_map"
---

<objective>
Add gleam_json as a runtime dependency and implement the LWW-Map (Last-Writer-Wins Map) CRDT with tombstone-based remove semantics and per-key timestamp resolution.

Purpose: Deliver the first map CRDT type and prepare the dependency tree for JSON serialization
Output: Working LWW-Map module with comprehensive unit tests, gleam_json available as runtime dep
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

# Existing patterns from Phase 1-2:
# - dict merge: list.unique(list.append(dict.keys(a), dict.keys(b))) for all-keys union
# - result.unwrap(dict.get(...), default) for safe access
# - Record-wrapping: each CRDT is a named record type
# - All types expose: new(), value(), merge()

# Key API from gleam/option:
# import gleam/option.{type Option, None, Some}
# Option(a) = Some(a) | None

# LWW-Map internal representation (from research, Claude's discretion):
# Dict(String, #(Option(String), Int)) — each entry is (value_or_tombstone, timestamp)
# None means tombstoned (removed). Some(val) means active.
# On merge, per-key highest timestamp wins (including tombstones).
# On get, return Error(Nil) if key missing OR value is None (tombstoned).
# On keys/values, filter out tombstoned entries.
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add gleam_json runtime dependency</name>
  <files>gleam.toml</files>
  <action>
Run `gleam add gleam_json` to add gleam_json as a runtime dependency.

Verify that gleam.toml now has `gleam_json` under `[dependencies]` (not just `[dev-dependencies]`). The version should resolve to 3.1.0 or compatible since it's already in manifest.toml as a transitive dep.

After adding, run `gleam build` to confirm the dependency resolves correctly.
  </action>
  <verify>
    <automated>gleam build</automated>
  </verify>
  <done>gleam_json appears in [dependencies] section of gleam.toml; gleam build succeeds</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: LWW-Map implementation with TDD (MAP-01 to MAP-07)</name>
  <files>src/lattice/lww_map.gleam, test/map/lww_map_test.gleam</files>
  <behavior>
    - Test: new() creates empty map; get("any") returns Error(Nil); keys() returns []; values() returns []
    - Test: set(new(), "name", "Alice", 1) then get("name") returns Ok("Alice")
    - Test: set at ts=1, then set same key at ts=5 — get returns the ts=5 value
    - Test: set at ts=5, then set same key at ts=1 (lower) — get returns the ts=5 value (not overwritten)
    - Test: set multiple keys — keys() returns all key names; values() returns all values
    - Test: remove(map, "name", 10) — get("name") returns Error(Nil) after remove
    - Test: set at ts=5, remove at ts=10 — key is removed (tombstone wins)
    - Test: set at ts=10, remove at ts=5 — key is NOT removed (set wins, higher ts)
    - Test: merge two maps with disjoint keys — merged map has all keys from both
    - Test: merge two maps with overlapping key, different timestamps — higher ts wins
    - Test: merge where one side has tombstone with higher ts — key stays removed
    - Test: merge where one side has tombstone with lower ts — key is present (set wins)
    - Test: merge commutativity: value-level merge(a,b) == merge(b,a)
  </behavior>
  <action>
Create test/map/ directory and test/map/lww_map_test.gleam with tests above.

Implement src/lattice/lww_map.gleam:

Import: `gleam/dict`, `gleam/list`, `gleam/option.{type Option, None, Some}`, `gleam/result`, `gleam/set`

Define the LWW-Map type using Option for tombstone support:
```gleam
pub type LWWMap {
  LWWMap(entries: dict.Dict(String, #(Option(String), Int)))
}
```

Each entry stores `#(Option(String), Int)` where:
- `Some(value)` = active entry with value
- `None` = tombstone (removed)
- `Int` = timestamp

Implement these functions:

- `new() -> LWWMap` — `LWWMap(entries: dict.new())`

- `set(map: LWWMap, key: String, value: String, timestamp: Int) -> LWWMap` —
  Check if key exists with higher or equal timestamp; if so, keep existing.
  Otherwise insert `#(Some(value), timestamp)`.
  ```gleam
  case dict.get(map.entries, key) {
    Ok(#(_, existing_ts)) if timestamp <= existing_ts -> map
    _ -> LWWMap(entries: dict.insert(map.entries, key, #(Some(value), timestamp)))
  }
  ```
  NOTE: Gleam doesn't have `if` guards in case patterns. Use nested case or comparison:
  ```gleam
  let should_update = case dict.get(map.entries, key) {
    Error(_) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_update {
    True -> LWWMap(entries: dict.insert(map.entries, key, #(Some(value), timestamp)))
    False -> map
  }
  ```

- `get(map: LWWMap, key: String) -> Result(String, Nil)` —
  ```gleam
  case dict.get(map.entries, key) {
    Ok(#(Some(value), _)) -> Ok(value)
    _ -> Error(Nil)
  }
  ```

- `remove(map: LWWMap, key: String, timestamp: Int) -> LWWMap` —
  Same timestamp check as set: only apply if timestamp is strictly greater than existing.
  Insert `#(None, timestamp)` as tombstone.
  ```gleam
  let should_remove = case dict.get(map.entries, key) {
    Error(_) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_remove {
    True -> LWWMap(entries: dict.insert(map.entries, key, #(None, timestamp)))
    False -> map
  }
  ```

- `keys(map: LWWMap) -> List(String)` —
  Filter entries to only active (non-tombstoned), return keys:
  ```gleam
  dict.fold(map.entries, [], fn(acc, key, entry) {
    case entry {
      #(Some(_), _) -> [key, ..acc]
      #(None, _) -> acc
    }
  })
  ```

- `values(map: LWWMap) -> List(String)` —
  Filter entries to only active, return values:
  ```gleam
  dict.fold(map.entries, [], fn(acc, _key, entry) {
    case entry {
      #(Some(value), _) -> [value, ..acc]
      #(None, _) -> acc
    }
  })
  ```

- `merge(a: LWWMap, b: LWWMap) -> LWWMap` —
  For each key in the union of both key sets, keep entry with higher timestamp:
  ```gleam
  let all_keys = list.unique(list.append(dict.keys(a.entries), dict.keys(b.entries)))
  let merged = list.fold(all_keys, dict.new(), fn(acc, key) {
    let entry = case dict.get(a.entries, key), dict.get(b.entries, key) {
      Ok(#(_, ts_a) as ea), Ok(#(_, ts_b)) ->
        case ts_a >= ts_b { True -> ea  False -> result.unwrap(dict.get(b.entries, key), ea) }
      Ok(ea), Error(_) -> ea
      Error(_), Ok(eb) -> eb
      Error(_), Error(_) -> #(None, 0)  // unreachable
    }
    dict.insert(acc, key, entry)
  })
  LWWMap(entries: merged)
  ```

  NOTE: In the merge, when timestamps are EQUAL, prefer the first argument's entry (consistent tiebreak like LWW-Register). The exact pattern:
  ```gleam
  let winner = case dict.get(a.entries, key), dict.get(b.entries, key) {
    Ok(ea), Ok(eb) -> {
      let #(_, ts_a) = ea
      let #(_, ts_b) = eb
      case ts_a >= ts_b {
        True -> ea
        False -> eb
      }
    }
    Ok(ea), Error(_) -> ea
    Error(_), Ok(eb) -> eb
    Error(_), Error(_) -> panic as "unreachable: key in all_keys but not in either dict"
  }
  ```

PITFALL: In tests comparing keys() and values(), the order of returned lists is not guaranteed since they come from dict.fold. Sort the results before comparing, or use set.from_list for keys comparison.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>LWW-Map: new creates empty map; set stores key-value-timestamp; get retrieves active values; set with lower timestamp is rejected; remove creates tombstone; remove with lower timestamp is rejected; keys/values exclude tombstoned entries; merge resolves per-key by highest timestamp including tombstones; all tests pass</done>
</task>

</tasks>

<verification>
Run `gleam test` - all LWW-Map tests pass
Run `gleam check` - no type errors
Run `gleam build` - confirms gleam_json dependency resolves
</verification>

<success_criteria>
- gleam_json is in [dependencies] of gleam.toml (runtime, not dev-only)
- LWW-Map: new, set, get, remove, keys, values, merge all work correctly
- LWW-Map tombstone semantics: remove inserts None+timestamp, merge respects tombstones
- LWW-Map per-key LWW resolution: higher timestamp always wins
- All unit tests pass including merge scenarios with tombstones
- Type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/03-maps-serialization/03-maps-serialization-01-SUMMARY.md`
</output>
