---
phase: 01-foundation-counters
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - gleam.toml
  - src/lattice.gleam
  - test/counter/g_counter_test.gleam
  - test/clock/version_vector_test.gleam
autonomous: true
requirements:
  - COUNTER-01
  - COUNTER-02
  - COUNTER-03
  - COUNTER-04
  - CLOCK-01
  - CLOCK-02
  - CLOCK-03
  - CLOCK-04
  - CLOCK-05

must_haves:
  truths:
    - "G-Counter can be created with a replica ID"
    - "G-Counter can increment by any non-negative integer"
    - "G-Counter value returns the sum of all increments"
    - "G-Counter merge uses pairwise max per replica"
    - "Version Vector can track per-replica logical clocks"
    - "Version Vector compare returns correct Order (Before/After/Concurrent/Equal)"
    - "Version Vector merge uses pairwise max"
  artifacts:
    - path: "src/lattice/g_counter.gleam"
      provides: "G-Counter implementation"
      exports: ["new", "increment", "value", "merge"]
    - path: "src/lattice/version_vector.gleam"
      provides: "Version Vector implementation"
      exports: ["new", "increment", "get", "compare", "merge"]
    - path: "test/counter/g_counter_test.gleam"
      provides: "G-Counter unit tests"
      tests: ["new", "increment", "value", "merge"]
    - path: "test/clock/version_vector_test.gleam"
      provides: "Version Vector unit tests"
      tests: ["new", "increment", "get", "compare", "merge"]
  key_links:
    - from: "src/lattice/g_counter.gleam"
      to: "src/lattice/version_vector.gleam"
      via: "internal Dict(ReplicaId, Int)"
      pattern: "type t = Dict(String, Int)"
    - from: "test/counter/g_counter_test.gleam"
      to: "src/lattice/g_counter.gleam"
      via: "import and function calls"
      pattern: "import.*g_counter"
---

<objective>
Implement Version Vector and G-Counter with TDD approach. Version Vector provides causal ordering; G-Counter is the simplest CRDT (increment-only counter).

Purpose: Establish foundational CRDT infrastructure and verify build/test pipeline works
Output: Working Version Vector and G-Counter modules with passing tests
</objective>

<execution_context>
@/home/tylerbu/.config/opencode/get-shit-done/workflows/execute-plan.md
@/home/tylerbu/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-foundation-counters/01-CONTEXT.md

# User locked decisions:
# - Version Vector before G-Counter (dependency)
# - Tests in test/counter/ and test/clock/ subdirectories
# - Use Dict for internal representation
# - TDD: tests first (red), then minimal implementation (green), then refactor
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: TDD - Version Vector (CLOCK-01 to CLOCK-05)</name>
  <files>src/lattice/version_vector.gleam, test/clock/version_vector_test.gleam</files>
  <behavior>
    - Test: new() returns empty vector
    - Test: increment(vv, "A") increases "A" count by 1
    - Test: get(vv, "A") returns the count for replica "A"
    - Test: compare({A:1}, {A:2}) returns Before
    - Test: compare({A:2}, {A:1}) returns After
    - Test: compare({A:1, B:1}, {A:2, B:1}) returns Before (A is less)
    - Test: compare({A:1, B:2}, {A:2, B:1}) returns Concurrent (A&lt;B but B&gt;A)
    - Test: compare({A:1}, {A:1}) returns Equal
    - Test: merge({A:1}, {A:2}) returns {A:2}
    - Test: merge({A:1, B:1}, {A:2, B:0}) returns {A:2, B:1}
  </behavior>
  <action>
Implement version_vector.gleam with:
- Type: `pub type t = Dict(String, Int)`
- `new()` - returns empty Dict
- `increment(vv, replica_id)` - increments count for replica, returns new VV
- `get(vv, replica_id)` - returns count for replica (0 if not present)
- `compare(a, b)` - returns Order: Before, After, Concurrent, Equal
  - Before: a is causally before b (all keys in a <= keys in b, at least one less)
  - After: a is causally after b
  - Concurrent: neither is before the other
  - Equal: identical vectors
- `merge(a, b)` - pairwise max per key

Create test/clock/ directory and version_vector_test.gleam with gleeunit tests.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>Version Vector passes all unit tests; merge returns pairwise max</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: TDD - G-Counter (COUNTER-01 to COUNTER-04)</name>
  <files>src/lattice/g_counter.gleam, test/counter/g_counter_test.gleam</files>
  <behavior>
    - Test: new("A") returns counter with replica A at 0
    - Test: increment(counter, 1) increases value by 1
    - Test: increment(counter, 5) increases value by 5
    - Test: value({A:3, B:2}) returns 5
    - Test: merge({A:3}, {A:1, B:2}) returns {A:3, B:2} (max per key)
    - Test: merge({A:1, B:1}, {A:2}) returns {A:2, B:1}
  </behavior>
  <action>
Implement g_counter.gleam with:
- Type: `pub type t = Dict(String, Int)` (per CONTEXT.md, using Dict)
- `new(replica_id)` - returns counter with replica at 0
- `increment(counter, delta)` - increments this replica's count by delta (must be >= 0)
- `value(counter)` - returns sum of all replica counts
- `merge(a, b)` - pairwise max per replica (not sum!)

Per user decision: use Dict internally for replica tracking.

Create test/counter/ directory if needed and g_counter_test.gleam.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>G-Counter passes all unit tests; merge uses pairwise max, value returns sum</done>
</task>

</tasks>

<verification>
Run `gleam test` - all tests pass
Run `gleam check` - no type errors
</verification>

<success_criteria>
- Version Vector: new, increment, get, compare, merge all work correctly
- G-Counter: new, increment, value, merge all work correctly
- All unit tests pass
- Type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation-counters/{phase}-01-SUMMARY.md`
</output>
