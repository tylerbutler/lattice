---
phase: 02-registers-sets
plan: 03
type: execute
wave: 1
depends_on: []
files_modified:
  - src/lattice/or_set.gleam
  - test/set/or_set_test.gleam
autonomous: true
requirements:
  - SET-12
  - SET-13
  - SET-14
  - SET-15
  - SET-16
  - SET-17

must_haves:
  truths:
    - "OR-Set new(replica_id) creates an empty set with the given replica"
    - "OR-Set add(set, element) makes contains(element) return True"
    - "OR-Set remove(set, element) makes contains(element) return False"
    - "OR-Set allows re-add after remove: add, remove, add results in element present"
    - "OR-Set concurrent add wins: if one replica adds while another removes, element is present after merge"
    - "OR-Set merge unions tag sets per element"
    - "OR-Set value() returns set of all elements with non-empty tag sets"
    - "OR-Set counter is propagated through merge (max of both counters)"
  artifacts:
    - path: "src/lattice/or_set.gleam"
      provides: "OR-Set implementation with add-wins semantics"
      exports: ["new", "add", "remove", "contains", "value", "merge"]
    - path: "test/set/or_set_test.gleam"
      provides: "OR-Set unit tests including add-wins scenarios"
      tests: ["new_empty", "add_contains", "remove", "re_add_after_remove", "concurrent_add_wins", "merge_union_tags", "value_set"]
  key_links:
    - from: "src/lattice/or_set.gleam"
      to: "gleam/dict"
      via: "element -> tag set mapping"
      pattern: "import gleam/dict"
    - from: "src/lattice/or_set.gleam"
      to: "gleam/set"
      via: "tag sets per element"
      pattern: "import gleam/set"
    - from: "test/set/or_set_test.gleam"
      to: "src/lattice/or_set.gleam"
      via: "import and function calls"
      pattern: "import lattice/or_set"
---

<objective>
Implement OR-Set (Observed-Remove Set) CRDT with add-wins semantics using unique per-add tags. This is the most complex set type — concurrent add and remove operations resolve in favor of add.

Purpose: Deliver the OR-Set CRDT, the most sophisticated set type in the library
Output: Working OR-Set module with passing unit tests covering add-wins semantics
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

# Key gleam/set and gleam/dict API:
#   dict.new() -> Dict(k, v)
#   dict.insert(dict, key, value) -> Dict(k, v)
#   dict.get(dict, key) -> Result(v, Nil)
#   dict.delete(dict, key) -> Dict(k, v)
#   dict.keys(dict) -> List(k)
#   dict.fold(dict, acc, fn(acc, k, v) -> acc) -> acc
#   set.new() -> Set(a)
#   set.insert(set, element) -> Set(a)
#   set.union(a, b) -> Set(a)
#   set.is_empty(set) -> Bool
#   set.from_list(list) -> Set(a)

# Phase 1 patterns:
# - list.unique(list.append(dict.keys(a), dict.keys(b))) for all-keys union
# - result.unwrap(dict.get(...), default) for safe access
# - Recursive helper functions for merge iteration

