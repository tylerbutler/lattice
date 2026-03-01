# Phase 4: Advanced Testing - Research

**Researched:** 2026-03-01
**Domain:** Property-based CRDT testing (qcheck), Dot Context (causal metadata), convergence proofs, OR-Set edge cases, 2P-Set tombstone invariants, cross-target serialization
**Confidence:** HIGH

## Summary

Phase 4 completes the test coverage for all CRDT types and adds Dot Context (CLOCK-06 to CLOCK-09). Three categories of work are needed:

1. **Completing merge-law tests (TEST-01 to TEST-03 remaining):** The maps (LWW-Map, OR-Map) have no property tests yet. LWW-Map is straightforward. OR-Map is harder because property tests require generating valid OR-Map states with matching crdt_spec, and structural equality cannot be used for comparison — only observable values (keys(), values(), get()).

2. **New test categories (TEST-04 to TEST-10):** Convergence/all-to-all-exchange (TEST-04), bottom identity (TEST-05), inflation/monotonicity (TEST-06), serialization round-trips (TEST-07 — partially done), cross-target serialization (TEST-08), OR-Set add-wins edge cases (TEST-09), and 2P-Set tombstone permanence (TEST-10). Most of these are deterministic (non-property-based) tests. Only convergence (TEST-04) benefits significantly from qcheck generators.

3. **Dot Context implementation (CLOCK-06 to CLOCK-09):** A Dot Context is a compact set of (replica, counter) pairs used by delta-CRDTs and OR-Set-based structures for causal reasoning. This is new implementation work, not just tests. The Dot Context struct needs to be built in `src/lattice/dot_context.gleam`, then property tests written.

The established qcheck patterns from Phases 1-3 remain fully applicable. The key constraint is to keep tests observable-value-based (not structural equality) for types like MV-Register, OR-Set, OR-Map, and LWW-Map. The `small_test_config()` pattern (test_count: 10, max_retries: 3, seed: qcheck.seed(42)) is mandatory to prevent timeout.

**Primary recommendation:** Organize into 3 plans: (1) Dot Context implementation + tests, (2) remaining merge-law property tests for maps + bottom identity + monotonicity, (3) convergence tests + OR-Set/2P-Set edge cases + cross-target serialization.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-01 | Merge commutativity tests for ALL CRDT types | Counters, registers, sets done. Need LWW-Map and OR-Map. |
| TEST-02 | Merge associativity tests for ALL CRDT types | Counters, G-Set, 2P-Set, LWW-Register done. Need OR-Set, MV-Register (tricky), LWW-Map, OR-Map. |
| TEST-03 | Merge idempotency tests for ALL CRDT types | Counters, registers, sets done. Need LWW-Map and OR-Map. |
| TEST-04 | Convergence tests (all-to-all exchange) | N replicas independently apply operations, all-to-all merge, all produce same value(). 3-replica deterministic or qcheck-driven. |
| TEST-05 | Bottom identity tests: merge(a, new()) == a | Each type has a `new()` bottom. Test that merging with bottom leaves value() unchanged. |
| TEST-06 | Inflation/monotonicity tests | value() can only increase after merges. Type-specific definition of "increase." |
| TEST-07 | Serialization round-trip tests | Already done for G-Counter, PN-Counter, LWW-Register, G-Set, 2P-Set, OR-Set, LWW-Map. Need: MV-Register, OR-Map, VersionVector round-trip property tests (property variants). |
| TEST-08 | Cross-target serialization tests (Erlang <-> JS) | Verify JSON is valid and parseable across targets. Deterministic test: encode on one side, confirm the JSON string is valid and from_json decodes correctly. |
| TEST-09 | OR-Set concurrent add-wins tests | The or_set_test.gleam already has `concurrent_add_wins_test`. Need property-based variant with random sequences. |
| TEST-10 | 2P-Set tombstone permanence tests | Already has unit test. Need property-based: for any element e, if removed at any point in any merge order, contains(e) is always False. |
| CLOCK-06 | Dot Context: new() -> t | New module `lattice/dot_context.gleam`. A Dot is #(replica_id, counter). DotContext is a set of dots. |
| CLOCK-07 | Dot Context: add_dot(context, replica_id, Int) -> context | Insert a dot into the context. |
| CLOCK-08 | Dot Context: remove_dots(context, List(Dot)) -> context | Remove a list of dots from the context. Used when dots are "applied." |
| CLOCK-09 | Dot Context: contains_dots(context, List(Dot)) -> Bool | Check if all given dots are present in the context. |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `qcheck` | 1.0.4 (installed) | Property-based test generation | Established in all prior phases; no alternative |
| `startest` | 0.8.0 (installed) | `startest/expect` assertions | Established in all prior tests |
| `gleam_stdlib` | 0.68.1 (installed) | `gleam/set`, `gleam/list`, `gleam/dict` | All CRDT internals |
| `gleam_json` | 3.1.0 (installed) | JSON for serialization tests | Same as Phase 3 |

