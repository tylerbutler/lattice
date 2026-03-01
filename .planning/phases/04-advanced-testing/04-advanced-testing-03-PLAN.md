---
phase: 04-advanced-testing
plan: 03
type: execute
wave: 1
depends_on: []
files_modified:
  - test/property/advanced_property_test.gleam
autonomous: true
requirements:
  - TEST-04
  - TEST-05
  - TEST-06
  - TEST-08
  - TEST-09
  - TEST-10

must_haves:
  truths:
    - "merge(a, new()) preserves value(a) for all CRDT types (bottom identity)"
    - "value(merge(a, b)) >= value(a) and >= value(b) for counters (monotonicity)"
    - "value(merge(a, b)) is superset of value(a) and value(b) for G-Set (monotonicity)"
    - "3-replica all-to-all exchange produces identical values for all CRDT types (convergence)"
    - "Concurrent add and remove of same OR-Set element results in add winning (property-based)"
    - "2P-Set tombstoned element stays removed under all merge orders (property-based)"
    - "JSON round-trip works identically for cross-target compatibility (smoke test)"
  artifacts:
    - path: "test/property/advanced_property_test.gleam"
      provides: "Bottom identity, monotonicity, convergence, edge case, and cross-target tests"
      min_lines: 200
  key_links:
    - from: "test/property/advanced_property_test.gleam"
      to: "src/lattice/g_counter.gleam"
      via: "import lattice/g_counter"
      pattern: "import lattice/g_counter"
    - from: "test/property/advanced_property_test.gleam"
      to: "src/lattice/or_set.gleam"
      via: "import lattice/or_set"
      pattern: "import lattice/or_set"
---

<objective>
Complete advanced property-based test coverage: bottom identity, monotonicity, convergence, OR-Set add-wins, 2P-Set tombstone permanence, and cross-target serialization.

Purpose: These tests verify the deeper mathematical properties of CRDTs beyond basic merge laws. Bottom identity ensures new() is a true identity element. Monotonicity proves values only grow through merges. Convergence proves replicas converge after all-to-all exchange. Edge case tests verify OR-Set add-wins and 2P-Set tombstone semantics with property-based randomization. Cross-target tests confirm JSON portability.

Output: New `advanced_property_test.gleam` covering TEST-04 through TEST-06, TEST-08 through TEST-10.
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

Existing property test patterns:
@test/property/counter_property_test.gleam
@test/property/register_set_property_test.gleam

Existing unit tests with edge cases to extend:
@test/set/or_set_test.gleam
@test/set/two_p_set_test.gleam

Source modules under test:
@src/lattice/g_counter.gleam
@src/lattice/pn_counter.gleam
@src/lattice/lww_register.gleam
@src/lattice/mv_register.gleam
@src/lattice/g_set.gleam
@src/lattice/two_p_set.gleam
@src/lattice/or_set.gleam
@src/lattice/lww_map.gleam
@src/lattice/or_map.gleam
@src/lattice/crdt.gleam
@src/lattice/version_vector.gleam
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Bottom identity + monotonicity/inflation property tests</name>
  <files>test/property/advanced_property_test.gleam</files>
  <behavior>
    TEST-05 Bottom Identity (merge(a, new()) == a on observable values):
    - G-Counter: value(merge(counter, g_counter.new("B"))) == value(counter)
    - PN-Counter: value(merge(counter, pn_counter.new("B"))) == value(counter)
    - LWW-Register: value(merge(reg_ts_nonzero, lww_register.new("", 0))) == value(reg_ts_nonzero)
    - MV-Register: sorted value(merge(reg, mv_register.new("B"))) == sorted value(reg)
    - G-Set: value(merge(s, g_set.new())) == value(s)
    - 2P-Set: value(merge(s, two_p_set.new())) == value(s)
    - OR-Set: value(merge(s, or_set.new("B"))) == value(s)
    - LWW-Map: get(merge(m, lww_map.new()), key) == get(m, key)
    - OR-Map: set.from_list(keys(merge(m, or_map.new("B", spec)))) == set.from_list(keys(m))

    TEST-06 Monotonicity/Inflation:
    - G-Counter: value(merge(a, b)) >= value(a) AND >= value(b)
    - PN-Counter: same (value can be negative, but merge produces pairwise max)
    - G-Set: value(merge(a, b)) is superset of value(a) and value(b)
    - 2P-Set: size of removed set after merge >= size before (tombstones only grow)
    - OR-Set: value(merge(a, b)) is superset of value(a) and value(b) (add-wins)
    - LWW-Register: timestamp of winner after merge >= timestamp of either input
  </behavior>
  <action>
