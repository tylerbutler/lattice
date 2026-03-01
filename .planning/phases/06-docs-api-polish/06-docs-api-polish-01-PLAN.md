---
phase: 06-docs-api-polish
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/lattice/g_counter.gleam
  - src/lattice/pn_counter.gleam
  - src/lattice/lww_register.gleam
  - src/lattice/mv_register.gleam
  - src/lattice/version_vector.gleam
  - src/lattice/dot_context.gleam
autonomous: true
requirements:
  - DOCS-01
  - DOCS-02
  - DOCS-03
  - API-01
  - API-02

must_haves:
  truths:
    - "Every public function in g_counter, pn_counter, lww_register, mv_register, version_vector, and dot_context has a /// doc comment that describes behavior, parameters, and return semantics"
    - "Every public type in those 6 modules has a /// doc comment explaining the CRDT's purpose and semantics"
    - "Each of the 6 modules has a //// module-level documentation block at the top of the file with a brief description and a usage example"
    - "GCounter and PNCounter types remain pub (pn_counter cross-module destructuring prevents opaqueness); VersionVector and DotContext evaluated for opaqueness per Task 3 guidance"
    - "LWWRegister remains pub (value and timestamp fields are part of the API)"
    - "MVRegister is pub opaque (internal entries dict and vclock hidden; users access via value())"
    - "mv_register.Tag type is pub opaque (users don't construct Tags directly)"
    - "dot_context.Dot type remains pub (users pass Dot values to add_dot/remove_dots)"
    - "Function ordering within each module is consistent: new, mutators, queries, merge, to_json, from_json"
    - "All existing tests still pass after changes (gleam test)"
  artifacts:
    - path: "src/lattice/g_counter.gleam"
      provides: "Documented G-Counter module (non-opaque, cross-module access needed)"
    - path: "src/lattice/pn_counter.gleam"
      provides: "Documented PN-Counter module (non-opaque, exposes GCounter fields)"
    - path: "src/lattice/lww_register.gleam"
      provides: "Documented LWW-Register module"
    - path: "src/lattice/mv_register.gleam"
      provides: "Documented + opaque MV-Register module"
    - path: "src/lattice/version_vector.gleam"
      provides: "Documented + opaque Version Vector module"
    - path: "src/lattice/dot_context.gleam"
      provides: "Documented + opaque Dot Context module"
  key_links: []
---

<objective>
Add module-level documentation, improve function doc comments, make types opaque where appropriate, and ensure consistent function ordering for the counter, register, and clock modules.

Purpose: These 6 modules form the foundational layer of lattice. This plan covers DOCS-01 (function docs), DOCS-02 (type docs), DOCS-03 (module docs with examples), API-01 (consistent signatures), and API-02 (opaque types) for g_counter, pn_counter, lww_register, mv_register, version_vector, and dot_context.

Output: All 6 modules fully documented with module-level docs, improved function docs, opaque types, and consistent ordering.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@src/lattice/g_counter.gleam
@src/lattice/pn_counter.gleam
@src/lattice/lww_register.gleam
@src/lattice/mv_register.gleam
@src/lattice/version_vector.gleam
@src/lattice/dot_context.gleam
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Document and polish counter modules (g_counter, pn_counter)</name>
  <files>src/lattice/g_counter.gleam, src/lattice/pn_counter.gleam</files>
  <behavior>
    - Each module starts with a //// module-level doc block describing the CRDT, its semantics, and a usage example
    - All existing /// doc comments are enhanced to describe parameters, return values, and edge cases
    - GCounter and PNCounter types become `pub opaque type` (hides internal dict structure)
    - Function order is: new, increment (+ decrement for pn_counter), value, merge, to_json, from_json
    - All tests still pass
  </behavior>
  <action>
**Step 1: Make GCounter opaque and add module docs**

In `src/lattice/g_counter.gleam`:

1. Add module-level documentation at the very top of the file (before imports):

