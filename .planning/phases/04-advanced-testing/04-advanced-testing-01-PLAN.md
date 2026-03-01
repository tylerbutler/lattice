---
phase: 04-advanced-testing
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/lattice/dot_context.gleam
  - test/clock/dot_context_test.gleam
autonomous: true
requirements:
  - CLOCK-06
  - CLOCK-07
  - CLOCK-08
  - CLOCK-09

must_haves:
  truths:
    - "DotContext new() creates empty context with no dots"
    - "add_dot inserts a (replica_id, counter) dot into the context"
    - "remove_dots removes specified dots from the context"
    - "contains_dots returns True only when all given dots are present"
    - "contains_dots returns False if any dot is missing"
  artifacts:
    - path: "src/lattice/dot_context.gleam"
      provides: "Dot and DotContext types with new, add_dot, remove_dots, contains_dots"
      exports: ["Dot", "DotContext", "new", "add_dot", "remove_dots", "contains_dots"]
    - path: "test/clock/dot_context_test.gleam"
      provides: "Unit tests for all DotContext operations"
      min_lines: 40
  key_links:
    - from: "test/clock/dot_context_test.gleam"
      to: "src/lattice/dot_context.gleam"
      via: "import lattice/dot_context"
      pattern: "import lattice/dot_context"
---

<objective>
Implement the Dot Context causal metadata module and its unit tests.

Purpose: Dot Context tracks individual (replica_id, counter) events ("dots") for causal reasoning in delta-CRDTs and OR-Set-based structures. This completes CLOCK-06 to CLOCK-09, the final infrastructure requirement.

Output: New `dot_context.gleam` module with `Dot` type, `DotContext` type, and four operations: `new()`, `add_dot()`, `remove_dots()`, `contains_dots()`. Full unit test coverage.
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

Existing clock module for reference pattern:
@src/lattice/version_vector.gleam
@test/clock/version_vector_test.gleam
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Implement DotContext module with TDD</name>
  <files>src/lattice/dot_context.gleam, test/clock/dot_context_test.gleam</files>
  <behavior>
    - new() returns empty DotContext (contains_dots(new(), []) is True)
    - add_dot(ctx, "A", 1) adds Dot("A", 1); contains_dots confirms presence
    - add_dot twice with same dot is idempotent (set semantics)
    - remove_dots(ctx, [Dot("A", 1)]) removes that dot; contains_dots returns False
    - remove_dots with dot not in context is a no-op (no error)
    - contains_dots with empty list returns True (vacuously true)
    - contains_dots returns False if any one dot is missing
    - Multiple dots from different replicas coexist correctly
  </behavior>
  <action>
Write tests first in test/clock/dot_context_test.gleam, then implement src/lattice/dot_context.gleam.

**Implementation (src/lattice/dot_context.gleam):**

```gleam
import gleam/list
import gleam/set

/// A Dot uniquely identifies a single event: a write by a replica at a specific counter value
pub type Dot {
  Dot(replica_id: String, counter: Int)
}

/// A DotContext tracks which events (dots) have been observed
pub type DotContext {
  DotContext(dots: set.Set(Dot))
}

/// Create a new empty DotContext
pub fn new() -> DotContext {
  DotContext(dots: set.new())
}

/// Add a specific dot to the context
pub fn add_dot(context: DotContext, replica_id: String, counter: Int) -> DotContext {
  DotContext(dots: set.insert(context.dots, Dot(replica_id:, counter:)))
}

/// Remove a list of dots from the context
pub fn remove_dots(context: DotContext, dots: List(Dot)) -> DotContext {
  DotContext(
    dots: list.fold(dots, context.dots, fn(acc, dot) { set.delete(acc, dot) }),
  )
}

/// Check if all given dots are present in the context
pub fn contains_dots(context: DotContext, dots: List(Dot)) -> Bool {
  list.all(dots, fn(dot) { set.contains(context.dots, dot) })
}
```

**Test file (test/clock/dot_context_test.gleam):**

Cover: new creates empty context, add_dot adds single dot, add_dot idempotent, multiple replicas, remove_dots removes specific dots, remove_dots no-op for missing, contains_dots empty list is True, contains_dots partial match returns False.

Use `startest/expect` assertions consistent with existing clock tests. Import `lattice/dot_context` and the `Dot` type.
  </action>
  <verify>
    <automated>gleam test 2>&1 | grep -E "(dot_context|Tests:)"</automated>
  </verify>
  <done>
    - src/lattice/dot_context.gleam exists with Dot, DotContext types and new/add_dot/remove_dots/contains_dots functions
    - test/clock/dot_context_test.gleam has 8+ test functions all passing
    - `gleam test` passes with no failures
  </done>
</task>

</tasks>

<verification>
1. `gleam test` — all tests pass including new dot_context tests
2. `gleam check` — no type errors
3. Verify dot_context.gleam exports: Dot, DotContext, new, add_dot, remove_dots, contains_dots
</verification>

<success_criteria>
- Dot Context module implements CLOCK-06 (new), CLOCK-07 (add_dot), CLOCK-08 (remove_dots), CLOCK-09 (contains_dots)
- All 8+ unit tests pass
- No regressions in existing 187 tests
</success_criteria>

<output>
After completion, create `.planning/phases/04-advanced-testing/04-advanced-testing-01-SUMMARY.md`
</output>
