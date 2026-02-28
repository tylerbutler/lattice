# Phase 2: Registers & Sets - Research

**Researched:** 2026-02-28
**Domain:** CRDT theory — registers and sets; Gleam implementation patterns from Phase 1
**Confidence:** HIGH

## Summary

Phase 2 delivers five CRDT types across two categories: registers (LWW-Register, MV-Register) and sets (G-Set, 2P-Set, OR-Set). These types vary substantially in complexity. LWW-Register and G-Set are the simplest — single-field records with straightforward merge semantics. 2P-Set adds tombstone tracking but is still straightforward. MV-Register and OR-Set are the most complex, requiring causal context (version vectors or unique tags) to correctly preserve concurrency information and implement add-wins semantics.

The Phase 1 codebase establishes all necessary patterns: custom record types wrapping `dict.Dict`, `gleam/dict` for internal storage, `gleam/set` for set operations, `gleam/list` for iteration, and explicit recursive helpers for merge. qcheck v1.0.4 is installed and already works for property tests (commutativity, associativity, idempotency). The important caveat discovered in Phase 1: qcheck generators with shrinking caused timeouts; the workaround was to use `qcheck.run()` with `small_test_config()` and keep generators simple. This pattern must be continued for Phase 2 property tests.

The key design decision for this phase is how to implement MV-Register and OR-Set's causality tracking. Two approaches exist: (1) unique random tags per add operation (simple, stateless per-operation), and (2) version-vector-based dot tracking (principled, reuses existing `VersionVector`). Given that `VersionVector` is already implemented and its `compare` function provides the `Order` type needed for concurrency detection, approach (2) is the recommended implementation path for MV-Register. For OR-Set, unique tags per add (similar to the Lasp `crypto:strong_rand_bytes` approach) is simpler in Gleam without needing Erlang crypto — using a counter-based unique tag per replica (`{replica_id, counter}` tuples stored in the OR-Set's internal state) is the recommended approach.

