---
phase: 06-docs-api-polish
plan: 02
type: execute
wave: 1
depends_on: []
files_modified:
  - src/lattice/g_set.gleam
  - src/lattice/two_p_set.gleam
  - src/lattice/or_set.gleam
  - src/lattice/lww_map.gleam
  - src/lattice/or_map.gleam
  - src/lattice/crdt.gleam
autonomous: true
requirements:
  - DOCS-01
  - DOCS-02
  - DOCS-03
  - API-01
  - API-02
  - API-03

must_haves:
  truths:
    - "Every public function in g_set, two_p_set, or_set, lww_map, or_map, and crdt has a /// doc comment describing behavior, parameters, and return semantics"
    - "Every public type in those 6 modules has a /// doc comment"
    - "Each of the 6 modules has a //// module-level documentation block at the top with description and usage example"
    - "or_set.Tag type is pub opaque (users never construct Tags directly)"
    - "Function ordering within each module is consistent: new, mutators (add/set/update/remove), queries (contains/get/value/keys/values), merge, to_json, from_json"
    - "crdt.gleam module-level docs explain the tagged union and when to use it vs individual modules"
    - "CrdtSpec type has a doc comment explaining its role in OR-Map"
    - "All existing tests still pass after changes (gleam test)"
  artifacts:
    - path: "src/lattice/g_set.gleam"
      provides: "Documented G-Set module"
    - path: "src/lattice/two_p_set.gleam"
      provides: "Documented Two-Phase Set module"
    - path: "src/lattice/or_set.gleam"
      provides: "Documented + opaque-Tag OR-Set module"
    - path: "src/lattice/lww_map.gleam"
      provides: "Documented LWW-Map module"
    - path: "src/lattice/or_map.gleam"
      provides: "Documented OR-Map module"
    - path: "src/lattice/crdt.gleam"
      provides: "Documented CRDT union module"
  key_links: []
---

<objective>
Add module-level documentation, improve function doc comments, make types opaque where appropriate, and ensure consistent function ordering for the set, map, and CRDT union modules.

Purpose: These 6 modules cover collections and the top-level dispatch layer. This plan covers DOCS-01 (function docs), DOCS-02 (type docs), DOCS-03 (module docs with examples), API-01 (consistent signatures), API-02 (opaque types), and API-03 (convenience function gaps) for g_set, two_p_set, or_set, lww_map, or_map, and crdt.

Output: All 6 modules fully documented with module-level docs, improved function docs, opaque types where appropriate, and consistent ordering.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@src/lattice/g_set.gleam
@src/lattice/two_p_set.gleam
@src/lattice/or_set.gleam
@src/lattice/lww_map.gleam
@src/lattice/or_map.gleam
@src/lattice/crdt.gleam
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Document and polish set modules (g_set, two_p_set, or_set)</name>
  <files>src/lattice/g_set.gleam, src/lattice/two_p_set.gleam, src/lattice/or_set.gleam</files>
  <behavior>
    - Each module starts with a //// module-level doc block with description and usage example
    - All /// doc comments are enhanced with parameter/return descriptions
    - or_set.Tag becomes pub opaque (users never construct Tags)
    - Function order is consistent: new, add, remove (if applicable), contains, value, merge, to_json, from_json
    - All tests still pass
  </behavior>
  <action>
**Step 1: Add module docs to g_set**

Add at the top of `src/lattice/g_set.gleam`:

