---
phase: 01-foundation-counters
plan: 02
type: execute
wave: 2
depends_on:
  - 01
files_modified:
  - src/lattice/pn_counter.gleam
  - src/lattice/g_counter.gleam
  - test/counter/pn_counter_test.gleam
autonomous: true
requirements:
  - COUNTER-05
  - COUNTER-06
  - COUNTER-07
  - COUNTER-08
  - COUNTER-09

must_haves:
  truths:
    - "PN-Counter can be created with a replica ID"
    - "PN-Counter can increment by any integer (positive or negative)"
    - "PN-Counter increment adds to positive counter"
    - "PN-Counter decrement adds to negative counter"
    - "PN-Counter value returns positive_sum - negative_sum"
    - "PN-Counter merge combines both positive and negative counters"
  artifacts:
    - path: "src/lattice/pn_counter.gleam"
      provides: "PN-Counter implementation"
      exports: ["new", "increment", "decrement", "value", "merge"]
    - path: "test/counter/pn_counter_test.gleam"
      provides: "PN-Counter unit tests"
      tests: ["new", "increment", "decrement", "value", "merge"]
  key_links:
    - from: "src/lattice/pn_counter.gleam"
      to: "src/lattice/g_counter.gleam"
      via: "internal positive/negative G-Counter pair"
      pattern: "type t { T(positive: GCounter, negative: GCounter) }"
    - from: "test/counter/pn_counter_test.gleam"
      to: "src/lattice/pn_counter.gleam"
      via: "import and function calls"
      pattern: "import.*pn_counter"
---

<objective>
Implement PN-Counter (positive-negative counter) which allows both increments and decrements. Built on top of G-Counter with separate positive and negative counters.

Purpose: Complete counter CRDT types; enables negative value tracking
Output: Working PN-Counter module with passing tests
</objective>

<execution_context>
@/home/tylerbu/.config/opencode/get-shit-done/workflows/execute-plan.md
@/home/tylerbu/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-foundation-counters/01-CONTEXT.md
@.planning/phases/01-foundation-counters/01-PLAN.md

# Dependencies:
# - Plan 01: Version Vector, G-Counter implemented
# - This plan: PN-Counter builds on G-Counter

# User locked decisions:
# - PN-Counter: pair of G-Counters (positive, negative)
# - Value: positive sum - negative sum
# - Tests in test/counter/ subdirectory
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: TDD - PN-Counter (COUNTER-05 to COUNTER-09)</name>
  <files>src/lattice/pn_counter.gleam, test/counter/pn_counter_test.gleam</files>
  <behavior>
    - Test: new("A") returns counter with positive and negative G-Counters at 0
    - Test: increment(counter, 3) adds 3 to positive counter
    - Test: decrement(counter, 2) adds 2 to negative counter
    - Test: value({positive: {A:5}, negative: {A:2}}) returns 3
    - Test: value({positive: {A:3}, negative: {A:7}}) returns -4
    - Test: merge preserves both positive and negative from each replica
    - Test: concurrent increments and decrements merge correctly
  </behavior>
  <action>
Implement pn_counter.gleam with:
- Type: `pub type t { T(positive: GCounter, negative: GCounter) }`
- `new(replica_id)` - creates pair of G-Counters at 0
- `increment(counter, delta)` - increments positive G-Counter (delta >= 0)
- `decrement(counter, delta)` - increments negative G-Counter (delta >= 0)
- `value(counter)` - returns positive.value - negative.value
- `merge(a, b)` - merges both positive and negative G-Counters separately

Per user decision: built on two G-Counters (positive/negative).

Create test/counter/pn_counter_test.gleam with gleeunit tests.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>PN-Counter passes all unit tests; value correctly computes positive-negative</done>
</task>

</tasks>

<verification>
Run `gleam test` - all tests pass
Run `gleam check` - no type errors
</verification>

<success_criteria>
- PN-Counter: new, increment, decrement, value, merge all work correctly
- All counter tests pass
- Type checking passes
- G-Counter still works after PN-Counter imports it
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation-counters/{phase}-02-SUMMARY.md`
</output>