```gleam
//// A grow-only counter (G-Counter) CRDT.
////
//// Each replica maintains its own monotonically increasing count. The global
//// value is the sum across all replicas. Merge takes the pairwise maximum
//// of each replica's count, guaranteeing convergence.
////
//// ## Example
////
//// ```gleam
//// import lattice/g_counter
////
//// let a = g_counter.new("node-a") |> g_counter.increment(3)
//// let b = g_counter.new("node-b") |> g_counter.increment(5)
//// let merged = g_counter.merge(a, b)
//// g_counter.value(merged)  // -> 8
//// ```
```

2. Change `pub type GCounter` to `pub opaque type GCounter`. This hides the internal `dict` and `self_id` fields from consumers.

3. Enhance existing doc comments:
   - `new`: Add `/// Returns a fresh counter with zero counts.`
   - `increment`: Document that `delta` should be non-negative and clarify the current behavior for negative deltas
   - `value`: Mention it returns the sum across all replicas
   - `merge`: Note commutativity, associativity, and idempotency guarantees
   - `to_json`/`from_json`: Keep existing docs (they already describe the format)

4. Ensure function order is: new, increment, value, merge, to_json, from_json (move helpers to end). Current order is already correct.

**Step 2: Fix compilation after making GCounter opaque**

Making GCounter opaque means `pn_counter.gleam` can no longer pattern-match on `GCounter(dict, self_id)` in `to_json` and `from_json`. The pn_counter serialization directly accesses g_counter internal fields.

To fix this, add two **internal** helper functions to g_counter (NOT public -- prefix with no `pub`):
- No, wait -- pn_counter is in a different module, so it can't access non-pub functions.

**Alternative approach:** Keep GCounter as `pub type` (not opaque) for v1.0 since pn_counter's serialization directly destructures it. Making it opaque would require adding accessor functions or restructuring serialization. This is a v1.1 polish release -- do not break the internal architecture.

**REVISED: Do NOT make GCounter opaque.** The pn_counter module's to_json/from_json directly destructures GCounter internals. Making it opaque would require adding public accessor functions for `dict` and `self_id`, which would be worse API design than the current state. Document the type as-is. The same applies to PNCounter (it exposes `positive` and `negative` G-Counters which is fine since that's the semantic model).

Similarly, review each type individually before making opaque -- only make opaque if no other module destructures it.

**Step 3: Make PNCounter module docs and polish**

In `src/lattice/pn_counter.gleam`:

1. Add module-level documentation at the top:

```gleam
//// A positive-negative counter (PN-Counter) CRDT.
////
//// Supports both increment and decrement operations by pairing two G-Counters:
//// one tracking increments and one tracking decrements. The value is the
//// difference between the two. Merge delegates to G-Counter merge on each half.
////
//// ## Example
////
//// ```gleam
//// import lattice/pn_counter
////
//// let counter = pn_counter.new("node-a")
////   |> pn_counter.increment(10)
////   |> pn_counter.decrement(3)
//// pn_counter.value(counter)  // -> 7
//// ```
```

2. Enhance existing doc comments with parameter descriptions and semantics.

3. Verify function order: new, increment, decrement, value, to_json, from_json, merge. Move merge to after value (before to_json) for consistency: new, increment, decrement, value, merge, to_json, from_json.

**Step 4: Run tests**

```bash
gleam test
```

All 228+ tests must still pass.
  </action>
  <verify>
    <automated>gleam test 2>&1 | tail -5</automated>
    <automated>head -15 src/lattice/g_counter.gleam | grep "////"</automated>
    <automated>head -15 src/lattice/pn_counter.gleam | grep "////"</automated>
  </verify>
  <done>
    - g_counter.gleam has //// module-level docs with usage example
    - pn_counter.gleam has //// module-level docs with usage example
    - All /// function doc comments are descriptive
    - Function ordering is consistent (new, mutators, queries, merge, to_json, from_json)
    - All tests pass
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Document and polish register modules (lww_register, mv_register)</name>
  <files>src/lattice/lww_register.gleam, src/lattice/mv_register.gleam</files>
  <behavior>
    - Each module starts with a //// module-level doc block with description and usage example
    - All /// doc comments are enhanced
    - mv_register: Tag type becomes pub opaque (users should not construct Tags directly)
    - Function order is consistent: new, set, value, merge, to_json, from_json
    - All tests still pass
  </behavior>
  <action>
**Step 1: Add module docs to lww_register**

Add at the top of `src/lattice/lww_register.gleam`:

```gleam
//// A last-writer-wins register (LWW-Register) CRDT.
////
//// Stores a single value with an associated timestamp. When two replicas
//// conflict, the value with the strictly higher timestamp wins. On equal
//// timestamps, the second argument to `merge` wins (consistent tiebreak).
////
//// ## Example
////
//// ```gleam
//// import lattice/lww_register
////
//// let a = lww_register.new("hello", 1)
//// let b = lww_register.new("world", 2)
//// let merged = lww_register.merge(a, b)
//// lww_register.value(merged)  // -> "world"
//// ```
```

Enhance doc comments to describe tiebreak behavior for `set` and `merge`.

**Step 2: Add module docs to mv_register and make Tag opaque**

Add at the top of `src/lattice/mv_register.gleam`:

```gleam
//// A multi-value register (MV-Register) CRDT.
////
//// Preserves all concurrently written values using causal history tracked by
//// version vectors. When one write causally supersedes another, only the newer
//// value survives. When writes are concurrent, all values are retained — the
//// application decides how to resolve the conflict.
////
//// ## Example
////
//// ```gleam
//// import lattice/mv_register
////
//// let a = mv_register.new("node-a") |> mv_register.set("hello")
//// let b = mv_register.new("node-b") |> mv_register.set("world")
//// let merged = mv_register.merge(a, b)
//// mv_register.value(merged)  // -> ["hello", "world"] (concurrent writes)
//// ```
```

Make `Tag` opaque: change `pub type Tag` to `pub opaque type Tag`. Tags are internal identifiers for write operations -- users never need to construct them. Check whether any test or external module destructures Tag. If tests do `Tag(...)` construction, they will need to be updated or Tag should remain public. Investigate before changing.

Check: `rg "mv_register.*Tag\(" test/` and `rg "Tag\(" src/lattice/mv_register` to see if Tag is constructed outside the module.

If Tag is only constructed inside mv_register.gleam itself, make it opaque. If tests construct Tags directly, leave it public and document it.

Reorder functions to: new, set, value, merge, to_json, from_json (currently to_json/from_json are at the top -- move them to the end).

**Step 3: Run tests**

```bash
gleam test
```

All tests must pass.
  </action>
  <verify>
    <automated>gleam test 2>&1 | tail -5</automated>
    <automated>head -15 src/lattice/lww_register.gleam | grep "////"</automated>
    <automated>head -15 src/lattice/mv_register.gleam | grep "////"</automated>
  </verify>
  <done>
    - lww_register.gleam has //// module-level docs with usage example
    - mv_register.gleam has //// module-level docs with usage example
    - Tag type opaqueness decision made and documented
    - All /// function doc comments describe behavior and parameters
    - Function ordering is consistent
    - All tests pass
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: Document and polish clock modules (version_vector, dot_context)</name>
  <files>src/lattice/version_vector.gleam, src/lattice/dot_context.gleam</files>
  <behavior>
    - Each module starts with a //// module-level doc block with description and usage example
    - All /// doc comments are enhanced
    - VersionVector: evaluate opaque type (check if other modules destructure it)
    - DotContext: evaluate opaque type
    - Function order is consistent
    - All tests still pass
  </behavior>
  <action>
**Step 1: Add module docs to version_vector**

Add at the top of `src/lattice/version_vector.gleam`:

```gleam
//// A version vector for tracking causal ordering between replicas.
////
//// Each replica has a logical clock (monotonically increasing integer). Version
//// vectors enable detecting whether two states are causally ordered (one happened
//// before the other) or concurrent (neither dominates). Merge takes the pairwise
//// maximum of all clocks.
////
//// ## Example
////
//// ```gleam
//// import lattice/version_vector
////
//// let a = version_vector.new()
////   |> version_vector.increment("node-a")
////   |> version_vector.increment("node-a")
//// let b = version_vector.new()
////   |> version_vector.increment("node-b")
//// version_vector.compare(a, b)  // -> Concurrent
//// ```
```

Check if VersionVector is destructured outside its own module: `rg "VersionVector\(dict:" src/lattice/` and `rg "VersionVector\(" src/lattice/ test/`. If mv_register.gleam or other modules construct VersionVector directly (e.g., in from_json), then it cannot be made opaque without adding a constructor function. The mv_register.gleam from_json does `version_vector.VersionVector(dict: vclock_dict)` -- so VersionVector cannot be opaque unless we add a `from_dict` constructor. For v1.1 polish: add a `pub fn from_dict(d: dict.Dict(String, Int)) -> VersionVector` function and make the type opaque, OR leave it non-opaque and document it.

**Decision guidance**: If adding `from_dict` is simple and clean, do it and make opaque. If it feels forced, leave non-opaque. The executor should check and decide.

**Step 2: Add module docs to dot_context**

Add at the top of `src/lattice/dot_context.gleam`:

```gleam
//// A dot context tracks observed events (dots) across replicas.
////
//// A "dot" is a pair of (replica_id, counter) uniquely identifying a single
//// write event. The dot context is used by causal CRDTs like MV-Register and
//// OR-Set to determine which operations have been observed.
////
//// ## Example
////
//// ```gleam
//// import lattice/dot_context.{Dot}
////
//// let ctx = dot_context.new()
////   |> dot_context.add_dot("node-a", 1)
////   |> dot_context.add_dot("node-b", 1)
//// dot_context.contains_dots(ctx, [Dot("node-a", 1)])  // -> True
//// ```
```

Check if DotContext is destructured outside its module. If only used via its API functions, consider making it opaque. Dot should remain public since users construct Dot values for `contains_dots` and `remove_dots`.

Enhance doc comments for all functions.

**Step 3: Enhance doc comments for Order type**

The `Order` type in version_vector.gleam has variants `Before`, `After`, `Concurrent`, `Equal`. Add a doc comment for the type explaining what each variant means:

```gleam
/// The causal ordering between two version vectors.
///
/// - `Before`: the first vector happened before the second
/// - `After`: the first vector happened after the second
/// - `Concurrent`: neither dominates — the states diverged
/// - `Equal`: the vectors are identical
```

**Step 4: Run tests**

```bash
gleam test
```

All tests must pass.
  </action>
  <verify>
    <automated>gleam test 2>&1 | tail -5</automated>
    <automated>head -15 src/lattice/version_vector.gleam | grep "////"</automated>
    <automated>head -15 src/lattice/dot_context.gleam | grep "////"</automated>
  </verify>
  <done>
    - version_vector.gleam has //// module-level docs with usage example
    - dot_context.gleam has //// module-level docs with usage example
    - Order type has enhanced doc comment explaining variants
    - Opaqueness decisions made and applied (or documented as intentionally non-opaque)
    - All /// function doc comments describe behavior and parameters
    - All tests pass
  </done>
</task>

</tasks>

<verification>
1. `gleam test` -- all 228+ tests pass after all changes
2. `head -1 src/lattice/g_counter.gleam src/lattice/pn_counter.gleam src/lattice/lww_register.gleam src/lattice/mv_register.gleam src/lattice/version_vector.gleam src/lattice/dot_context.gleam` -- all start with ////
3. `gleam format --check src test` -- code is formatted correctly
4. `gleam build --warnings-as-errors` -- no warnings
</verification>

<success_criteria>
- DOCS-01 (partial): All public functions in 6 modules have quality /// doc comments
- DOCS-02 (partial): All public types in 6 modules have quality /// doc comments
- DOCS-03 (partial): 6 of 12 modules have //// module-level docs with usage examples
- API-01 (partial): Function ordering and naming consistent across 6 modules
- API-02 (partial): Opaque types evaluated and applied where appropriate in 6 modules
</success_criteria>

<output>
After completion, create `.planning/phases/06-docs-api-polish/06-docs-api-polish-01-SUMMARY.md`
</output>