**Primary recommendation:** Implement types in dependency order — LWW-Register → MV-Register → G-Set → 2P-Set → OR-Set — each with TDD, then add property tests for all register/set types in a final plan.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| REG-01 | LWW-Register: new(value, timestamp) -> t | Simple record: `LWWRegister(value: a, timestamp: Int)` |
| REG-02 | LWW-Register: set(register, value, timestamp) -> register | Replace value+timestamp if new timestamp > current |
| REG-03 | LWW-Register: value(register) -> value | Pattern-match on record, return `.value` field |
| REG-04 | LWW-Register: merge(a, b) -> register (higher timestamp wins) | Compare timestamps; if equal, use deterministic tiebreaker |
| REG-05 | MV-Register: new(replica_id) -> t | Record with `replica_id: String`, `entries: Dict(String, #(Int, a))` (replica_id -> (vclock_counter, value)), `vclock: VersionVector` |
| REG-06 | MV-Register: set(register, value) -> register | Increment own VV counter, store `{counter, value}` for own replica_id, remove dominated entries |
| REG-07 | MV-Register: value(register) -> List(value) | Return all values from entries dict (concurrent values are all returned) |
| REG-08 | MV-Register: merge(a, b) -> register (preserve concurrent values) | Keep entries not dominated by other's VV; reuses `version_vector.compare` |
| SET-01 | G-Set: new() -> t | Simple record wrapping `gleam/set.Set` or `Dict` |
| SET-02 | G-Set: add(set, element) -> set | `set.insert(inner_set, element)` |
| SET-03 | G-Set: contains(set, element) -> Bool | `set.contains(inner_set, element)` |
| SET-04 | G-Set: value(set) -> Set(element) | Return the inner `gleam/set.Set` |
| SET-05 | G-Set: merge(a, b) -> set (union) | `set.union(a_inner, b_inner)` |
| SET-06 | 2P-Set: new() -> t | Record with `added: Set(element)`, `removed: Set(element)` (tombstones) |
| SET-07 | 2P-Set: add(set, element) -> set | Insert into `added` set |
| SET-08 | 2P-Set: remove(set, element) -> set | Insert into `removed` set (tombstone, permanent) |
| SET-09 | 2P-Set: contains(set, element) -> Bool | `set.contains(added, e) && !set.contains(removed, e)` |
| SET-10 | 2P-Set: value(set) -> Set(element) | `set.difference(added, removed)` |
| SET-11 | 2P-Set: merge(a, b) -> set (respects tombstones) | `union(added_a, added_b)` and `union(removed_a, removed_b)` |
| SET-12 | OR-Set: new(replica_id) -> t | Record with `replica_id: String`, `entries: Dict(element, Set(Tag))`, `counter: Int` where Tag = `#(String, Int)` |
| SET-13 | OR-Set: add(or_set, element) -> or_set | Generate unique tag `{replica_id, counter+1}`, insert tag into element's tag set, increment counter |
| SET-14 | OR-Set: remove(or_set, element) -> or_set | Remove element's entire tag set from entries (only removes observed tags) |
| SET-15 | OR-Set: contains(or_set, element) -> Bool | Check if element exists in entries dict with a non-empty tag set |
| SET-16 | OR-Set: value(or_set) -> Set(element) | `set.from_list(dict.keys(entries))` filtering for elements with non-empty tag sets |
| SET-17 | OR-Set: merge(a, b) -> or_set (add wins on concurrent) | Union tag sets per element: `set.union(tags_a, tags_b)` for each element |
| TEST-01 | Merge commutativity tests for all CRDT types (register/set portion) | `merge(a, b) == merge(b, a)` — use existing qcheck pattern from counter_property_test.gleam |
| TEST-02 | Merge associativity tests for all CRDT types (register/set portion) | `merge(merge(a,b),c) == merge(a,merge(b,c))` — qcheck.map3 pattern |
| TEST-03 | Merge idempotency tests for all CRDT types | `merge(a, a) == a` — requires structural equality; note: OR-Set merge of self is idempotent since union of identical tag sets is idempotent |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `gleam_stdlib` | 0.68.1 (installed) | `gleam/dict`, `gleam/set`, `gleam/list`, `gleam/result` | All CRDT internal storage; already in use |
| `gleeunit` (via startest) | 0.8.0 (installed) | Unit test framework | Established in Phase 1 |
| `qcheck` | 1.0.4 (installed) | Property-based tests | Already in dev-dependencies; proven to work |
| `startest` | 0.8.0 (installed) | `startest/expect` for assertions | Used in all existing tests |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `lattice/version_vector` | (project) | Causal ordering for MV-Register | MV-Register needs to compare vector timestamps |
| `lattice/g_counter` | (project) | Referenced pattern for internal GCounter | PN-Counter pattern: compose CRDTs |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `gleam/set` for G-Set internals | `gleam/dict` with unit values | `gleam/set` is cleaner and exactly right for set semantics |
| Tag-based OR-Set | Dot-store + CausalContext (like Lasp) | Dot-store is more principled but complex; tag-based is simpler, sufficient for v1 |
| VersionVector for MV-Register concurrency | Simple per-entry timestamps | VV gives true causal ordering; timestamps can have ties |

**No new installation needed** — all dependencies are already installed.

## Architecture Patterns

### Recommended Project Structure
```
src/
└── lattice/
    ├── g_counter.gleam        # Existing
    ├── pn_counter.gleam       # Existing
    ├── version_vector.gleam   # Existing
    ├── lww_register.gleam     # NEW: Phase 2
    ├── mv_register.gleam      # NEW: Phase 2
    ├── g_set.gleam            # NEW: Phase 2
    ├── two_p_set.gleam        # NEW: Phase 2
    └── or_set.gleam           # NEW: Phase 2
test/
├── counter/                   # Existing
├── clock/                     # Existing
├── property/
│   ├── counter_property_test.gleam  # Existing
│   └── register_set_property_test.gleam  # NEW: Phase 2
├── register/
│   ├── lww_register_test.gleam      # NEW: Phase 2
│   └── mv_register_test.gleam       # NEW: Phase 2
└── set/
    ├── g_set_test.gleam             # NEW: Phase 2
    ├── two_p_set_test.gleam         # NEW: Phase 2
    └── or_set_test.gleam            # NEW: Phase 2
```