Create test/property/advanced_property_test.gleam. Use `small_test_config()` pattern (test_count: 10, max_retries: 3, seed: qcheck.seed(42)).

**Bottom identity tests (TEST-05):**

For each type, use qcheck to generate a scalar parameter, construct the CRDT, then merge with bottom (new()), and compare observable values.

Key caveats per research:
- LWW-Register: Use non-zero timestamp for the "non-bottom" register (`lww_register.new("value", ts + 1)` where ts is from generator). The bottom is `lww_register.new("", 0)`.
- MV-Register: Compare using `list.sort(mv_register.value(...), int.compare)`.
- OR-Map: Compare using `set.from_list(or_map.keys(...))`.
- LWW-Map: Compare using `lww_map.get(merged, "key")`.

**Monotonicity tests (TEST-06):**

Type-specific "increase" definitions per research Pattern 2:
- G-Counter, PN-Counter: `value(merged) >= value(input)` for both inputs
- G-Set: `set.is_subset(value(input), value(merged))` for both inputs
- 2P-Set: Check that both the added set and removed set sizes are non-decreasing (use internal access or just check value(merged) subset relationship carefully — for 2P-Set, value can shrink due to tombstones, but the lattice is on the pair (added, removed). Simplify: verify `set.is_subset(two_p_set.value(a), two_p_set.value(merged))` does NOT hold in general for 2P-Set because b may have tombstoned elements in a. Instead, test that the number of distinct elements in value(merged) <= size of value(a) union value(b). Better: just test G-Counter, PN-Counter, G-Set, OR-Set, and LWW-Register where monotonicity is cleanly defined.)
- OR-Set: `set.is_subset(value(input), value(merged))` for add-only scenario (both inputs only add, no removes)
- LWW-Register: Compare timestamps (higher timestamp always wins)

Skip 2P-Set and MV-Register monotonicity — their "increase" semantics are complex. Skip maps — LWW-Map has no clean monotonicity on observable values (keys can change winners). Focus on the 5 types with clean monotonicity: G-Counter, PN-Counter, G-Set, OR-Set (add-only), LWW-Register.

Import all CRDT modules, gleam/set, gleam/list, gleam/int, qcheck, startest/expect.
  </action>
  <verify>
    <automated>gleam test 2>&1 | grep -E "(bottom_identity|monoton|Tests:)"</automated>
  </verify>
  <done>
    - 9 bottom identity tests pass (one per CRDT type)
    - 5+ monotonicity tests pass (G-Counter, PN-Counter, G-Set, OR-Set, LWW-Register)
    - All tests use small_test_config() with fixed seed
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Convergence + OR-Set add-wins + 2P-Set tombstone + cross-target tests</name>
  <files>test/property/advanced_property_test.gleam</files>
  <behavior>
    TEST-04 Convergence (3-replica all-to-all):
    - G-Counter: 3 replicas, random increments, all-to-all merge, all produce same value()
    - PN-Counter: same pattern
    - G-Set: 3 replicas, random adds, all-to-all merge, all produce same value()
    - LWW-Register: 3 registers with distinct timestamps, all-to-all merge, all produce same value()
    - LWW-Map: 3 maps with distinct timestamps, all-to-all merge, all produce same get() results

    TEST-09 OR-Set concurrent add-wins (property-based):
    - For random element: A adds, B syncs+removes, A concurrently re-adds, merge → element present

    TEST-10 2P-Set tombstone permanence (property-based):
    - For random element: set_a adds+removes, set_b only adds, merge in both orders → element absent

    TEST-08 Cross-target serialization:
    - Deterministic smoke test: encode G-Counter, decode, values match (JSON is target-agnostic)
    - Deterministic smoke test: encode OR-Set, decode, values match
  </behavior>
  <action>
