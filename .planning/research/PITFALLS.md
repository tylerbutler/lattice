# Domain Pitfalls

**Domain:** CRDT Library in Gleam
**Researched:** 2026-02-28
**Overall confidence:** HIGH

## Critical Pitfalls

Mistakes that cause data corruption, convergence failures, or complete rewrites.

### Pitfall 1: Incorrect Merge Semantics (Merge Law Violations)

**What goes wrong:** Merge function fails one or more of the required semilattice properties:
- Not commutative: `merge(a, b) != merge(b, a)`
- Not associative: `merge(merge(a, b), c) != merge(a, merge(b, c))`
- Not idempotent: `merge(a, a) != a`

**Why it happens:** 
- Academic papers can have bugs in their specifications (Ditto found OAR-Set spec violated associativity)
- Optimized implementations may diverge from base specs
- Implementation errors in merge logic

**Consequences:** 
- Replicas fail to converge to same state
- Data corruption in distributed systems
- Race-dependent results based on merge order

**Prevention:** 
- Implement property-based tests for all merge laws (see TEST.md)
- Test convergence with random operation sequences across multiple replicas
- Start with textbook implementations before optimizing

**Detection:** Warning signs:
- Property tests fail with random operations
- Merge order affects final result
- `merge(merge(a, b), c)` differs from `merge(a, merge(b, c))`

**Phase:** Core types (G-Counter, G-Set) — these are the foundation

---

### Pitfall 2: OR-Set Concurrent Add Wins Behavior

**What goes wrong:** OR-Set's "concurrent add wins" semantics is counterintuitive in Remove Wins mode.

**Why it happens:** When peer A removes element X and peer B concurrently re-adds X:
- In Remove Wins: both removed, X is absent
- In Add Wins: X is present
- "Mutual destruction" scenario: both peers add→remove→re-add, then merge = empty set

**Consequences:** 
- Users surprised by element disappearing
- Data loss in collaborative scenarios

**Prevention:** 
- Document behavior clearly
- Consider supporting both AWSet and ORSet
- Test concurrent add/remove/re-add scenarios

**Detection:** Warning signs:
- Elements disappearing unexpectedly after sync
- Users report "my changes got lost"

**Phase:** OR-Set implementation — requires comprehensive scenario tests

---

### Pitfall 3: LWW-Register Timestamp Tiebreaker

**What goes wrong:** When two registers have identical timestamps, the winner is undefined or inconsistent.

**Why it happens:** 
- Clock skew or distributed timestamp generation
- No tiebreaker strategy documented/implemented

**Consequences:** 
- Non-deterministic merge results
- Violates commutativity property when timestamps equal

**Prevention:** 
- Document tiebreaker strategy (compare replica IDs lexicographically)
- Use logical timestamps (Lamport clocks) with replica ID as tiebreaker
- Never rely on wall-clock time alone

**Detection:** Warning signs:
- Merge results differ between runs
- Timestamp equality causes inconsistent behavior

**Phase:** LWW-Register — this must be correct from initial implementation

---

### Pitfall 4: Tombstone Accumulation (Unbounded Memory Growth)

**What goes wrong:** OR-Set, OR-Map accumulate tombstones indefinitely, causing memory to grow unbounded.

**Why it happens:** 
- Naive OR-Set never removes tombstones from remove-set
- Each add/remove cycle adds new tombstones
- Long-running systems eventually exhaust memory

**Consequences:** 
- Memory exhaustion in production
- Performance degradation over time

**Prevention:** 
- Implement garbage collection (see "optimized OR-Set" in academic literature)
- Consider merge-based GC: when all replicas have seen a tombstone, remove it
- Document memory characteristics and provide compaction utilities

**Detection:** Warning signs:
- Memory grows linearly with operations
- No GC mechanism visible in code

**Phase:** OR-Set, OR-Map, LWW-Map — plan for GC from design phase

---

### Pitfall 5: G-Counter vs PN-Counter Confusion

**What goes wrong:** Using G-Counter when PN-Counter is needed (or vice versa).

**Why it happens:** 
- G-Counter only supports increment (not decrement)
- PN-Counter can go negative
- Choosing wrong type leads to unexpected behavior

**Consequences:** 
- G-Counter: decrement is silently ignored or wraps incorrectly
- PN-Counter: negative values may be unexpected

**Prevention:** 
- Clearly document each counter's semantics
- G-Counter: "only increases" (likes, votes)
- PN-Counter: "can increase and decrease" (bank balance, inventory delta)

**Phase:** Counter types — get this right in initial design

---

### Pitfall 6: Version Vector Comparison Errors

**What goes wrong:** Version vector comparison (before/after/concurrent/equal) implemented incorrectly.

**Why it happens:** 
- Vector clocks are subtle: `{A:2, B:1}` vs `{A:1, B:2}` are concurrent, not comparable
- Many incorrect implementations treat all differences as comparable

**Consequences:** 
- Causal ordering decisions wrong
- OR-Set context tracking fails
- "Dead node update" scenarios break

**Prevention:** 
- Use existing verified implementations as reference
- Test all comparison cases: equal, before, after, concurrent (disjoint, mixed)

**Phase:** Version Vector — critical infrastructure for OR-Set

---

## Moderate Pitfalls

Issues that cause correctness problems in specific scenarios.

### Pitfall 7: Replica ID Collision in OR-Set