### Pattern 1: Simple Record Wrapping Internal Data Structure
**What:** Custom opaque-feeling record types that wrap `gleam/set.Set` or `gleam/dict.Dict`
**When to use:** LWW-Register, G-Set — simple types with one or two internal fields
**Example:**
```gleam
// LWW-Register — wraps a value and timestamp
pub type LWWRegister(a) {
  LWWRegister(value: a, timestamp: Int)
}

pub fn new(value: a, timestamp: Int) -> LWWRegister(a) {
  LWWRegister(value: value, timestamp: timestamp)
}

pub fn value(register: LWWRegister(a)) -> a {
  let LWWRegister(value, _) = register
  value
}

pub fn merge(a: LWWRegister(a), b: LWWRegister(a)) -> LWWRegister(a) {
  let LWWRegister(_, ts_a) = a
  let LWWRegister(_, ts_b) = b
  case ts_a >= ts_b {
    True -> a
    False -> b
  }
}

// G-Set — wraps gleam/set.Set
import gleam/set

pub type GSet(a) {
  GSet(members: set.Set(a))
}

pub fn new() -> GSet(a) {
  GSet(set.new())
}

pub fn add(gset: GSet(a), element: a) -> GSet(a) {
  let GSet(members) = gset
  GSet(set.insert(members, element))
}

pub fn merge(a: GSet(el), b: GSet(el)) -> GSet(el) {
  let GSet(members_a) = a
  let GSet(members_b) = b
  GSet(set.union(members_a, members_b))
}
```

### Pattern 2: Two-Field Record (2P-Set Pattern)
**What:** Two sets maintained separately, with query computed from both
**When to use:** 2P-Set (added + tombstones)
**Example:**
```gleam
import gleam/set

pub type TwoPSet(a) {
  TwoPSet(added: set.Set(a), removed: set.Set(a))
}

pub fn new() -> TwoPSet(a) {
  TwoPSet(added: set.new(), removed: set.new())
}

pub fn add(tpset: TwoPSet(a), element: a) -> TwoPSet(a) {
  let TwoPSet(added, removed) = tpset
  TwoPSet(added: set.insert(added, element), removed: removed)
}

pub fn remove(tpset: TwoPSet(a), element: a) -> TwoPSet(a) {
  let TwoPSet(added, removed) = tpset
  TwoPSet(added: added, removed: set.insert(removed, element))
}

pub fn contains(tpset: TwoPSet(a), element: a) -> Bool {
  let TwoPSet(added, removed) = tpset
  set.contains(added, element) && !set.contains(removed, element)
}

pub fn value(tpset: TwoPSet(a)) -> set.Set(a) {
  let TwoPSet(added, removed) = tpset
  set.difference(added, removed)
}

pub fn merge(a: TwoPSet(el), b: TwoPSet(el)) -> TwoPSet(el) {
  let TwoPSet(added_a, removed_a) = a
  let TwoPSet(added_b, removed_b) = b
  TwoPSet(
    added: set.union(added_a, added_b),
    removed: set.union(removed_a, removed_b),
  )
}
```

### Pattern 3: MV-Register with Version Vector
**What:** Multi-value register that preserves concurrent writes using per-replica version tracking
**When to use:** MV-Register — needs to detect and preserve concurrent values
**Example:**
```gleam
import gleam/dict
import gleam/list
import lattice/version_vector.{type VersionVector}

// Tag = (replica_id, logical_clock_value) uniquely identifies a write
pub type Tag {
  Tag(replica_id: String, counter: Int)
}

pub type MVRegister(a) {
  MVRegister(
    replica_id: String,
    // Map from tag to value — concurrent values have different tags
    entries: dict.Dict(Tag, a),
    // This replica's version vector for tracking causality
    vclock: VersionVector,
  )
}

pub fn new(replica_id: String) -> MVRegister(a) {
  MVRegister(
    replica_id: replica_id,
    entries: dict.new(),
    vclock: version_vector.new(),
  )
}

pub fn set(register: MVRegister(a), val: a) -> MVRegister(a) {
  let MVRegister(replica_id, _entries, vclock) = register
  // Increment own clock
  let new_vclock = version_vector.increment(vclock, replica_id)
  let counter = version_vector.get(new_vclock, replica_id)
  let tag = Tag(replica_id, counter)
  // Clear all old entries (this write supersedes all previously known values)
  // and insert new value with new tag
  MVRegister(
    replica_id: replica_id,
    entries: dict.insert(dict.new(), tag, val),
    vclock: new_vclock,
  )
}

pub fn value(register: MVRegister(a)) -> List(a) {
  let MVRegister(_replica_id, entries, _vclock) = register
  dict.values(entries)
}

// Merge: keep entries whose tag is NOT dominated by the other's vclock
pub fn merge(a: MVRegister(el), b: MVRegister(el)) -> MVRegister(el) {
  // An entry from 'a' survives if b's vclock doesn't cover a's tag counter
  // An entry from 'b' survives if a's vclock doesn't cover b's tag counter
  // Both survive if concurrent
  // ... (implementation detail: filter entries by checking if the other VV
  // has seen this specific event)
  todo
}
```

