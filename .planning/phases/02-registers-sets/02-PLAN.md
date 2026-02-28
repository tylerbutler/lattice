---
phase: 02-registers-sets
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - src/lattice/g_set.gleam
  - src/lattice/two_p_set.gleam
  - test/set/g_set_test.gleam
  - test/set/two_p_set_test.gleam
autonomous: true
requirements:
  - SET-01
  - SET-02
  - SET-03
  - SET-04
  - SET-05
  - SET-06
  - SET-07
  - SET-08
  - SET-09
  - SET-10
  - SET-11

must_haves:
  truths:
    - "G-Set new() creates an empty set"
    - "G-Set add(set, element) includes the element"
    - "G-Set contains(set, element) returns True after add"
    - "G-Set value() returns all added elements as a gleam/set.Set"
    - "G-Set merge is union: merged set contains elements from both"
    - "G-Set is grow-only: no remove operation exists"
    - "2P-Set new() creates empty added and removed sets"
    - "2P-Set add then contains returns True"
    - "2P-Set remove then contains returns False (tombstone is permanent)"
    - "2P-Set value() returns added minus removed (set difference)"
    - "2P-Set merge unions both added and removed sets"
    - "2P-Set tombstone is permanent: after remove, re-add does NOT restore element"
  artifacts:
    - path: "src/lattice/g_set.gleam"
      provides: "G-Set implementation"
      exports: ["new", "add", "contains", "value", "merge"]
    - path: "src/lattice/two_p_set.gleam"
      provides: "2P-Set implementation"
      exports: ["new", "add", "remove", "contains", "value", "merge"]
    - path: "test/set/g_set_test.gleam"
      provides: "G-Set unit tests"
      tests: ["new_empty", "add_contains", "value", "merge_union"]
    - path: "test/set/two_p_set_test.gleam"
      provides: "2P-Set unit tests"
      tests: ["new_empty", "add_contains", "remove_tombstone", "value_difference", "merge_unions", "tombstone_permanent"]
  key_links:
    - from: "src/lattice/g_set.gleam"
      to: "gleam/set"
      via: "wraps gleam/set.Set for internal storage"
      pattern: "import gleam/set"
    - from: "src/lattice/two_p_set.gleam"
      to: "gleam/set"
      via: "uses gleam/set for added and removed sets"
      pattern: "import gleam/set"
    - from: "test/set/g_set_test.gleam"
      to: "src/lattice/g_set.gleam"
      via: "import and function calls"
      pattern: "import lattice/g_set"
    - from: "test/set/two_p_set_test.gleam"
      to: "src/lattice/two_p_set.gleam"
      via: "import and function calls"
      pattern: "import lattice/two_p_set"
---

<objective>
Implement G-Set (grow-only set) and 2P-Set (two-phase set with tombstones) CRDT types with TDD approach. G-Set is the simplest set CRDT (add-only, merge is union). 2P-Set adds remove capability with permanent tombstones.

Purpose: Deliver the two simpler set CRDT types required for Phase 2
Output: Working G-Set and 2P-Set modules with passing unit tests
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

# Key gleam/set API (from research):
#   set.new() -> Set(a)
#   set.insert(set, element) -> Set(a)
#   set.contains(set, element) -> Bool
#   set.union(set_a, set_b) -> Set(a)
#   set.difference(set_a, set_b) -> Set(a)
#   set.from_list(list) -> Set(a)
#   set.to_list(set) -> List(a)
#   set.is_empty(set) -> Bool
#   set.delete(set, element) -> Set(a)

# Phase 1 established patterns:
# - Record wrapping internal data structure
# - Tests use startest/expect with expect.to_equal
# - One test file per CRDT type
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: TDD - G-Set (SET-01 to SET-05)</name>
  <files>src/lattice/g_set.gleam, test/set/g_set_test.gleam</files>
  <behavior>
    - Test: new() creates empty set; value returns empty set; contains("a") returns False
    - Test: add(new(), "hello") then contains("hello") returns True
    - Test: add multiple elements; value() returns set containing all of them
    - Test: add duplicate element is idempotent (set semantics)
    - Test: merge({a,b}, {b,c}) returns set containing {a,b,c} (union)
    - Test: merge(empty, set) returns set
    - Test: merge(set, empty) returns set
  </behavior>
  <action>
Create test/set/ directory and g_set_test.gleam with the tests above.

Implement src/lattice/g_set.gleam:

```gleam
import gleam/set

pub type GSet(a) {
  GSet(members: set.Set(a))
}
```

- `new() -> GSet(a)` — create with empty `set.new()`
- `add(gset: GSet(a), element: a) -> GSet(a)` — `GSet(set.insert(gset.members, element))`
- `contains(gset: GSet(a), element: a) -> Bool` — `set.contains(gset.members, element)`
- `value(gset: GSet(a)) -> set.Set(a)` — return `gset.members`
- `merge(a: GSet(el), b: GSet(el)) -> GSet(el)` — `GSet(set.union(a.members, b.members))`

This is the simplest CRDT in the project. Every operation maps directly to a `gleam/set` function. No complex logic needed.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>G-Set: new creates empty set; add inserts element; contains checks membership; value returns inner set; merge computes union; all tests pass</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: TDD - 2P-Set (SET-06 to SET-11)</name>
  <files>src/lattice/two_p_set.gleam, test/set/two_p_set_test.gleam</files>
  <behavior>
    - Test: new() creates empty set; value returns empty set; contains("a") returns False
    - Test: add(new(), "hello") then contains("hello") returns True
    - Test: add("hello") then remove("hello") then contains("hello") returns False
    - Test: value after add("a"), add("b"), remove("b") returns set containing only {"a"}
    - Test: Tombstone is permanent: add("x"), remove("x"), add("x") — contains("x") returns False
    - Test: remove without prior add creates tombstone; future add of same element is blocked
    - Test: merge combines added sets (union) and removed sets (union):
      - set_a has added={"a","b"}, removed={"b"}
      - set_b has added={"b","c"}, removed={}
      - merged has added={"a","b","c"}, removed={"b"}
      - value of merged = {"a","c"} (b is tombstoned)
    - Test: merge(empty, set) returns set
    - Test: merge(set, empty) returns set
  </behavior>
  <action>
Create test/set/two_p_set_test.gleam with the tests above.

Implement src/lattice/two_p_set.gleam:

```gleam
import gleam/set

pub type TwoPSet(a) {
  TwoPSet(added: set.Set(a), removed: set.Set(a))
}
```

- `new() -> TwoPSet(a)` — `TwoPSet(added: set.new(), removed: set.new())`
- `add(tpset: TwoPSet(a), element: a) -> TwoPSet(a)` — Insert element into `added` set. NOTE: Even if element is in `removed`, we still add it to `added` — but `contains` and `value` will exclude it because `removed` takes precedence.
- `remove(tpset: TwoPSet(a), element: a) -> TwoPSet(a)` — Insert element into `removed` set (tombstone). This is permanent — once in `removed`, the element is effectively dead.
- `contains(tpset: TwoPSet(a), element: a) -> Bool` — `set.contains(tpset.added, element) && !set.contains(tpset.removed, element)`. Must check both sets.
- `value(tpset: TwoPSet(a)) -> set.Set(a)` — `set.difference(tpset.added, tpset.removed)`. Returns elements that have been added but NOT removed.
- `merge(a: TwoPSet(el), b: TwoPSet(el)) -> TwoPSet(el)` — Union both added sets AND union both removed sets: `TwoPSet(added: set.union(a.added, b.added), removed: set.union(a.removed, b.removed))`.

KEY SEMANTIC: The 2P-Set tombstone is PERMANENT. Once an element is in the `removed` set, it can never be observed again, even if re-added. This is the fundamental limitation of 2P-Set (which OR-Set solves).

Use `gleam/bool` if needed for the `!set.contains(...)` negation (Gleam uses `bool.negate` or pattern matching, not `!` operator). Alternatively, use `case set.contains(removed, e) { True -> False False -> set.contains(added, e) }`.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>2P-Set: new creates empty set; add inserts to added set; remove creates permanent tombstone; contains checks added minus removed; value returns set difference; merge unions both sets; tombstone permanence verified; all tests pass</done>
</task>

</tasks>

<verification>
Run `gleam test` - all G-Set and 2P-Set tests pass
Run `gleam check` - no type errors
</verification>

<success_criteria>
- G-Set: new, add, contains, value, merge all work correctly
- G-Set merge is set union
- 2P-Set: new, add, remove, contains, value, merge all work correctly
- 2P-Set tombstone is permanent (re-add after remove does not restore)
- 2P-Set merge unions both added and removed sets
- All unit tests pass
- Type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/02-registers-sets/02-registers-sets-02-SUMMARY.md`
</output>