```gleam
//// A grow-only set (G-Set) CRDT.
////
//// Elements can be added but never removed. Merge is set union, so any element
//// added on any replica will eventually appear in all replicas. This is the
//// simplest set CRDT — use `TwoPSet` or `ORSet` if you need removal.
////
//// ## Example
////
//// ```gleam
//// import lattice/g_set
////
//// let a = g_set.new() |> g_set.add("alice")
//// let b = g_set.new() |> g_set.add("bob")
//// let merged = g_set.merge(a, b)
//// g_set.contains(merged, "alice")  // -> True
//// g_set.contains(merged, "bob")    // -> True
//// ```
```

Enhance doc comments. Ensure function order: new, add, contains, value, merge, to_json, from_json. Current order already matches.

**Step 2: Add module docs to two_p_set**

Add at the top of `src/lattice/two_p_set.gleam`:

```gleam
//// A two-phase set (2P-Set) CRDT.
////
//// Supports both add and remove, but an element can only be removed once. Once
//// removed (tombstoned), an element can never be re-added. Internally tracks
//// two sets: `added` and `removed`. An element is active if it is in `added`
//// but not in `removed`. Use `ORSet` if you need re-add after remove.
////
//// ## Example
////
//// ```gleam
//// import lattice/two_p_set
////
//// let set = two_p_set.new()
////   |> two_p_set.add("alice")
////   |> two_p_set.add("bob")
////   |> two_p_set.remove("bob")
//// two_p_set.contains(set, "alice")  // -> True
//// two_p_set.contains(set, "bob")    // -> False (tombstoned)
//// ```
```

Enhance doc comments. Function order: new, add, remove, contains, value, merge, to_json, from_json. Current order already matches.

**Step 3: Add module docs to or_set and make Tag opaque**

Add at the top of `src/lattice/or_set.gleam`:

```gleam
//// An observed-remove set (OR-Set) CRDT.
////
//// The most flexible set CRDT: supports add, remove, and re-add. Each add
//// creates a unique tag. Remove only deletes tags observed locally, so a
//// concurrent add on another replica survives (add-wins semantics). This makes
//// OR-Set suitable for collaborative data where elements may be toggled.
////
//// ## Example
////
//// ```gleam
//// import lattice/or_set
////
//// let a = or_set.new("node-a") |> or_set.add("item")
//// let b = or_set.new("node-b") |> or_set.add("item") |> or_set.remove("item")
//// let merged = or_set.merge(a, b)
//// or_set.contains(merged, "item")  // -> True (concurrent add wins)
//// ```
```

Make `Tag` opaque: change `pub type Tag` to `pub opaque type Tag`. Check first whether any code outside or_set.gleam constructs `Tag(...)` directly:

```bash
rg "or_set\.Tag\(" src/ test/
rg "or_set.*Tag\(" test/
```

If Tag is only constructed inside or_set.gleam, make it opaque. The Tag type exists so that tags can be stored in sets and compared -- users should not need to construct them.

Reorder functions to: new, add, remove, contains, value, merge, to_json, from_json. Currently to_json/from_json are near the top -- move them to the end after merge.

**Step 4: Run tests**

```bash
gleam test
```

All tests must pass.
  </action>
  <verify>
    <automated>gleam test 2>&1 | tail -5</automated>
    <automated>head -10 src/lattice/g_set.gleam | grep "////"</automated>
    <automated>head -10 src/lattice/two_p_set.gleam | grep "////"</automated>
    <automated>head -10 src/lattice/or_set.gleam | grep "////"</automated>
  </verify>
  <done>
    - g_set.gleam has //// module-level docs with usage example
    - two_p_set.gleam has //// module-level docs with usage example
    - or_set.gleam has //// module-level docs with usage example
    - or_set.Tag opaqueness decision made and applied
    - Function ordering is consistent across all 3 set modules
    - All tests pass
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Document and polish map modules (lww_map, or_map)</name>
  <files>src/lattice/lww_map.gleam, src/lattice/or_map.gleam</files>
  <behavior>
    - Each module starts with a //// module-level doc block with description and usage example
    - All /// doc comments are enhanced with parameter/return descriptions
    - Function order: new, set/update, get, remove, keys, values, merge, to_json, from_json
    - All tests still pass
  </behavior>
  <action>
**Step 1: Add module docs to lww_map**

Add at the top of `src/lattice/lww_map.gleam`:

```gleam
//// A last-writer-wins map (LWW-Map) CRDT.
////
//// Each key maps to a value and a timestamp. On conflict, the entry with the
//// higher timestamp wins. Removal is timestamp-based (tombstone): a remove at
//// timestamp T beats any set at timestamp < T. Keys are strings; values are
//// strings.
////
//// ## Example
////
//// ```gleam
//// import lattice/lww_map
////
//// let a = lww_map.new() |> lww_map.set("name", "Alice", 1)
//// let b = lww_map.new() |> lww_map.set("name", "Bob", 2)
//// let merged = lww_map.merge(a, b)
//// lww_map.get(merged, "name")  // -> Ok("Bob")
//// ```
```

Enhance doc comments. Function order is already: new, set, get, remove, keys, values, to_json, from_json, merge. Move `merge` to after `values` (before to_json): new, set, get, remove, keys, values, merge, to_json, from_json.

**Step 2: Add module docs to or_map**

Add at the top of `src/lattice/or_map.gleam`:

```gleam
//// An observed-remove map (OR-Map) CRDT.
////
//// Keys are tracked using an OR-Set with add-wins semantics: concurrent update
//// and remove of the same key resolves in favor of the update. Each value is
//// itself a CRDT (specified by `CrdtSpec` at construction), enabling nested
//// convergent data structures.
////
//// ## Example
////
//// ```gleam
//// import lattice/crdt
//// import lattice/g_counter
//// import lattice/or_map
////
//// let map = or_map.new("node-a", crdt.GCounterSpec)
////   |> or_map.update("score", fn(c) {
////     let assert crdt.CrdtGCounter(gc) = c
////     crdt.CrdtGCounter(g_counter.increment(gc, 10))
////   })
//// ```
```

Enhance doc comments. Reorder functions to: new, update, get, remove, keys, values, merge, to_json, from_json. Currently to_json/from_json are near the top -- move them to the end.

**Step 3: Run tests**

```bash
gleam test
```

All tests must pass.
  </action>
  <verify>
    <automated>gleam test 2>&1 | tail -5</automated>
    <automated>head -10 src/lattice/lww_map.gleam | grep "////"</automated>
    <automated>head -10 src/lattice/or_map.gleam | grep "////"</automated>
  </verify>
  <done>
    - lww_map.gleam has //// module-level docs with usage example
    - or_map.gleam has //// module-level docs with usage example
    - All /// function doc comments describe behavior and parameters
    - Function ordering is consistent (new, mutators, queries, merge, serialization)
    - All tests pass
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: Document CRDT union module and review for API-03 convenience gaps</name>
  <files>src/lattice/crdt.gleam</files>
  <behavior>
    - crdt.gleam starts with a //// module-level doc block explaining the tagged union, when to use it, and a usage example
    - All /// doc comments are enhanced
    - CrdtSpec type has a thorough doc comment
    - API-03 review: check if any obvious convenience functions are missing across the entire library (e.g., `size` for sets, `is_empty` for collections)
    - If convenience gaps are found, document them as a note in the summary but do NOT implement them in this plan (scope control -- new functions need tests)
    - All tests still pass
  </behavior>
  <action>
**Step 1: Add module docs to crdt.gleam**

Add at the top of `src/lattice/crdt.gleam`:

```gleam
//// A tagged union over all leaf CRDT types with dynamic dispatch.
////
//// The `Crdt` type wraps individual CRDTs (counters, registers, sets) so they
//// can be stored and merged uniformly — this is how `ORMap` holds heterogeneous
//// values. For direct use, prefer the individual modules (e.g., `g_counter`,
//// `or_set`) for type-safe access.
////
//// Maps (`LWWMap`, `ORMap`) are **not** included in this union to avoid circular
//// module dependencies.
////
//// ## Example
////
//// ```gleam
//// import lattice/crdt
//// import lattice/g_counter
////
//// let a = crdt.CrdtGCounter(g_counter.new("node-a") |> g_counter.increment(1))
//// let b = crdt.CrdtGCounter(g_counter.new("node-b") |> g_counter.increment(2))
//// let merged = crdt.merge(a, b)
//// ```
```

**Step 2: Enhance doc comments**

- `Crdt` type: Explain it's a tagged union, list the variants briefly
- `CrdtSpec` type: Explain it specifies the value type for OR-Map key creation
- `default_crdt`: Document what defaults are used for each spec (e.g., LWW-Register defaults to empty string at timestamp 0)
- `merge`: Document type mismatch behavior (returns first argument unchanged)
- `to_json`/`from_json`: Document the type-tag-based dispatch

**Step 3: API-03 review — identify convenience gaps**

Review the entire API surface for missing convenience functions. Check common patterns:

1. **Sets**: Do g_set, two_p_set, or_set have `size` or `is_empty`? (Answer: No — these could be useful)
2. **Counters**: Is there a `reset` or `is_zero` function? (Not standard for CRDTs — skip)
3. **Maps**: Do lww_map, or_map have `size` or `is_empty`? (No — could be useful)
4. **Registers**: Any missing? `value` exists, that's the main query.
5. **Version Vector**: `dominates(a, b) -> Bool` could be nice (check if compare returns Before/Equal). Already has `compare`, so this is sugar.
6. **General**: `to_json_string` convenience (to_json returns json.Json, users must call json.to_string separately). This is idiomatic Gleam — skip.

Document findings in the summary. Do NOT add new functions in this plan — new functions need corresponding tests which is out of scope for a docs/polish plan. Note the gaps for potential future work.

**Step 4: Run tests**

```bash
gleam test
```

All tests must pass.
  </action>
  <verify>
    <automated>gleam test 2>&1 | tail -5</automated>
    <automated>head -10 src/lattice/crdt.gleam | grep "////"</automated>
  </verify>
  <done>
    - crdt.gleam has //// module-level docs explaining the union type and when to use it
    - CrdtSpec has thorough doc comment
    - All /// function doc comments describe behavior
    - API-03 convenience gaps identified and documented in summary
    - All tests pass
  </done>
</task>

</tasks>

<verification>
1. `gleam test` -- all 228+ tests pass after all changes
2. `head -1 src/lattice/g_set.gleam src/lattice/two_p_set.gleam src/lattice/or_set.gleam src/lattice/lww_map.gleam src/lattice/or_map.gleam src/lattice/crdt.gleam` -- all start with ////
3. `gleam format --check src test` -- code is formatted correctly
4. `gleam build --warnings-as-errors` -- no warnings
</verification>

<success_criteria>
- DOCS-01 (partial): All public functions in remaining 6 modules have quality /// doc comments
- DOCS-02 (partial): All public types in remaining 6 modules have quality /// doc comments
- DOCS-03 (partial): Remaining 6 of 12 modules have //// module-level docs with usage examples
- API-01 (partial): Function ordering and naming consistent across remaining 6 modules
- API-02 (partial): or_set.Tag opaqueness evaluated and applied
- API-03: Convenience gaps identified and documented (no new functions added — those need tests)
</success_criteria>

<output>
After completion, create `.planning/phases/06-docs-api-polish/06-docs-api-polish-02-SUMMARY.md`
</output>