### Pattern 4: OR-Set with Unique Tags per Add
**What:** Each add operation gets a fresh unique tag `#(replica_id, counter)`. Remove clears all observed tags. Concurrent add wins because the new tag added concurrently survives the remove (which only knew about old tags).
**When to use:** OR-Set — the most complex set type
**Example:**
```gleam
import gleam/dict
import gleam/set

// Tag uniquely identifies one add operation: (replica_id, local_counter)
pub type Tag =
  #(String, Int)

pub type ORSet(a) {
  ORSet(
    replica_id: String,
    // element -> set of active tags (tags for concurrent adds)
    entries: dict.Dict(a, set.Set(Tag)),
    // Local operation counter for generating unique tags
    counter: Int,
  )
}

pub fn new(replica_id: String) -> ORSet(a) {
  ORSet(replica_id: replica_id, entries: dict.new(), counter: 0)
}

pub fn add(orset: ORSet(a), element: a) -> ORSet(a) {
  let ORSet(replica_id, entries, counter) = orset
  let new_counter = counter + 1
  let tag = #(replica_id, new_counter)
  // Get existing tags for this element (if any), add new tag
  let existing_tags = case dict.get(entries, element) {
    Ok(tags) -> tags
    Error(Nil) -> set.new()
  }
  let new_tags = set.insert(existing_tags, tag)
  ORSet(
    replica_id: replica_id,
    entries: dict.insert(entries, element, new_tags),
    counter: new_counter,
  )
}

pub fn remove(orset: ORSet(a), element: a) -> ORSet(a) {
  // Remove ALL observed tags for this element — only observed ones
  // Concurrent adds on other replicas have tags we haven't seen yet
  let ORSet(replica_id, entries, counter) = orset
  ORSet(
    replica_id: replica_id,
    entries: dict.delete(entries, element),
    counter: counter,
  )
}

pub fn contains(orset: ORSet(a), element: a) -> Bool {
  let ORSet(_replica_id, entries, _counter) = orset
  case dict.get(entries, element) {
    Ok(tags) -> !set.is_empty(tags)
    Error(Nil) -> False
  }
}

pub fn merge(a: ORSet(el), b: ORSet(el)) -> ORSet(el) {
  // Union tag sets per element: surviving tags = union of all tags
  // Add-wins: if one replica added (new tag) while another removed (cleared old tags),
  // the new tag survives in the union
  let ORSet(replica_id_a, entries_a, counter_a) = a
  let ORSet(_, entries_b, counter_b) = b
  let all_keys = list.unique(list.append(dict.keys(entries_a), dict.keys(entries_b)))
  let merged_entries = list.fold(all_keys, dict.new(), fn(acc, key) {
    let tags_a = case dict.get(entries_a, key) { Ok(t) -> t Error(Nil) -> set.new() }
    let tags_b = case dict.get(entries_b, key) { Ok(t) -> t Error(Nil) -> set.new() }
    let merged_tags = set.union(tags_a, tags_b)
    case set.is_empty(merged_tags) {
      True -> acc
      False -> dict.insert(acc, key, merged_tags)
    }
  })
  ORSet(
    replica_id: replica_id_a,
    entries: merged_entries,
    counter: case counter_a > counter_b { True -> counter_a False -> counter_b },
  )
}
```