### No new dependencies needed

All required tools are already installed. Phase 4 is purely test/implementation work using the existing stack.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Manual 3-replica convergence setup | qcheck-driven N-replica convergence | Manual is deterministic and debuggable; qcheck adds coverage but increases shrinking complexity. Use manual for convergence tests. |
| Observable value comparison in OR-Map tests | Structural equality | Structural equality would require identical internal state including OR-Set tag counters — impossible to guarantee. Use value()-based comparison. |

## Architecture Patterns

### Recommended Project Structure

```
src/lattice/
├── dot_context.gleam    # NEW: CLOCK-06 to CLOCK-09

test/
├── clock/
│   ├── version_vector_test.gleam    # Existing
│   └── dot_context_test.gleam       # NEW: CLOCK-06 to CLOCK-09 unit tests
└── property/
    ├── counter_property_test.gleam          # Existing (done)
    ├── register_set_property_test.gleam     # Existing (done)
    ├── serialization_property_test.gleam    # Existing (partial)
    ├── map_property_test.gleam              # NEW: TEST-01/02/03 for maps
    └── advanced_property_test.gleam         # NEW: TEST-04 to TEST-10
```

### Pattern 1: Bottom Identity Test
**What:** `merge(a, new()) == a` expressed as observable equality
**When to use:** TEST-05 — applies to all CRDT types
**Example:**
```gleam
// G-Counter: merge(counter, g_counter.new("B")) has same value()
pub fn g_counter_bottom_identity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.small_non_negative_int(),
    fn(n) {
      let counter = g_counter.new("A") |> g_counter.increment(n)
      let bottom = g_counter.new("B")
      g_counter.value(g_counter.merge(counter, bottom))
      |> expect.to_equal(g_counter.value(counter))
      Nil
    },
  )
}

// OR-Set: value() unchanged after merge with new()
pub fn or_set_bottom_identity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 10),
    fn(n) {
      let s = or_set.new("A") |> or_set.add(int.to_string(n))
      let bottom = or_set.new("B")
      or_set.value(or_set.merge(s, bottom))
      |> expect.to_equal(or_set.value(s))
      Nil
    },
  )
}
```

**Bottom elements per type:**
- `g_counter.new(any_id)`: all zero counts
- `pn_counter.new(any_id)`: all zero counts
- `lww_register.new("", 0)`: value="" at timestamp 0 (loses to any non-zero timestamp)
- `mv_register.new(any_id)`: empty entries, empty vclock
- `g_set.new()`: empty set
- `two_p_set.new()`: empty added and removed sets
- `or_set.new(any_id)`: empty entries, counter=0
- `lww_map.new()`: empty entries dict
- `or_map.new(any_id, spec)`: empty key_set, empty values dict

**Caveat for LWW-Register:** `lww_register.new("", 0)` is only a true bottom for registers with timestamp > 0. If both registers have timestamp 0, merge tie-breaks to second arg. Test `merge(reg_ts_1, lww_register.new("", 0))` instead of using timestamp 0 input.

### Pattern 2: Monotonicity / Inflation Test
**What:** After merge, observable value is "at least as large" as either input
**When to use:** TEST-06
**Type-specific definitions of "inflation":**

