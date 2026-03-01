---
phase: 04-advanced-testing
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - test/property/map_property_test.gleam
  - test/property/serialization_property_test.gleam
autonomous: true
requirements:
  - TEST-01
  - TEST-02
  - TEST-03
  - TEST-07

must_haves:
  truths:
    - "LWW-Map merge is commutative (with distinct timestamps)"
    - "LWW-Map merge is associative (with distinct timestamps)"
    - "LWW-Map merge is idempotent"
    - "OR-Map merge is commutative (observable keys comparison)"
    - "OR-Map merge is idempotent (observable keys unchanged after self-merge)"
    - "OR-Set merge is associative (tag-set union is associative)"
    - "MV-Register JSON round-trip preserves observable values"
    - "OR-Map JSON round-trip preserves observable keys"
    - "VersionVector JSON round-trip preserves all entries"
  artifacts:
    - path: "test/property/map_property_test.gleam"
      provides: "LWW-Map and OR-Map merge law property tests + OR-Set associativity"
      min_lines: 80
    - path: "test/property/serialization_property_test.gleam"
      provides: "Complete round-trip property tests for all CRDT types"
      contains: "mv_register_json_round_trip"
  key_links:
    - from: "test/property/map_property_test.gleam"
      to: "src/lattice/lww_map.gleam"
      via: "import lattice/lww_map"
      pattern: "import lattice/lww_map"
    - from: "test/property/map_property_test.gleam"
      to: "src/lattice/or_map.gleam"
      via: "import lattice/or_map"
      pattern: "import lattice/or_map"
---

<objective>
Complete merge-law property tests for maps and remaining serialization round-trip property tests.

Purpose: TEST-01/02/03 require ALL CRDT types to have merge commutativity, associativity, and idempotency property tests. Counters, registers, and sets are done. This plan adds LWW-Map, OR-Map, and OR-Set associativity. TEST-07 requires round-trip tests for all types — MV-Register, OR-Map, and VersionVector are missing.

Output: New `map_property_test.gleam` with map merge laws + OR-Set associativity. Updated `serialization_property_test.gleam` with remaining round-trip tests.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/04-advanced-testing/04-RESEARCH.md

Existing property test patterns to follow:
@test/property/counter_property_test.gleam
@test/property/register_set_property_test.gleam
@test/property/serialization_property_test.gleam

Source modules under test:
@src/lattice/lww_map.gleam
@src/lattice/or_map.gleam
@src/lattice/crdt.gleam
@src/lattice/or_set.gleam
@src/lattice/mv_register.gleam
@src/lattice/version_vector.gleam
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Map merge-law + OR-Set associativity property tests</name>
  <files>test/property/map_property_test.gleam</files>
  <behavior>
    - LWW-Map commutativity: get(merge(a,b), key) == get(merge(b,a), key) with distinct timestamps
    - LWW-Map idempotency: get(merge(m, m), key) == get(m, key)
    - LWW-Map associativity: get(merge(merge(a,b),c), key) == get(merge(a,merge(b,c)), key) with distinct timestamps
    - OR-Map commutativity: set.from_list(keys(merge(a,b))) == set.from_list(keys(merge(b,a)))
    - OR-Map idempotency: set.from_list(keys(merge(m,m))) == set.from_list(keys(m))
    - OR-Map associativity: SKIP with comment (infeasible like MV-Register)
    - OR-Set associativity: value(merge(merge(a,b),c)) == value(merge(a,merge(b,c)))
  </behavior>
  <action>
Create test/property/map_property_test.gleam with the `small_test_config()` pattern (test_count: 10, max_retries: 3, seed: qcheck.seed(42)).

**LWW-Map commutativity:** Use non-overlapping timestamp ranges — `bounded_int(1, 50)` for map_a and `bounded_int(51, 100)` for map_b. Compare via `lww_map.get(merged, "key")` on both merge orders. Per research Pattern 6 and the anti-pattern about equal timestamps.

**LWW-Map idempotency:** Single map merged with itself; compare `lww_map.get` results.

**LWW-Map associativity:** Three maps with timestamps from three distinct ranges (1-30, 31-60, 61-90). Compare `lww_map.get` results for both groupings.

