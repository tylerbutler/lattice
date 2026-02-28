---
phase: 02-registers-sets
plan: 04
type: execute
wave: 2
depends_on:
  - 01
  - 02
  - 03
files_modified:
  - test/property/register_set_property_test.gleam
autonomous: true
requirements:
  - TEST-01
  - TEST-02
  - TEST-03

must_haves:
  truths:
    - "LWW-Register merge satisfies commutativity: value(merge(a, b)) == value(merge(b, a))"
    - "LWW-Register merge satisfies associativity: value(merge(merge(a,b),c)) == value(merge(a,merge(b,c)))"
    - "LWW-Register merge satisfies idempotency: merge(a, a) == a"
    - "MV-Register merge satisfies commutativity on values"
    - "MV-Register merge satisfies idempotency: merge(a, a) produces same values as a"
    - "G-Set merge satisfies commutativity: value(merge(a, b)) == value(merge(b, a))"
    - "G-Set merge satisfies associativity"
    - "G-Set merge satisfies idempotency: merge(a, a) == a"
    - "2P-Set merge satisfies commutativity"
    - "2P-Set merge satisfies associativity"
    - "2P-Set merge satisfies idempotency"
    - "OR-Set merge satisfies commutativity on values"
    - "OR-Set merge satisfies idempotency on values"
    - "All property tests pass with qcheck small_test_config"
  artifacts:
    - path: "test/property/register_set_property_test.gleam"
      provides: "Property-based tests for merge laws on all register and set types"
      tests: ["commutativity", "associativity", "idempotency"]
  key_links:
    - from: "test/property/register_set_property_test.gleam"
      to: "src/lattice/lww_register.gleam"
      via: "qcheck property tests"
      pattern: "import lattice/lww_register"
    - from: "test/property/register_set_property_test.gleam"
      to: "src/lattice/mv_register.gleam"
      via: "qcheck property tests"
      pattern: "import lattice/mv_register"
    - from: "test/property/register_set_property_test.gleam"
      to: "src/lattice/g_set.gleam"
      via: "qcheck property tests"
      pattern: "import lattice/g_set"
    - from: "test/property/register_set_property_test.gleam"
      to: "src/lattice/two_p_set.gleam"
      via: "qcheck property tests"
      pattern: "import lattice/two_p_set"
    - from: "test/property/register_set_property_test.gleam"
      to: "src/lattice/or_set.gleam"
      via: "qcheck property tests"
      pattern: "import lattice/or_set"
---

<objective>
Add property-based tests verifying merge laws (commutativity, associativity, idempotency) for all register and set CRDT types implemented in Phase 2. Uses qcheck with established small_test_config pattern from Phase 1.

Purpose: Prove CRDT correctness through property-based testing — merge laws are required for convergence
Output: Property tests pass for all 5 new CRDT types, verifying merge law compliance
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/02-registers-sets/02-CONTEXT.md
@.planning/phases/02-registers-sets/02-RESEARCH.md
@test/property/counter_property_test.gleam

# CRITICAL: Follow exact qcheck pattern from Phase 1 counter_property_test.gleam:
#   fn small_test_config() -> qcheck.Config {
#     qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
#   }
#   qcheck.run(small_test_config(), generator, fn(input) { ... Nil })
#   Use qcheck.map2, qcheck.map3 for multi-input properties
#   Use qcheck.bounded_int, qcheck.small_non_negative_int for generators
#   Use startest/expect for assertions

# Phase 1 SUMMARY-03 warning: qcheck shrinking can timeout.
# MUST use small_test_config (test_count: 10, max_retries: 3).
# Keep generators simple — bounded ints and basic string ops.