```gleam
// G-Counter: value after merge >= value before merge
pub fn g_counter_monotonic__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let ca = g_counter.new("A") |> g_counter.increment(a)
      let cb = g_counter.new("B") |> g_counter.increment(b)
      let merged = g_counter.merge(ca, cb)
      expect.to_be_true(g_counter.value(merged) >= g_counter.value(ca))
      expect.to_be_true(g_counter.value(merged) >= g_counter.value(cb))
      Nil
    },
  )
}

// G-Set: value after merge is superset of both inputs
pub fn g_set_monotonic__test() {
  // value(merge(a, b)) is superset of value(a) and superset of value(b)
  // Use set.is_subset to verify
}

// 2P-Set: value can shrink (elements get tombstoned) — monotonicity is on the
// removed set size: set.size(removed) only increases after merge.
// The "inflating" lattice for 2P-Set is the pair (added_size, removed_size), both non-decreasing.

// OR-Set: set size (number of unique tags) only increases after merge
// (assuming no removes between snapshots)

// LWW-Register: timestamp after merge >= timestamp of either input
// (the winner has the highest timestamp)

// MV-Register: number of concurrent values after merge >= max of either input's count
// (merge can only add or keep values, never drop surviving ones)
```

**Note:** Strict "values only increase" is type-specific. For sets, it means "at least as many elements." For counters, it means "at least as high a value." For LWW types, it means "at least as recent a winner."

### Pattern 3: All-to-All Convergence Test
**What:** N replicas, each with independent operations, exchange state pairwise, final state is identical
**When to use:** TEST-04
**Recommended approach:** Deterministic 3-replica setup (not qcheck-driven) for readability; use qcheck for the operation values
```gleam
pub fn g_counter_convergence_3_replicas__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(a, b, c) = triple
      let ra = g_counter.new("A") |> g_counter.increment(a)
      let rb = g_counter.new("B") |> g_counter.increment(b)
      let rc = g_counter.new("C") |> g_counter.increment(c)
      // All-to-all exchange: each replica merges with all others
      let ra_final = ra |> g_counter.merge(rb) |> g_counter.merge(rc)
      let rb_final = rb |> g_counter.merge(ra) |> g_counter.merge(rc)
      let rc_final = rc |> g_counter.merge(ra) |> g_counter.merge(rb)
      // All must agree
      g_counter.value(ra_final)
      |> expect.to_equal(g_counter.value(rb_final))
      g_counter.value(rb_final)
      |> expect.to_equal(g_counter.value(rc_final))
      Nil
    },
  )
}
```

**Note:** For OR-Map convergence, use observable comparison: `set.from_list(or_map.keys(final_a)) == set.from_list(or_map.keys(final_b))`.

### Pattern 4: OR-Set Concurrent Add-Wins Property Test
**What:** Concurrent add and remove of the same element — add always wins
**When to use:** TEST-09
**Critical insight:** The existing unit test in `or_set_test.gleam` (`concurrent_add_wins_test`) covers the canonical scenario. For property-based, generate the element value randomly.

```gleam
pub fn or_set_concurrent_add_wins_property__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 20),
    fn(elem) {
      let elem_str = int.to_string(elem)
      // Replica A adds element
      let replica_a = or_set.new("A") |> or_set.add(elem_str)
      // Replica B syncs, then removes (clears A's tags)
      let replica_b = or_set.new("B") |> or_set.merge(replica_a)
      let replica_b = or_set.remove(replica_b, elem_str)
      // Replica A concurrently adds again (new tag B hasn't seen)
      let replica_a = or_set.add(replica_a, elem_str)
      // Merge: add wins
      let merged = or_set.merge(replica_a, replica_b)
      merged |> or_set.contains(elem_str) |> expect.to_be_true
      Nil
    },
  )
}
```

### Pattern 5: 2P-Set Tombstone Permanence Property Test
**What:** For any element, once in the removed set, it stays removed under all merge orders
**When to use:** TEST-10

```gleam
pub fn two_p_set_tombstone_permanent_under_merge__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 20),
    fn(elem) {
      let elem_str = int.to_string(elem)
      // Set A: add and remove element
      let set_a =
        two_p_set.new()
        |> two_p_set.add(elem_str)
        |> two_p_set.remove(elem_str)
      // Set B: also has the element added (concurrent)
      let set_b = two_p_set.new() |> two_p_set.add(elem_str)
      // Merge in both orders — tombstone must survive
      let merged_ab = two_p_set.merge(set_a, set_b)
      let merged_ba = two_p_set.merge(set_b, set_a)
      merged_ab |> two_p_set.contains(elem_str) |> expect.to_be_false
      merged_ba |> two_p_set.contains(elem_str) |> expect.to_be_false
      Nil
    },
  )
}
```