**OR-Map commutativity:** Two OR-Maps with GCounterSpec, each updating key "x" with different increments. Compare using `set.from_list(or_map.keys(...))`. Per research Pattern 7.

**OR-Map idempotency:** Single OR-Map merged with itself. Compare using `set.from_list(or_map.keys(...))` and `list.length(or_map.values(...))`.

**OR-Map associativity:** Add a comment: `// Associativity skipped: constructing valid OR-Map triples for property testing is infeasible; see Phase 2 plan 04 decision on MV-Register.`

**OR-Set associativity:** Three OR-Sets with independent replicas ("A", "B", "C"). Compare `or_set.value` for both merge groupings. Research confirms this is feasible since OR-Set uses tag-set union (mathematically associative) and counter max (also associative).

Import: `lattice/lww_map`, `lattice/or_map`, `lattice/or_set`, `lattice/crdt`, `lattice/g_counter`, `gleam/set`, `gleam/int`, `gleam/list`, `qcheck`, `startest/expect`.
  </action>
  <verify>
    <automated>gleam test 2>&1 | grep -E "(map_property|Tests:)"</automated>
  </verify>
  <done>
    - LWW-Map commutativity, idempotency, associativity property tests pass
    - OR-Map commutativity, idempotency property tests pass (associativity skipped with comment)
    - OR-Set associativity property test passes
    - No regressions in existing tests
  </done>
</task>

<task type="auto">
  <name>Task 2: Remaining serialization round-trip property tests</name>
  <files>test/property/serialization_property_test.gleam</files>
  <action>
Add three new round-trip property tests to the existing serialization_property_test.gleam file.

**MV-Register round-trip:** Generate two values with `bounded_int(0, 10)`. Create MV-Register with two concurrent sets (from different replicas, merged). Encode with `mv_register.to_json`, decode with `mv_register.from_json`. Compare using `list.sort(mv_register.value(...), int.compare)` (observable equality, not structural). Add imports: `lattice/mv_register`, `gleam/list`, `gleam/int`.

**OR-Map round-trip:** Create an OR-Map with GCounterSpec, update key "x" with a qcheck-generated increment. Encode with `or_map.to_json`, decode with `or_map.from_json`. Compare using `set.from_list(or_map.keys(...))` for keys equality. Add imports: `lattice/or_map`, `lattice/crdt`, `lattice/g_counter`, `gleam/set`.

**VersionVector round-trip:** Generate two non-negative ints. Create VersionVector with increment calls for "A" (a times) and "B" (b times). Encode with `version_vector.to_json`, decode with `version_vector.from_json`. Compare using `version_vector.get(decoded, "A")` and `version_vector.get(decoded, "B")` against originals. Add import: `lattice/version_vector`.

Follow the exact pattern of existing round-trip tests in the file (case decoded { Ok(d) -> ..., Error(_) -> expect.to_be_true(False) }).
  </action>
  <verify>
    <automated>gleam test 2>&1 | grep -E "(round_trip|Tests:)"</automated>
  </verify>
  <done>
    - mv_register_json_round_trip__test passes
    - or_map_json_round_trip__test passes
    - version_vector_json_round_trip__test passes
    - All existing round-trip tests still pass
  </done>
</task>

</tasks>

<verification>
1. `gleam test` — all tests pass including new map property tests and round-trip tests
2. `gleam check` — no type errors
3. Verify map_property_test.gleam has: lww_map_commutativity, lww_map_idempotency, lww_map_associativity, or_map_commutativity, or_map_idempotency, or_set_associativity
4. Verify serialization_property_test.gleam has: mv_register_json_round_trip, or_map_json_round_trip, version_vector_json_round_trip
</verification>

<success_criteria>
- TEST-01 complete: All CRDT types have commutativity tests (maps added)
- TEST-02 complete: All applicable types have associativity tests (LWW-Map, OR-Set added; OR-Map, MV-Register skipped with documented reason)
- TEST-03 complete: All CRDT types have idempotency tests (maps added)
- TEST-07 complete: All CRDT types have serialization round-trip property tests
- No regressions in existing 187 tests
</success_criteria>

<output>
After completion, create `.planning/phases/04-advanced-testing/04-advanced-testing-02-SUMMARY.md`
</output>