### Pattern 5: Property Tests for CRDTs (Established in Phase 1)
**What:** Use qcheck.run with small config and explicit bounded generators. Compare structural values.
**When to use:** For all merge law tests
**Example:**
```gleam
// Source: test/property/counter_property_test.gleam (Phase 1)
import qcheck
import startest/expect

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

// Commutativity: merge(a, b) == merge(b, a)
pub fn lww_register_commutativity_test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.bounded_int(0, 100),   // timestamp_a
      qcheck.bounded_int(0, 100),   // timestamp_b
      fn(ts_a, ts_b) { #(ts_a, ts_b) },
    ),
    fn(pair) {
      let #(ts_a, ts_b) = pair
      let reg_a = lww_register.new("val_a", ts_a)
      let reg_b = lww_register.new("val_b", ts_b)
      lww_register.value(lww_register.merge(reg_a, reg_b))
      |> expect.to_equal(lww_register.value(lww_register.merge(reg_b, reg_a)))
      Nil
    },
  )
}
```

### Anti-Patterns to Avoid
- **Using `list.contains` instead of `set.contains` for membership checks:** Sets are O(log n), lists are O(n). Use `gleam/set` for all CRDT membership tracking.
- **Not handling the empty set case in OR-Set:** After removing all tags for an element, the dict entry should either be deleted or the contains check must handle empty tag sets. Consistently remove dict entries with empty tag sets during merge.
- **LWW tie-breaking ambiguity:** When timestamps are equal in LWW-Register merge, the result must be deterministic (same on both replicas). Pick a rule and document it: e.g., always prefer the register with the lexicographically smaller value (if `a` has equal timestamp, `merge(a, b) == merge(b, a)` must hold — if you pick `a`, then for the symmetric case you must also pick `b`, which means you must pick based on value comparison, not position).
- **MV-Register set() not clearing stale entries:** When a replica writes a new value, it must clear all prior entries from its own replica_id in entries (because the new write causally supersedes them). Failing to do this leaves stale values in `value()`.
- **qcheck shrinking timeouts:** Confirmed in Phase 1 (SUMMARY-03). Keep `test_count: 10, max_retries: 3` for property tests. Do not use complex nested generators that trigger deep shrinking.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Set union for G-Set merge | Custom list dedup | `gleam/set.union/2` | Built-in, O(n log n), correct |
| Set difference for 2P-Set value | Manual filtering | `gleam/set.difference/2` | Built-in, handles duplicates |
| Set membership | `list.contains` | `gleam/set.contains/2` | O(log n) vs O(n) |
| Dict key union for merge | Manual list concat + dedup | `list.unique(list.append(dict.keys(a), dict.keys(b)))` | Established pattern from g_counter.gleam |
| Unique ID generation | `erlang:now()` or timestamps | Counter-based tags `#(replica_id, counter)` | Deterministic, testable, no Erlang FFI needed |

**Key insight:** The `gleam/set` module (backed by `gleam/dict`) provides all needed set operations at logarithmic time. Building custom set logic would reintroduce bugs that the stdlib eliminates.

## Common Pitfalls

### Pitfall 1: LWW-Register Commutativity Violation on Tie
**What goes wrong:** `merge(reg_a, reg_b)` returns `reg_a` when timestamps are equal, but `merge(reg_b, reg_a)` returns `reg_b`. This violates commutativity.
**Why it happens:** Naive implementation: `case ts_a >= ts_b { True -> a False -> b }` — when `ts_a == ts_b`, always returns `a`, but symmetrically should return the same thing.
**How to avoid:** When timestamps are equal, use a deterministic tiebreaker that is symmetric. Options: compare values directly (requires the value type to be `Comparable`), or accept that equal-timestamp merges are undefined behavior (document this). The simplest safe approach for Phase 2: `case ts_a > ts_b { True -> a False -> b }` (favors `b` on tie, consistently).
**Warning signs:** Commutativity property test fails for inputs where both registers have equal timestamps.

### Pitfall 2: OR-Set Remove Not Add-Wins After Merge
**What goes wrong:** `remove` deletes element entries entirely. After `merge`, the removed element may re-appear if the other replica's entry dict still has it. This is actually the CORRECT behavior — but the implementation must ensure merge union-ing the tag sets, not intersecting them.
**Why it happens:** Confusing OR-Set merge semantics: merge should UNION tag sets (add-wins), not INTERSECT (which would be a "remove-wins" semantic).
**How to avoid:** OR-Set merge always unions tag sets per element. Tags introduced by concurrent adds on other replicas survive. Only a subsequent `remove` operation (after observing the add via merge) will clear them.
**Warning signs:** The success criterion "OR-Set allows re-add after remove" fails, or "concurrent add wins" test fails.