# Type interfaces needed (from Plans 01-03):
# LWW-Register: new(value, timestamp), set(reg, val, ts), value(reg), merge(a, b)
# MV-Register: new(replica_id), set(reg, val), value(reg) -> List(a), merge(a, b)
# G-Set: new(), add(set, el), contains(set, el), value(set), merge(a, b)
# 2P-Set: new(), add(set, el), remove(set, el), contains(set, el), value(set), merge(a, b)
# OR-Set: new(replica_id), add(set, el), remove(set, el), contains(set, el), value(set), merge(a, b)
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Property tests for registers (LWW-Register + MV-Register)</name>
  <files>test/property/register_set_property_test.gleam</files>
  <behavior>
    LWW-Register properties:
    - Commutativity: value(merge(a, b)) == value(merge(b, a)) for any two LWW-Registers
    - Associativity: value(merge(merge(a,b),c)) == value(merge(a,merge(b,c))) for any three
    - Idempotency: merge(a, a) == a for any LWW-Register

    MV-Register properties:
    - Commutativity: sorted value(merge(a, b)) == sorted value(merge(b, a))
    - Idempotency: sorted value(merge(a, a)) == sorted value(a)
    NOTE: MV-Register associativity is complex because merge changes vclock state.
    For Phase 2, test commutativity and idempotency. Associativity test is optional
    (it requires carefully constructed triples where vclock state is consistent).
  </behavior>
  <action>
Create test/property/register_set_property_test.gleam.

Import all needed modules:
```gleam
import lattice/lww_register
import lattice/mv_register
import lattice/g_set
import lattice/two_p_set
import lattice/or_set
import gleam/list
import gleam/set
import qcheck
import startest/expect
```

Define shared config (same as counter_property_test.gleam):
```gleam
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}
```

**LWW-Register property tests:**

1. `lww_register_commutativity__test()`:
   - Generator: `qcheck.map2(qcheck.bounded_int(0, 100), qcheck.bounded_int(0, 100), fn(a, b) { #(a, b) })`
   - Create reg_a = new("val_a", ts_a), reg_b = new("val_b", ts_b)
   - Assert: `lww_register.value(lww_register.merge(reg_a, reg_b)) == lww_register.value(lww_register.merge(reg_b, reg_a))`

2. `lww_register_associativity__test()`:
   - Generator: `qcheck.map3(qcheck.bounded_int(0, 100), qcheck.bounded_int(0, 100), qcheck.bounded_int(0, 100), fn(a, b, c) { #(a, b, c) })`
   - Create three registers with different timestamps
   - Assert: value of left-grouped merge == value of right-grouped merge

3. `lww_register_idempotency__test()`:
   - Generator: `qcheck.bounded_int(0, 100)`
   - Create register, merge with self
   - Assert: `lww_register.merge(reg, reg) == reg`

**MV-Register property tests:**

4. `mv_register_commutativity__test()`:
   - Generator: `qcheck.map2(qcheck.bounded_int(0, 10), qcheck.bounded_int(0, 10), fn(a, b) { #(a, b) })`
   - Create reg_a = set(new("A"), a), reg_b = set(new("B"), b) — use Int values
   - Merge both ways, sort the value lists, compare
   - `list.sort(mv_register.value(mv_register.merge(reg_a, reg_b)), int.compare)` == same for reverse merge
   - NOTE: value() returns a List — order may differ, so sort before comparing

5. `mv_register_idempotency__test()`:
   - Generator: `qcheck.bounded_int(0, 10)`
   - Create register with a value, merge with self
   - Assert: sorted value(merge(reg, reg)) == sorted value(reg)

**IMPORTANT:** For MV-Register tests, the value() returns `List(a)` where order is not guaranteed (comes from dict.values). Sort the lists before comparing. Use `list.sort(values, int.compare)` for Int values.

**IMPORTANT:** qcheck generators must produce simple values. Do NOT try to generate full CRDT state objects — generate the parameters (ints, strings) and construct CRDTs from them in the test body. This follows the Phase 1 pattern exactly.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>LWW-Register passes commutativity, associativity, idempotency property tests; MV-Register passes commutativity and idempotency property tests; all property tests run without timeout</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Property tests for sets (G-Set + 2P-Set + OR-Set)</name>
  <files>test/property/register_set_property_test.gleam</files>
  <behavior>
    G-Set properties:
    - Commutativity: value(merge(a, b)) == value(merge(b, a))
    - Associativity: value(merge(merge(a,b),c)) == value(merge(a,merge(b,c)))
    - Idempotency: merge(a, a) == a (structural equality on GSet)

    2P-Set properties:
    - Commutativity: value(merge(a, b)) == value(merge(b, a))
    - Associativity: value(merge(merge(a,b),c)) == value(merge(a,merge(b,c)))
    - Idempotency: merge(a, a) == a (structural equality on TwoPSet)

    OR-Set properties:
    - Commutativity: value(merge(a, b)) == value(merge(b, a))
    - Idempotency: value(merge(a, a)) == value(a)
    NOTE: OR-Set associativity is complex because merge keeps replica_id from first
    argument. Test commutativity and idempotency on values (observable behavior).
  </behavior>
  <action>