Add to test/property/advanced_property_test.gleam (created in Task 1).

**Convergence tests (TEST-04):**

Use qcheck.map3 for 3 independent operation parameters. Create 3 replicas with IDs "A", "B", "C". Each applies its operation. Then do all-to-all merge: each replica merges with both others. Compare observable values — all 3 must agree.

Per research Pattern 3:
- G-Counter: `g_counter.value(ra_final) == g_counter.value(rb_final) == g_counter.value(rc_final)`
- PN-Counter: same with `pn_counter.value`
- G-Set: `g_set.value(sa_final) == g_set.value(sb_final) == g_set.value(sc_final)`
- LWW-Register: use distinct timestamp ranges per replica (1-30, 31-60, 61-90) to avoid tie-break issues
- LWW-Map: use distinct timestamp ranges, compare via `lww_map.get(final, "key")`

Skip OR-Map, MV-Register, OR-Set, and 2P-Set convergence — their state construction for 3 independent replicas with proper causal metadata is complex. Focus on the 5 types where convergence is cleanly testable.

**OR-Set concurrent add-wins property (TEST-09):**

Per research Pattern 4:
1. replica_a adds element (random int to string)
2. replica_b syncs with a, then removes element
3. replica_a concurrently re-adds element (new tag)
4. Merge: add must win. `or_set.contains(merged, elem_str)` must be True.
Use `qcheck.bounded_int(0, 20)` for element generation.

**2P-Set tombstone permanence property (TEST-10):**

Per research Pattern 5:
1. set_a adds element then removes it
2. set_b adds element (concurrent)
3. Merge both orders: both must have `contains(elem_str)` == False
Use `qcheck.bounded_int(0, 20)` for element generation.

**Cross-target serialization smoke tests (TEST-08):**

Deterministic (not qcheck-driven). Create fixed CRDT instances, encode to JSON, decode, verify values match. This proves JSON contains no BEAM-specific types.

1. G-Counter: new("A") |> increment(42), encode, decode, compare value
2. OR-Set: new("A") |> add("hello") |> add("world"), encode, decode, compare value
3. LWW-Map: new() |> set("k", "v", 100), encode, decode, compare get("k")

Note: True cross-target verification requires `gleam test --target javascript` which is outside scope of this test file. The smoke tests verify JSON round-trip correctness which is necessary for cross-target compatibility.
  </action>
  <verify>
    <automated>gleam test 2>&1 | grep -E "(convergence|add_wins|tombstone|cross_target|target_agnostic|Tests:)"</automated>
  </verify>
  <done>
    - 5 convergence tests pass (G-Counter, PN-Counter, G-Set, LWW-Register, LWW-Map)
    - OR-Set concurrent add-wins property test passes
    - 2P-Set tombstone permanence property test passes
    - 3 cross-target serialization smoke tests pass
    - All tests use small_test_config() where applicable
    - No regressions in existing tests
  </done>
</task>

</tasks>

<verification>
1. `gleam test` — all tests pass including all new advanced property tests
2. `gleam check` — no type errors
3. Verify advanced_property_test.gleam contains: bottom identity tests (9 types), monotonicity tests (5 types), convergence tests (5 types), or_set add-wins property, two_p_set tombstone property, cross-target smoke tests (3 types)
</verification>

<success_criteria>
- TEST-04: Convergence proven for G-Counter, PN-Counter, G-Set, LWW-Register, LWW-Map
- TEST-05: Bottom identity proven for all 9 CRDT types
- TEST-06: Monotonicity proven for G-Counter, PN-Counter, G-Set, OR-Set, LWW-Register
- TEST-08: Cross-target JSON compatibility smoke-tested for 3 representative types
- TEST-09: OR-Set concurrent add-wins verified with property-based random elements
- TEST-10: 2P-Set tombstone permanence verified with property-based random elements under both merge orders
- No regressions in existing 187 tests
</success_criteria>

<output>
After completion, create `.planning/phases/04-advanced-testing/04-advanced-testing-03-SUMMARY.md`
</output>