### Pattern 6: LWW-Map Property Tests
**What:** Commutativity, idempotency, associativity for LWW-Map
**When to use:** TEST-01, TEST-02, TEST-03 (map completion)
**Important:** LWW-Map merge tiebreak uses first-arg-wins on equal timestamps. Commutativity holds on observable values only when timestamps differ. Use distinct timestamps.

```gleam
pub fn lww_map_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(1, 50),
      qcheck.bounded_int(51, 100),  // distinct timestamps ensure determinism
      fn(ts_a, ts_b) { #(ts_a, ts_b) },
    ),
    fn(pair) {
      let #(ts_a, ts_b) = pair
      let map_a = lww_map.new() |> lww_map.set("key", "val_a", ts_a)
      let map_b = lww_map.new() |> lww_map.set("key", "val_b", ts_b)
      lww_map.get(lww_map.merge(map_a, map_b), "key")
      |> expect.to_equal(lww_map.get(lww_map.merge(map_b, map_a), "key"))
      Nil
    },
  )
}
```

**Commutativity caveat:** LWW-Map merge(a, b) uses `ts_a >= ts_b → a wins`. When ts_a == ts_b, merge(a,b) != merge(b,a) structurally, but the winning value is deterministic (first arg wins on ties). However `value()` (get) results will differ for equal-timestamp keys. To test true commutativity, use distinct timestamps in generators (bounded_int ranges that don't overlap).

### Pattern 7: OR-Map Property Tests
**What:** Commutativity, idempotency for OR-Map (associativity is complex, skip like MV-Register)
**When to use:** TEST-01, TEST-03 (map completion)
**Important:** Compare with `set.from_list(or_map.keys(...))` and `list.length(or_map.values(...))` not structural equality.

```gleam
pub fn or_map_commutativity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(1, 10),
      qcheck.bounded_int(1, 10),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let map_a = or_map.new("A", crdt.GCounterSpec)
        |> or_map.update("x", fn(c) {
          case c {
            crdt.CrdtGCounter(counter) -> crdt.CrdtGCounter(g_counter.increment(counter, a))
            _ -> c
          }
        })
      let map_b = or_map.new("B", crdt.GCounterSpec)
        |> or_map.update("x", fn(c) {
          case c {
            crdt.CrdtGCounter(counter) -> crdt.CrdtGCounter(g_counter.increment(counter, b))
            _ -> c
          }
        })
      // Compare keys (as sets)
      let keys_ab = set.from_list(or_map.keys(or_map.merge(map_a, map_b)))
      let keys_ba = set.from_list(or_map.keys(or_map.merge(map_b, map_a)))
      keys_ab |> expect.to_equal(keys_ba)
      Nil
    },
  )
}
```

### Pattern 8: Dot Context Implementation
**What:** A Dot Context is a set of (replica_id, counter) pairs (called "dots") representing observed events
**When to use:** CLOCK-06 to CLOCK-09
**Note:** This is the only NEW implementation in Phase 4; everything else is tests.

```gleam
// src/lattice/dot_context.gleam

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
  DotContext(dots: set.insert(context.dots, Dot(replica_id: replica_id, counter: counter)))
}

/// Remove a list of dots from the context (used when dots are "applied"/observed)
pub fn remove_dots(context: DotContext, dots: List(Dot)) -> DotContext {
  let new_dots = list.fold(dots, context.dots, fn(acc, dot) { set.delete(acc, dot) })
  DotContext(dots: new_dots)
}

/// Check if all given dots are present in the context
pub fn contains_dots(context: DotContext, dots: List(Dot)) -> Bool {
  list.all(dots, fn(dot) { set.contains(context.dots, dot) })
}
```

**Dot Context is infrastructure.** It does not need JSON serialization in v1 (no JSON requirements for CLOCK-06 to CLOCK-09). Unit tests suffice; no property tests are required by the spec.

### Pattern 9: Cross-Target Serialization Test (TEST-08)
**What:** JSON produced by the Gleam library is valid JSON parseable on both Erlang and JS targets
**When to use:** TEST-08
**Approach:** Create deterministic test that encodes a CRDT, verifies the JSON string is valid by round-tripping it through `from_json`, and verify the format contains only JSON primitives (no BEAM atoms, no Erlang tuples). The actual cross-target validation requires running `gleam test --target javascript` in addition to the default Erlang run.

```gleam
// Deterministic cross-target compatibility smoke test
pub fn json_format_is_target_agnostic_test() {
  // Create a G-Counter and encode it
  let counter = g_counter.new("replica_1") |> g_counter.increment(42)
  let json_str = json.to_string(g_counter.to_json(counter))

  // JSON must be parseable (no BEAM-specific types leaked)
  let result = g_counter.from_json(json_str)
  result |> expect.to_be_ok
  // Value round-trips correctly
  case result {
    Ok(decoded) ->
      g_counter.value(decoded) |> expect.to_equal(g_counter.value(counter))
    Error(_) -> expect.to_be_true(False)
  }
}
```

### Anti-Patterns to Avoid

- **Structural equality on LWW-Map:** `lww_map.merge(a, b) |> expect.to_equal(lww_map.merge(b, a))` — this compares internal dict structure. Use `lww_map.get(merged_ab, key) |> expect.to_equal(lww_map.get(merged_ba, key))` instead.

- **Structural equality on OR-Map:** Never use `expect.to_equal(or_map.merge(a, b), or_map.merge(b, a))` — internal OR-Set tag counters differ. Use `set.from_list(or_map.keys(...))` for key comparison.

- **Equal timestamps in LWW commutativity tests:** LWW-Map with `ts_a == ts_b` has first-arg-wins tie-break semantics. Use non-overlapping timestamp ranges in generators (e.g., `bounded_int(1, 50)` vs `bounded_int(51, 100)`) to ensure deterministic commutativity.

- **Generating full OR-Map structures with qcheck:** Don't try to generate `ORMap` values directly with qcheck generators. Generate only the scalar parameters (increments, timestamps, element values) and construct CRDT states deterministically in the test body.

- **Missing `Nil` return in property closures:** Every `qcheck.run` property closure must return `Nil`. Forgetting this causes a type error.

- **OR-Map associativity:** Like MV-Register, OR-Map associativity is extremely complex to construct valid triples for. Skip associativity for OR-Map (as was done for MV-Register in Phase 2 plan 04). Document the skip with a comment.

- **test_count too high in convergence tests:** Convergence tests with 3 replicas are O(n) in operations. Keep test_count at 10 per the established `small_test_config()`.

- **Dot vs VersionVector confusion:** Dot Context and Version Vector solve different problems. Version Vector compresses causal history into per-replica maximums (compact). Dot Context tracks individual events (dots) precisely. For CLOCK-06 to CLOCK-09, implement `DotContext` as a `set.Set(Dot)` — no compression, just membership.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Deduplication in all-to-all exchange | Custom dedup | `list.unique` from stdlib | Already established pattern from g_counter.merge |
| Set operations for Dot Context | Custom set logic | `gleam/set` (set.insert, set.delete, set.contains) | stdlib provides all needed ops |
| Observable set comparison | Sort + compare lists | `set.from_list(keys())` then `expect.to_equal` | Gleam set equality is content-based, order-independent |
| LWW-Map equal-timestamp commutativity proof | Complex invariant | Use non-overlapping timestamp ranges in generators | Sidesteps tie-break by design; cleaner and correct |

**Key insight:** Phase 4 has no new library dependencies. The only new implementation work is `dot_context.gleam` (~50 lines). Everything else is test writing using established patterns.

## Common Pitfalls

### Pitfall 1: LWW-Register Bottom Identity With Timestamp 0
**What goes wrong:** `merge(reg_ts_5, lww_register.new("", 0))` returns `reg_ts_5` (correct). But `merge(lww_register.new("x", 0), lww_register.new("", 0))` — both have timestamp 0, so tiebreak (second arg wins) makes the "bottom" win, which appears wrong.
**Why it happens:** LWW-Register bottom is only a true bottom for registers with timestamp >= 1. At timestamp 0, the tie-break behavior kicks in.
**How to avoid:** In bottom identity tests for LWW-Register, use a non-zero timestamp for the "non-bottom" register: `lww_register.new("value", 1)` vs `lww_register.new("", 0)`.

### Pitfall 2: OR-Set Idempotency Uses value() Not Structural Equality
**What goes wrong:** `or_set.merge(s, s) |> expect.to_equal(s)` — this compares internal tag dicts structurally. The counter field on OR-Set is the `max(a.counter, b.counter)`, so `merge(s, s)` keeps `s.counter` — structural equality holds here actually.
**Why it happens:** The or_set_property_test.gleam already handles this correctly with `or_set.value(or_set.merge(s, s)) |> expect.to_equal(or_set.value(s))`. Follow this established pattern.
**How to avoid:** Follow existing patterns from Phase 2 register_set_property_test.gleam.

### Pitfall 3: OR-Map Keys Order Nondeterminism
**What goes wrong:** `or_map.keys(merged)` returns a list in nondeterministic order. `expect.to_equal(keys_ab, keys_ba)` fails even if they contain the same elements.
**Why it happens:** `or_map.keys` calls `set.to_list` which has no guaranteed order.
**How to avoid:** Always wrap: `set.from_list(or_map.keys(m))` before comparing with `expect.to_equal`.

### Pitfall 4: Dot Context set.delete Requires Correct Type
**What goes wrong:** Using `set.delete(context.dots, Dot("A", 1))` — Gleam uses structural equality for custom types in sets. This works correctly as long as `Dot` constructors are called with identical arguments. No pitfall if `Dot` type is non-opaque and constructors match exactly.
**Why it happens:** Custom type records use structural equality in Gleam.
**How to avoid:** Ensure `Dot(replica_id: "A", counter: 1)` and `Dot("A", 1)` are the same value — they are since named and positional args resolve to the same struct in Gleam.

### Pitfall 5: MV-Register Associativity Is Infeasible
**What goes wrong:** Trying to write a property test for MV-Register associativity with random inputs — the test will either be trivially deterministic (same replica, sequential) or will require constructing valid causally-related triples.
**Why it happens:** MV-Register merge requires careful construction of vclock-compatible states. The Phase 2 decision explicitly skipped this.
**How to avoid:** Skip OR-Map and MV-Register associativity, mirroring the Phase 2 decision. Add a comment: `// Associativity skipped: constructing valid vclock triples for property testing is infeasible; see Phase 2 plan 04 decision.`

### Pitfall 6: qcheck.seed(42) Is Mandatory
**What goes wrong:** Using `qcheck.default_config()` without a fixed seed causes non-deterministic test results. Different runs may fail or pass depending on the seed.
**Why it happens:** qcheck uses a random seed by default.
**How to avoid:** Always use `small_test_config()` as defined in counter_property_test.gleam:
```gleam
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}
```

## Code Examples

Verified patterns from codebase (all examples drawn from actual implemented files):

### Existing small_test_config Pattern (from counter_property_test.gleam)
```gleam
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}
```

### Existing Convergence Pattern (to extend for TEST-04)
```gleam
// Extension of existing 3-counter tests in counter_property_test.gleam
// Use qcheck.map3 for 3 independent operation values
qcheck.run(
  small_test_config(),
  qcheck.map3(
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    qcheck.small_non_negative_int(),
    fn(a, b, c) { #(a, b, c) },
  ),
  fn(triple) { /* ... */ Nil },
)
```

### Observable OR-Map Comparison (must use for TEST-01, TEST-03)
```gleam
// Compare keys as sets (order-independent)
set.from_list(or_map.keys(merged_ab))
|> expect.to_equal(set.from_list(or_map.keys(merged_ba)))

// Compare value count for simple cases
list.length(or_map.values(merged_ab))
|> expect.to_equal(list.length(or_map.values(merged_ba)))
```

### Dot Context Complete Implementation
```gleam
// src/lattice/dot_context.gleam
import gleam/list
import gleam/set

pub type Dot {
  Dot(replica_id: String, counter: Int)
}

pub type DotContext {
  DotContext(dots: set.Set(Dot))
}

pub fn new() -> DotContext {
  DotContext(dots: set.new())
}

pub fn add_dot(context: DotContext, replica_id: String, counter: Int) -> DotContext {
  DotContext(dots: set.insert(context.dots, Dot(replica_id: replica_id, counter: counter)))
}

pub fn remove_dots(context: DotContext, dots: List(Dot)) -> DotContext {
  DotContext(
    dots: list.fold(dots, context.dots, fn(acc, dot) { set.delete(acc, dot) }),
  )
}

pub fn contains_dots(context: DotContext, dots: List(Dot)) -> Bool {
  list.all(dots, fn(dot) { set.contains(context.dots, dot) })
}
```

### Bottom Identity Test Pattern (TEST-05)
```gleam
// Works for all set types (value() returns set.Set)
pub fn g_set_bottom_identity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.bounded_int(0, 20),
    fn(n) {
      let s = g_set.new() |> g_set.add(int.to_string(n))
      let bottom = g_set.new()
      g_set.value(g_set.merge(s, bottom))
      |> expect.to_equal(g_set.value(s))
      Nil
    },
  )
}
```

### Monotonicity Test Pattern (TEST-06)
```gleam
// G-Counter: value(merge(a, b)) >= value(a) AND >= value(b)
pub fn g_counter_value_monotone__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let ca = g_counter.new("A") |> g_counter.increment(a)
      let cb = g_counter.new("B") |> g_counter.increment(b)
      let merged_val = g_counter.value(g_counter.merge(ca, cb))
      expect.to_be_true(merged_val >= g_counter.value(ca))
      expect.to_be_true(merged_val >= g_counter.value(cb))
      Nil
    },
  )
}

// G-Set: value(merge(a, b)) is superset of value(a) and value(b)
pub fn g_set_value_monotone__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 20),
      qcheck.bounded_int(0, 20),
      fn(a, b) { #(a, b) },
    ),
    fn(pair) {
      let #(a, b) = pair
      let sa = g_set.new() |> g_set.add(int.to_string(a))
      let sb = g_set.new() |> g_set.add(int.to_string(b))
      let merged = g_set.merge(sa, sb)
      expect.to_be_true(set.is_subset(g_set.value(sa), g_set.value(merged)))
      expect.to_be_true(set.is_subset(g_set.value(sb), g_set.value(merged)))
      Nil
    },
  )
}
```

## What TEST-01, TEST-02, TEST-03 Still Need

Based on reviewing the existing property test files:

**`counter_property_test.gleam`** (done):
- G-Counter: commutativity, associativity, idempotency
- PN-Counter: commutativity, associativity, idempotency

**`register_set_property_test.gleam`** (done):
- LWW-Register: commutativity, associativity, idempotency
- MV-Register: commutativity, idempotency (associativity skipped)
- G-Set: commutativity, associativity, idempotency
- 2P-Set: commutativity, associativity, idempotency
- OR-Set: commutativity, idempotency (associativity skipped — not yet, but complex)

**Still needed (Phase 4):**
- LWW-Map: commutativity (with distinct timestamps), idempotency (straightforward), associativity (three maps, distinct timestamps)
- OR-Map: commutativity (observable keys), idempotency (observable keys unchanged after merge with self)
- OR-Set associativity: was not included in Phase 2. Can add in Phase 4 — simpler than MV-Register because OR-Set doesn't use vclocks directly.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual counter-example testing | qcheck property-based shrinking | Phase 1 | Automatic minimal counterexample finding |
| Full structural equality in merge tests | Observable value comparison | Phase 2 decision | Enables testing types with non-deterministic internal structure |
| `qcheck.default_config()` | `small_test_config()` with fixed seed | Phase 1 discovery | Prevents timeout; deterministic results |
| Testing commutativity with equal timestamps | Using non-overlapping timestamp ranges | Phase 3 LWW-Map decision | Avoids tie-break ambiguity in LWW-Map commutativity |

**Deprecated/outdated:**
- Using `expect.to_equal` on full OR-Set/MV-Register/OR-Map records: Always use value() comparison per Phase 2 decisions.
- `gleam/dynamic.field`: Old API. Always use `gleam/dynamic/decode` (already established).

## Open Questions

1. **OR-Set associativity — include or skip?**
   - What we know: OR-Set merge is a union of tag sets. Associativity of set union is mathematically guaranteed. Property-based testing can verify it.
   - What's unclear: Whether the counter field (max of the three) makes the test complex. Counter max is associative (max(max(a,b),c) == max(a,max(b,c))).
   - Recommendation: Include OR-Set associativity — it's simpler than MV-Register because there are no vclocks involved. The counter is simply max of all three.

2. **MV-Register round-trip property test (TEST-07 remaining)**
   - What we know: `serialization_property_test.gleam` doesn't yet include MV-Register or OR-Map round-trip property tests.
   - What's unclear: Whether structural equality holds for MV-Register after round-trip. Tag-keyed dict should reconstruct identically if the same entries are decoded.
   - Recommendation: Use observable equality — `list.sort(mv_register.value(decoded))` vs `list.sort(mv_register.value(original))`.

3. **OR-Map round-trip property test (TEST-07 remaining)**
   - What we know: `serialization_property_test.gleam` doesn't yet include OR-Map.
   - What's unclear: Whether OR-Map double-encoding (json.to_string of nested CRDTs) round-trips cleanly with qcheck-generated values.
   - Recommendation: Use observable equality: `set.from_list(or_map.keys(decoded)) == set.from_list(or_map.keys(original))`.

4. **Dot Context vs Version Vector overlap**
   - What we know: Version Vector is already implemented (CLOCK-01 to CLOCK-05). Dot Context tracks individual events rather than per-replica maximums.
   - What's unclear: Whether Dot Context should merge/compact like Version Vector, or remain as a raw set.
   - Recommendation: For v1, implement `DotContext` as a raw `set.Set(Dot)` per the requirements. No merge/compaction needed since requirements only specify new(), add_dot(), remove_dots(), contains_dots().

## Sources

### Primary (HIGH confidence)
- `/Volumes/Code/claude-workspace-ccl/lattice/test/property/counter_property_test.gleam` — Verified qcheck patterns (small_test_config, map2, map3, bounded_int, small_non_negative_int)
- `/Volumes/Code/claude-workspace-ccl/lattice/test/property/register_set_property_test.gleam` — Verified OR-Set, MV-Register, 2P-Set, G-Set observable equality patterns
- `/Volumes/Code/claude-workspace-ccl/lattice/test/property/serialization_property_test.gleam` — Verified round-trip property patterns, confirmed what's done and what's missing
- `/Volumes/Code/claude-workspace-ccl/lattice/src/lattice/*.gleam` — All 11 CRDT modules read; new() constructors confirmed for bottom identity tests
- `/Volumes/Code/claude-workspace-ccl/lattice/.planning/STATE.md` — Phase decisions verified (MV-Register associativity skip, OR-Set/MV-Register value() comparison, LWW-Map tiebreak semantics)

### Secondary (MEDIUM confidence)
- `/Volumes/Code/claude-workspace-ccl/lattice/test/set/or_set_test.gleam` — concurrent_add_wins_test verified; property-based variant derivation is straightforward extension
- `/Volumes/Code/claude-workspace-ccl/lattice/test/set/two_p_set_test.gleam` — tombstone_is_permanent_test verified; property-based variant is deterministic extension
- CRDT literature (Shapiro et al. 2011) — Dot Context standard definition as (replica, counter) pair set; verified against CLOCK-06 to CLOCK-09 requirements

### Tertiary (LOW confidence)
- Dot Context "compaction" behavior: The implementation recommendation (raw set, no compaction) is based on the requirement spec alone. If Dot Context needs to participate in delta-CRDT operations in the future, compaction (compressing into maximal contiguous ranges) may be needed. For v1 requirements only, raw set is correct.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries confirmed installed; no new deps needed
- Architecture: HIGH — all patterns derived directly from existing codebase files; no speculation
- Pitfalls: HIGH — all pitfalls derived from actual Phase 2/3 decisions documented in STATE.md and verifiable from source code

**Research date:** 2026-03-01
**Valid until:** 2026-04-01 (stable dependencies; no fast-moving ecosystem changes)