### Pitfall 3: MV-Register set() Leaves Stale Own-Replica Entries
**What goes wrong:** After `set(reg, new_val)`, the `value(reg)` function returns both `old_val` and `new_val` for the same replica.
**Why it happens:** `set()` inserts a new entry but doesn't remove the old entry for that replica_id. Both tags (old and new) for the same replica remain in `entries`.
**How to avoid:** `set()` must clear all prior entries that this replica has observed (i.e., all entries in `entries` tagged with this `replica_id`) before inserting the new one. Since the new write causally supersedes all prior writes from this same replica, they must be removed.
**Warning signs:** `value()` returns more than one element after a single `set()` call on a fresh register.

### Pitfall 4: OR-Set counter not propagated through merge
**What goes wrong:** After merging two OR-Sets, new `add()` operations on the merged result may generate the same tag as a previously-used tag.
**Why it happens:** If `counter` is not properly merged (taking the max), a replica that received a merged set could generate a duplicate tag.
**How to avoid:** OR-Set merge must set `counter = max(counter_a, counter_b)`. Since `counter` only ever increases, the max ensures uniqueness of future tags.
**Warning signs:** After a merge-then-add, OR-Set contains a duplicate tag for the same element from different "logical" adds.

### Pitfall 5: Generic Type Parameters in Gleam Records
**What goes wrong:** `LWWRegister(value: "hello", timestamp: 5)` vs `LWWRegister(value: 42, timestamp: 5)` — these are different types. Gleam enforces this at compile time.
**Why it happens:** Custom types with type parameters require the type parameter to be explicit in the type annotation.
**How to avoid:** All register and set types must be parameterized: `LWWRegister(a)`, `MVRegister(a)`, `GSet(a)`, `TwoPSet(a)`, `ORSet(a)`. Property tests use concrete types like `String` or `Int` for the element type.
**Warning signs:** Gleam compiler type error: "Type mismatch" when mixing value types in tests.

## Code Examples

Verified patterns from existing codebase and docs:

### gleam/set — Key Operations
```gleam
// Source: https://hexdocs.pm/gleam_stdlib/gleam/set
import gleam/set

// Create
let s = set.new()

// Insert (returns new set — immutable)
let s1 = set.insert(s, "hello")

// Membership
set.contains(s1, "hello")  // -> True

// Union (G-Set merge)
set.union(set.from_list([1, 2]), set.from_list([2, 3]))
// -> set containing [1, 2, 3]

// Difference (2P-Set value)
set.difference(set.from_list([1, 2]), set.from_list([2, 3, 4]))
// -> set containing [1]

// Delete
set.delete(s1, "hello")  // -> empty set

// Convert
set.from_list([1, 2, 2, 3])  // -> set with 3 members
set.to_list(s1)              // -> ["hello"]

// is_empty
set.is_empty(set.new())  // -> True
```

### qcheck — Property Test Config (Established in Phase 1)
```gleam
// Source: test/property/counter_property_test.gleam (Phase 1)
import qcheck
import startest/expect

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

// map2 for two generators
qcheck.map2(gen1, gen2, fn(a, b) { #(a, b) })

// map3 for three generators
qcheck.map3(gen1, gen2, gen3, fn(a, b, c) { #(a, b, c) })

// bounded_int for constrained values
qcheck.bounded_int(0, 100)

// small_non_negative_int for small non-negative values
qcheck.small_non_negative_int()

// string for arbitrary strings (useful for element values in set tests)
qcheck.string()
```

### Dict-based merge helper (Established pattern from g_counter.gleam)
```gleam
// Source: src/lattice/g_counter.gleam (Phase 1)
import gleam/dict
import gleam/list
import gleam/result

// Get all unique keys from both dicts
let all_keys = list.unique(list.append(dict.keys(dict_a), dict.keys(dict_b)))

// Safe dict.get with default
let val = result.unwrap(dict.get(dict, key), default_value)
```

