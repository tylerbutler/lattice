---
phase: 01-foundation-counters
plan: 03
type: execute
wave: 3
depends_on:
  - 02
files_modified:
  - gleam.toml
  - test/property/counter_property_test.gleam
autonomous: true
requirements:
  - TEST-01
  - TEST-02

must_haves:
  truths:
    - "G-Counter merge satisfies commutativity: merge(a, b) == merge(b, a)"
    - "G-Counter merge satisfies associativity: merge(merge(a, b), c) == merge(a, merge(b, c))"
    - "G-Counter merge satisfies idempotency: merge(a, a) == a"
    - "PN-Counter merge satisfies commutativity"
    - "PN-Counter merge satisfies associativity"
    - "PN-Counter merge satisfies idempotency"
    - "Property tests shrink correctly (qcheck generators produce minimal counterexamples)"
  artifacts:
    - path: "test/property/counter_property_test.gleam"
      provides: "Property-based tests for counter merge laws"
      tests: ["commutativity", "associativity", "idempotency"]
  key_links:
    - from: "test/property/counter_property_test.gleam"
      to: "src/lattice/g_counter.gleam"
      via: "qcheck generators"
      pattern: "qcheck.test"
    - from: "test/property/counter_property_test.gleam"
      to: "src/lattice/pn_counter.gleam"
      via: "qcheck generators"
      pattern: "qcheck.test"
---

<objective>
Add qcheck property-based testing library and implement merge law verification for counters. Property tests verify CRDT correctness: commutativity, associativity, idempotency must hold for all inputs.

Purpose: Verify counter CRDTs satisfy merge laws required for convergence
Output: Property tests pass, proving merge law compliance
</objective>

<execution_context>
@/home/tylerbu/.config/opencode/get-shit-done/workflows/execute-plan.md
@/home/tylerbu/.config/opencode/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/01-foundation-counters/01-CONTEXT.md
@.planning/research/SUMMARY.md

# Dependencies:
# - Plan 01: G-Counter implemented
# - Plan 02: PN-Counter implemented
# - This plan: Property tests require both counters

# Research highlights (from SUMMARY.md):
# - qcheck is CRITICAL for verifying merge laws
# - Ditto's research found bugs in academic papers through property testing
# - Merge laws: commutativity, associativity, idempotency

# User discretion:
# - Whether to use qcheck (research strongly recommends yes)
</context>

<tasks>

<task type="auto">
  <name>Task 1: Add qcheck to dev-dependencies</name>
  <files>gleam.toml</files>
  <action>
Add qcheck as a dev-dependency in gleam.toml:
- qcheck version ">= 1.0.0 and < 2.0.0"

Run `gleam deps download` to fetch dependencies.
  </action>
  <verify>
    <automated>gleam deps download && gleam deps list</automated>
  </verify>
  <done>qcheck available in project dependencies</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: TDD - Property tests for G-Counter merge laws</name>
  <files>test/property/counter_property_test.gleam</files>
  <behavior>
    - Property: merge(a, b) == merge(b, a) for all G-Counters (commutativity)
    - Property: merge(merge(a, b), c) == merge(a, merge(b, c)) for all (associativity)
    - Property: merge(a, a) == a for all G-Counters (idempotency)
    - Property: value only increases or stays same after merge (monotonicity)
  </behavior>
  <action>
Create test/property/ directory and counter_property_test.gleam:

1. Import qcheck and counter modules
2. Define G-Counter generator:
   - Generate random number of replicas (1-5)
   - For each replica, generate random counts (0-100)
3. Write property tests:
   - commutativity: for_all(counter_gen, fn(a) for_all(counter_gen, fn(b) merge(a,b) == merge(b,a)))
   - associativity: for_all(counter_gen, fn(a) for_all(counter_gen, fn(b) for_all(counter_gen, fn(c) merge(merge(a,b),c) == merge(a,merge(b,c)))))
   - idempotency: for_all(counter_gen, fn(a) merge(a,a) == a)
   - monotonicity: for_all(counter_gen, fn(a) for_all(counter_gen, fn(b) value(merge(a,b)) >= value(a)))

Run tests - they should FAIL (red) first, then implement minimal fix.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>All G-Counter property tests pass</done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: TDD - Property tests for PN-Counter merge laws</name>
  <files>test/property/counter_property_test.gleam</files>
  <behavior>
    - Property: merge(a, b) == merge(b, a) for all PN-Counters (commutativity)
    - Property: merge(merge(a, b), c) == merge(a, merge(b, c)) for all (associativity)
    - Property: merge(a, a) == a for all PN-Counters (idempotency)
    - Property: value converges after all-to-all exchange (convergence)
  </behavior>
  <action>
Add to counter_property_test.gleam:

1. Define PN-Counter generator:
   - Generate random number of replicas (1-5)
   - For each replica, generate random positive count (0-50) and negative count (0-50)
2. Write property tests for PN-Counter:
   - commutativity: same pattern as G-Counter
   - associativity: same pattern as G-Counter
   - idempotency: same pattern as G-Counter
   - convergence: all-to-all exchange produces identical values

Per research: property-based testing is non-negotiable for CRDT correctness.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>All PN-Counter property tests pass</done>
</task>

</tasks>

<verification>
Run `gleam test` - all property tests pass
Run `gleam check` - no type errors
</verification>

<success_criteria>
- qcheck added to dependencies
- G-Counter merge laws verified: commutativity, associativity, idempotency, monotonicity
- PN-Counter merge laws verified: commutativity, associativity, idempotency, convergence
- All property tests pass
- Type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation-counters/{phase}-03-SUMMARY.md`
</output>