Add to the existing register_set_property_test.gleam file:

**G-Set property tests:**

6. `g_set_commutativity__test()`:
   - Generator: `qcheck.map2(qcheck.bounded_int(0, 20), qcheck.bounded_int(0, 20), fn(a, b) { #(a, b) })`
   - Create set_a with element a, set_b with element b (use ints directly)
   - Assert: `g_set.value(g_set.merge(set_a, set_b)) == g_set.value(g_set.merge(set_b, set_a))`

7. `g_set_associativity__test()`:
   - Generator: `qcheck.map3(...)` with three bounded_ints
   - Create three G-Sets, each with one element
   - Assert value of left-grouped merge == value of right-grouped merge

8. `g_set_idempotency__test()`:
   - Generator: `qcheck.bounded_int(0, 20)`
   - Create G-Set with one element, merge with self
   - Assert: `g_set.merge(set, set) == set` (structural equality)

**2P-Set property tests:**

9. `two_p_set_commutativity__test()`:
   - Generator: `qcheck.map2(qcheck.bounded_int(0, 20), qcheck.bounded_int(0, 20), fn(a, b) { #(a, b) })`
   - Create two 2P-Sets with different add/remove patterns
   - Assert: value(merge(a, b)) == value(merge(b, a))

10. `two_p_set_associativity__test()`:
    - Generator: `qcheck.map3(...)` with three bounded_ints
    - Assert value of left-grouped merge == value of right-grouped merge

11. `two_p_set_idempotency__test()`:
    - Generator: `qcheck.bounded_int(0, 20)`
    - Create 2P-Set, merge with self
    - Assert: `two_p_set.merge(set, set) == set`

**OR-Set property tests:**

12. `or_set_commutativity__test()`:
    - Generator: `qcheck.map2(qcheck.bounded_int(0, 10), qcheck.bounded_int(0, 10), fn(a, b) { #(a, b) })`
    - Create set_a = add(new("A"), a), set_b = add(new("B"), b)
    - Assert: `or_set.value(or_set.merge(set_a, set_b)) == or_set.value(or_set.merge(set_b, set_a))`
    - Compare on value (observable state), not structural equality (replica_id differs in merged result)

13. `or_set_idempotency__test()`:
    - Generator: `qcheck.bounded_int(0, 10)`
    - Create OR-Set with one element, merge with self
    - Assert: `or_set.value(or_set.merge(set, set)) == or_set.value(set)`
    - Compare on value level since replica_id/counter may differ structurally

**IMPORTANT:** For set-valued comparisons (G-Set, 2P-Set), `gleam/set` equality uses structural comparison — `set.from_list([1,2]) == set.from_list([2,1])` should be True in Gleam. Verify this works; if not, convert to sorted lists for comparison.

**IMPORTANT:** For OR-Set, compare on `value()` output (which returns `set.Set`), NOT structural equality of the ORSet record. The merged ORSet's replica_id and counter differ depending on merge order, but the observable value (element membership) should be identical.

**Generator strategy:** Keep generators simple — generate Int values, construct CRDTs in the test body. Follow Phase 1 pattern exactly. Do NOT try to generate complex CRDT state directly.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>G-Set passes commutativity, associativity, idempotency property tests; 2P-Set passes all three; OR-Set passes commutativity and idempotency on values; all property tests run without timeout using small_test_config</done>
</task>

</tasks>

<verification>
Run `gleam test` - all property tests pass (both register and set)
Run `gleam check` - no type errors
Confirm no qcheck timeouts (small_test_config prevents this)
</verification>

<success_criteria>
- LWW-Register: commutativity, associativity, idempotency property tests pass
- MV-Register: commutativity and idempotency property tests pass
- G-Set: commutativity, associativity, idempotency property tests pass
- 2P-Set: commutativity, associativity, idempotency property tests pass
- OR-Set: commutativity and idempotency property tests pass (value-level)
- All property tests complete without timeout
- Type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/02-registers-sets/02-registers-sets-04-SUMMARY.md`
</output>