**What goes wrong:** Reusing replica IDs across different OR-Set instances causes elements to be incorrectly dropped.

**Why it happens:** OR-Set tracks "witnesses" (replica IDs) for each element. Same witness with different elements = both dropped.

**Consequences:** 
- Elements silently disappear during merge

**Prevention:** 
- Ensure unique replica IDs per CRDT instance
- Document: "don't reuse witness IDs across independent sets"

**Detection:** rust-crdt test: "weird highlight: same witness, different elements"

**Phase:** OR-Set

---

### Pitfall 8: PN-Counter Merge Same ID Semantics

**What goes wrong:** Merging two PN-Counters with same replica ID takes max of both P and N vectors incorrectly.

**Why it happens:** Naive implementation sums or takes wrong value.

**Consequences:** 
- Counter value incorrect after merge

**Prevention:** 
- For same replica ID: take max of P-values AND max of N-values
- Test: `a = new("X") |> increment(5); b = new("X") |> increment(3); merge(a,b)` should give P["X"]=5

**Phase:** PN-Counter

---

### Pitfall 9: Delta-State vs Full State Confusion

**What goes wrong:** Mixing delta-state and full-state CRDTs in same system.

**Why it happens:** 
- Delta-CRDTs only send changes, not full state
- Full-state CRDTs send entire state
- Merging delta into full-state produces wrong results

**Prevention:** 
- Clearly separate delta and state-based types
- Document delta format expectations

**Phase:** Delta-CRDT support (later phase)

---

### Pitfall 10: Cross-Platform Serialization Mismatch

**What goes wrong:** JSON serialized on Erlang doesn't deserialize correctly on JavaScript (or vice versa).

**Why it happens:** 
- Different number representations (Erlang atom vs JS string for keys)
- Character encoding differences
- Map key ordering

**Consequences:** 
- Data corrupted when syncing across platforms
- State reconciliation fails

**Prevention:** 
- Define canonical JSON format
- Test round-trip: Erlang encode → JavaScript decode → Erlang decode
- Use string keys consistently (not atoms in Erlang)

**Phase:** Serialization — critical for cross-target support

---

## Minor Pitfalls

Subtle issues that may not manifest in typical usage.

### Pitfall 11: LWW-Map Per-Key Timestamp Semantics

**What goes wrong:** LWW-Map semantics unclear: is it per-key timestamps or whole-map timestamp?

**Why it happens:** 
- Different implementations choose different semantics
- User expectations may not match implementation

**Prevention:** 
- Document: "per-key last-write-wins"
- Test: concurrent updates to different keys merge correctly

**Phase:** LWW-Map

---

### Pitfall 12: MV-Register Value Causal Drop

**What goes wrong:** MV-Register doesn't correctly drop causally dominated values.

**Why it happens:** 
- A sets v1, B merges A's state then sets v2
- Merging A and B should drop v1 (causally dominated by v2)

**Consequences:** 
- MV-Register returns multiple values when should return one

**Prevention:** 
- Track causal context per value
- Test causal chain scenarios

**Phase:** MV-Register

---

### Pitfall 13: Composite CRDT Keys in Maps

**What goes wrong:** Using CRDTs as values in LWW-Map doesn't merge nested CRDTs correctly.

**Why it happens:** 
- Map merge iterates keys but doesn't call nested CRDT merge

**Consequences:** 
- Nested counter/OR-Set doesn't converge

**Prevention:** 
- Implement recursive merge for composite types
- Test: two maps with same key, different OR-Set values

**Phase:** OR-Map, LWW-Map with nested types

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| G-Counter | Basic merge laws | Start with property tests from TEST.md |
| PN-Counter | Same ID merge semantics | Explicit test case for same replica ID |
| G-Set | Add is idempotent | Test `add("x") |> add("x")` = single element |
| 2P-Set | Tombstone permanence | Test add-remove-add: should stay removed |
| OR-Set | Concurrent add wins | Test add-remove-readd with concurrent merge |
| LWW-Register | Timestamp tiebreaker | Document and test equal timestamps |
| MV-Register | Causal drop | Test causal chain: A→B→C merge |
| Version Vector | Comparison bugs | Test all four cases: equal, before, after, concurrent |
| Serialization | Cross-platform | Test encode→decode round-trip |

---

## Sources

- **Ditto (2025):** "Testing CRDTs in Rust, from theory to practice" — Property-based testing found OAR-Set spec bug
  - https://www.ditto.com/blog/testing-crdts-in-rust-from-theory-to-practice
  
- **Riak (2015):** "Incompatibility between Dotted Version Vectors and Last-Write Wins"
  - https://docs.riak.com/community/productadvisories/dvvlastwritewins/index.html

- **Akka (2019):** "Document tombstone accumulation of OR-Set and OR-Map" — Issue #27151
  - https://github.com/akka/akka/issues/27151

- **Automerge (2025):** "Counters" — Warning about concurrent modifications
  - https://automerge.org/docs/reference/documents/counters

- **rust-crdt tests:** OR-Set edge cases including "weird highlight" bug
  - https://github.com/rust-crdt/rust-crdt

- **Bartosz Sypytkowski:** "State-based CRDTs" series — Implementation patterns
  - https://www.bartoszsypytkowski.com/the-state-of-a-state-based-crdts/

- **ACM (2016):** "The problem with embedded CRDT counters" — PN-Counter issues
  - https://dl.acm.org/doi/10.1145/2911151.2911159