# Research key insight: Tag = #(String, Int) tuple (replica_id, counter)
# Each add() generates a unique tag. remove() clears all tags for that element.
# merge() unions tag sets. Concurrent add wins because the new tag from the
# concurrent add is not in the removing replica's knowledge.
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: TDD - OR-Set (SET-12 to SET-17)</name>
  <files>src/lattice/or_set.gleam, test/set/or_set_test.gleam</files>
  <behavior>
    - Test: new("A") creates empty set; contains("x") returns False; value() returns empty set
    - Test: add(new("A"), "hello") then contains("hello") returns True
    - Test: add then value() returns set containing the element
    - Test: add then remove then contains returns False
    - Test: Re-add after remove: add("x"), remove("x"), add("x") — contains("x") returns True
      (This is the key difference from 2P-Set: OR-Set allows re-add because the second add
       generates a NEW tag that was not removed)
    - Test: Multiple adds accumulate: add("a"), add("b") — value contains both
    - Test: Concurrent add-wins scenario:
      - replica_a = add(new("A"), "x")
      - replica_b = merge(new("B"), replica_a) — B sees x
      - replica_b = remove(replica_b, "x") — B removes x (clears A's tag for x)
      - replica_a = add(replica_a, "x") — A adds x again concurrently (new tag!)
      - merged = merge(replica_a, replica_b)
      - contains(merged, "x") returns True (A's new tag survived B's remove)
    - Test: merge(empty, set) — merged contains same elements as set
    - Test: merge(a, b) == merge(b, a) on value (commutativity on observable state)
    - Test: Merge propagates counter: after merge, new add generates unique tag
      (counter = max of both sides, so no tag collision)
  </behavior>
  <action>
Create test/set/ directory (if not already created by Plan 02) and or_set_test.gleam with the tests above.

Implement src/lattice/or_set.gleam:

Define the Tag type as a tuple:
```gleam
pub type Tag =
  #(String, Int)
```

Define the OR-Set record:
```gleam
pub type ORSet(a) {
  ORSet(
    replica_id: String,
    entries: dict.Dict(a, set.Set(Tag)),
    counter: Int,
  )
}
```

Import `gleam/dict`, `gleam/set`, `gleam/list`, `gleam/result`.

Implement these functions:

- `new(replica_id: String) -> ORSet(a)` — `ORSet(replica_id: replica_id, entries: dict.new(), counter: 0)`

- `add(orset: ORSet(a), element: a) -> ORSet(a)` —
  1. Increment counter: `new_counter = orset.counter + 1`
  2. Create unique tag: `tag = #(orset.replica_id, new_counter)`
  3. Get existing tags for this element (or empty set if not present):
     `existing = case dict.get(orset.entries, element) { Ok(t) -> t Error(Nil) -> set.new() }`
  4. Add new tag: `new_tags = set.insert(existing, tag)`
  5. Update entries: `dict.insert(orset.entries, element, new_tags)`
  6. Return ORSet with updated entries and new_counter

- `remove(orset: ORSet(a), element: a) -> ORSet(a)` —
  Delete the element's entire entry from the dict: `dict.delete(orset.entries, element)`.
  This removes ALL observed tags for this element. Tags on other replicas that we haven't
  seen yet are NOT affected (they'll appear in merge).
  Counter stays unchanged.

- `contains(orset: ORSet(a), element: a) -> Bool` —
  Check if element exists in entries with a non-empty tag set:
  ```gleam
  case dict.get(orset.entries, element) {
    Ok(tags) -> !set.is_empty(tags)
    Error(Nil) -> False
  }
  ```
  Note: In Gleam, use `bool.negate(set.is_empty(tags))` or pattern match instead of `!`.

- `value(orset: ORSet(a)) -> set.Set(a)` —
  Get all keys from entries dict that have non-empty tag sets:
  ```gleam
  dict.fold(orset.entries, set.new(), fn(acc, key, tags) {
    case set.is_empty(tags) {
      True -> acc
      False -> set.insert(acc, key)
    }
  })
  ```

- `merge(a: ORSet(el), b: ORSet(el)) -> ORSet(el)` —
  1. Get all unique element keys from both entries dicts:
     `all_keys = list.unique(list.append(dict.keys(a.entries), dict.keys(b.entries)))`
  2. For each element, UNION the tag sets from both sides:
     ```
     tags_a = dict.get(a.entries, key) |> result.unwrap(set.new())
     tags_b = dict.get(b.entries, key) |> result.unwrap(set.new())
     merged_tags = set.union(tags_a, tags_b)
     ```
  3. Only include elements with non-empty merged tag sets in result
  4. Set counter = max(a.counter, b.counter) — CRITICAL for tag uniqueness after merge
  5. Use a.replica_id for the merged set's replica_id
  6. Build merged entries using `list.fold` over all_keys (or recursive helper matching Phase 1 pattern)

  This produces ADD-WINS semantics because:
  - When replica A adds element "x" (creating tag T1), and replica B removes "x" (deleting T1 from B's view), a concurrent add by A creates T2.
  - B's remove only cleared T1 from B's entries. T2 (from A's concurrent add) is still in A's entries.
  - merge() unions tags: T2 from A survives in the merged set. Element "x" has non-empty tags → it's present.

PITFALL: Gleam does not have a `!` boolean negation operator. Use `case ... { True -> False False -> True }` or import `gleam/bool` if it provides a negate function. Check what pattern the codebase uses — Phase 1 used direct `case` pattern matching.

PITFALL: After merge, ensure empty tag sets result in the element being removed from the entries dict entirely (or at least handled correctly in contains/value). The fold-based merge naturally handles this by only inserting elements with non-empty tag sets.
  </action>
  <verify>
    <automated>gleam test</automated>
  </verify>
  <done>OR-Set: new creates empty set; add generates unique tag and inserts element; remove clears all observed tags; re-add after remove works (new tag); concurrent add wins after merge; value returns elements with tags; merge unions tag sets and propagates counter; all tests pass including add-wins scenario</done>
</task>

</tasks>

<verification>
Run `gleam test` - all OR-Set tests pass
Run `gleam check` - no type errors
</verification>

<success_criteria>
- OR-Set: new, add, remove, contains, value, merge all work correctly
- OR-Set allows re-add after remove (new tag generated)
- OR-Set concurrent add wins after merge (add-wins semantics verified)
- OR-Set merge unions tag sets per element
- OR-Set counter propagated via max after merge
- All unit tests pass
- Type checking passes
</success_criteria>

<output>
After completion, create `.planning/phases/02-registers-sets/02-registers-sets-03-SUMMARY.md`
</output>