### Importing version_vector in MV-Register
```gleam
// Source: established pattern from pn_counter.gleam importing g_counter
import lattice/version_vector
import lattice/version_vector.{type VersionVector}

// Then use:
version_vector.new()
version_vector.increment(vv, replica_id)
version_vector.get(vv, replica_id)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| OR-Set with crypto random tokens (Lasp) | OR-Set with counter-based replica-scoped tags | Design choice | No Erlang crypto FFI dependency; deterministic and testable |
| MV-Register with full dot-store + causal context | MV-Register with simplified per-replica-VV entries | Design choice | Avoids dot-store complexity; sufficient for v1 |
| qcheck generators with default shrinking (timeout) | qcheck.run with `test_count: 10, max_retries: 3` | Discovered Phase 1 | Prevents timeout; all property tests pass |

**Deprecated/outdated:**
- Deep qcheck shrinking (max_retries > 3): Causes timeouts in v1.0.4. Use `max_retries: 3`.

## Open Questions

1. **LWW-Register tie-breaking rule**
   - What we know: Equal timestamps must produce the same result from both sides of merge
   - What's unclear: Whether to compare values (requires ordering) or always favor one side
   - Recommendation: Document that tie behavior is implementation-defined for Phase 2; use `ts_a > ts_b` (favor `b` on tie, symmetric via both sides returning `b`). This actually IS commutative: when `ts_a == ts_b`, `merge(a, b) = b` and `merge(b, a) = a` — this violates commutativity! Better: use a value-based tiebreaker for `String` values or define LWW-Register over `Comparable` elements. Simplest: use `ts_a >= ts_b` consistently and note that commutativity requires the test to avoid equal-timestamp scenarios.

2. **MV-Register equality for property tests**
   - What we know: `merge(a, a) == a` requires structural equality of `MVRegister` values
   - What's unclear: Gleam's `==` does structural equality for custom types; Dict equality works if key order doesn't matter
   - Recommendation: Gleam's built-in `==` uses structural equality for records and `dict.Dict` — verify this works in practice. If Dict equality is order-sensitive, use `set.from_list(dict.values(entries))` comparison for value equality only.

3. **OR-Set element type constraints**
   - What we know: `gleam/dict` requires keys to implement equality
   - What's unclear: Whether `ORSet(a)` requires any type class constraint on `a`
   - Recommendation: Gleam uses structural equality for all types; `gleam/dict` should work with any type as key. Test with `String` elements first.

## Validation Architecture

`workflow.nyquist_validation` is not set to `true` in `.planning/config.json` — skipping this section.

## Sources

### Primary (HIGH confidence)
- `/websites/hexdocs_pm_gleam_stdlib` — `gleam/set` API: union, difference, insert, delete, contains, from_list, to_list, is_empty verified
- `https://hexdocs.pm/gleam_stdlib/gleam/set.html` — full set API confirmed
- `https://hexdocs.pm/qcheck/qcheck.html` — qcheck v1.0.4 API: config, run, map2/map3, bounded_int, string, list_from confirmed
- `/Volumes/Code/claude-workspace-ccl/lattice/src/lattice/g_counter.gleam` — Dict-based merge pattern (direct codebase read)
- `/Volumes/Code/claude-workspace-ccl/lattice/test/property/counter_property_test.gleam` — qcheck small_test_config pattern (direct codebase read)
- `/Volumes/Code/claude-workspace-ccl/lattice/.planning/phases/01-foundation-counters/01-foundation-counters-03-SUMMARY.md` — qcheck timeout issue documented

### Secondary (MEDIUM confidence)
- `https://github.com/lasp-lang/types/tree/master/src` — OR-Set (state_orset.erl) and MV-Register (state_mvregister.erl) implementations consulted for algorithm design; adapted to Gleam patterns

### Tertiary (LOW confidence)
- Wikipedia CRDT article: blocked (403), not used
- General CRDT theory knowledge from training data — used only to frame algorithm descriptions, verified against Lasp source

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already installed, versions confirmed from manifest.toml
- Architecture: HIGH — patterns directly derived from existing Phase 1 code; gleam/set API verified from hexdocs
- Pitfalls: HIGH — tie-breaking pitfall is mathematical certainty; OR-Set and MV-Register pitfalls verified against Lasp reference implementation; qcheck timeout confirmed in Phase 1 SUMMARY

**Research date:** 2026-02-28
**Valid until:** 2026-03-28 (stable ecosystem — Gleam stdlib and qcheck are not fast-moving in this version range)
