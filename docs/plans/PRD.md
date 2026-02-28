# Lattice — CRDT Library for Gleam

**Version:** 1.0  
**Date:** February 2026  
**Status:** Draft  

---

## 1. Overview

### 1.1 Problem Statement

The Gleam ecosystem has no comprehensive CRDT library. The only existing package is lpil's `lww-register-crdt`, which implements a single data type (last-write-wins register). There is no library providing the standard catalog of conflict-free replicated data types — counters, sets, registers, maps, and sequences — that developers need for building distributed, collaborative, or offline-first applications.

### 1.2 Vision

Build a cross-platform CRDT library for Gleam that provides the standard catalog of state-based, operation-based, and delta-state CRDTs as composable, type-safe building blocks. The library should feel native to Gleam's functional style, leverage its type system for correctness guarantees, and work identically on Erlang and JavaScript targets.

The name **lattice** reflects the mathematical foundation of CRDTs: join-semilattices, where every pair of states has a well-defined least upper bound (merge).

### 1.3 Success Criteria

- Complete catalog of standard CRDT types (counters, sets, registers, maps)
- Works identically on Erlang and JavaScript targets
- Correct merge semantics verified by property-based tests
- Composable types (e.g., map values can be any CRDT)
- Zero runtime dependencies beyond `gleam_stdlib`
- Clear documentation with distributed systems context

---

## 2. Target Users

### 2.1 Primary Users

| User Type | Needs | Example Use Case |
|-----------|-------|------------------|
| **Application Developer** | Ready-made conflict-free data structures | Building an offline-first app with sync |
| **Library Author** | Composable primitives for higher-level abstractions | Building presence tracking (e.g., beryl) |
| **Distributed Systems Engineer** | Correct, well-tested merge semantics | State replication across BEAM nodes |
| **Frontend Developer** | Client-side CRDT state on JS target | Collaborative editing in a Lustre app |

### 2.2 User Stories

1. **As an application developer**, I want to use a counter that multiple nodes can increment concurrently without conflicts, so that I can build distributed counters (likes, views, inventory).

2. **As a library author**, I want composable CRDT primitives so that I can build presence tracking on top of observed-remove maps and registers.

3. **As a distributed systems engineer**, I want property-tested merge operations with proven convergence guarantees, so that I can trust state replication correctness.

4. **As a frontend developer**, I want CRDTs that work on the JavaScript target so that I can build collaborative features in browser-based Gleam apps.

5. **As a developer**, I want to serialize and deserialize CRDT state so that I can persist it or send it over the network for replication.

---

## 3. Goals and Non-Goals

### 3.1 Goals

| Priority | Goal |
|----------|------|
| **P0** | Cross-target support (Erlang + JavaScript) |
| **P0** | State-based (CvRDT) implementations of all core types |
| **P0** | Correct, commutative, associative, idempotent merge for every type |
| **P0** | Composable types (CRDTs as values in maps) |
| **P1** | Operation-based (CmRDT) variants for common types |
| **P1** | Delta-state CRDT support for efficient replication |
| **P1** | JSON serialization/deserialization |
| **P1** | Version vectors and causal context utilities |
| **P2** | Sequence/list CRDTs (RGA or similar) |
| **P2** | Text CRDT for collaborative editing |
| **P2** | Erlang distribution helpers (gossip, anti-entropy) |

### 3.2 Non-Goals

- **Networking / transport** — Lattice provides data structures, not replication protocols. Use with beryl, distributed Erlang, or custom transport.
- **Persistence / storage** — Serialization is in scope; database integration is not.
- **Conflict resolution UI** — Lattice resolves conflicts automatically; no user-facing merge UI.
- **Full Automerge clone** — Lattice focuses on individual CRDT primitives, not a document-level CRDT framework (though it could be a foundation for one).
- **Consensus / coordination** — CRDTs are coordination-free by design. Lattice does not implement Raft, Paxos, etc.

---

## 4. Functional Requirements

### 4.1 Core Abstraction: The Semilattice Interface

Every CRDT in Lattice conforms to a shared interface expressing the semilattice properties.

#### FR-1: CRDT Interface

Every CRDT type MUST provide these operations:

```gleam
/// Create a new instance for a given replica ID
new(replica_id: ReplicaId) -> t

/// Merge two states (commutative, associative, idempotent)
merge(a: t, b: t) -> t

/// Query the current value
value(crdt: t) -> v
```

The `merge` function MUST satisfy:
- **Commutativity:** `merge(a, b) == merge(b, a)`
- **Associativity:** `merge(merge(a, b), c) == merge(a, merge(b, c))`
- **Idempotency:** `merge(a, a) == a`

#### FR-2: Replica Identity

Replica IDs MUST be opaque, comparable values:

```gleam
/// A unique identifier for a replica/node
pub type ReplicaId {
  ReplicaId(String)
}
```

Replica IDs are required for types that track per-node state (counters, OR-sets) but not for types that don't (G-Set, LWW-Register with external timestamps).

### 4.2 Counters

#### FR-3: G-Counter (Grow-Only Counter)

A counter that can only be incremented.

```gleam
import lattice/counter/g_counter

let c = g_counter.new(ReplicaId("node1"))
let c = c |> g_counter.increment(1)
g_counter.value(c)  // => 1

// Merge from another replica
let c2 = g_counter.new(ReplicaId("node2"))
  |> g_counter.increment(5)
let merged = g_counter.merge(c, c2)
g_counter.value(merged)  // => 6
```

Internal representation: `Dict(ReplicaId, Int)` — each replica's contribution. Merge takes pairwise max.

#### FR-4: PN-Counter (Positive-Negative Counter)

A counter that supports both increment and decrement.

```gleam
import lattice/counter/pn_counter

let c = pn_counter.new(ReplicaId("node1"))
let c = c |> pn_counter.increment(10)
let c = c |> pn_counter.decrement(3)
pn_counter.value(c)  // => 7
```

Internal representation: pair of G-Counters (positive, negative). Value = P - N.

### 4.3 Registers

#### FR-5: LWW-Register (Last-Write-Wins Register)

A register that resolves conflicts by timestamp, keeping the most recent write.

```gleam
import lattice/register/lww_register

let r = lww_register.new("initial_value", timestamp: 1000)
let r = lww_register.set(r, "updated", timestamp: 2000)
lww_register.value(r)  // => "updated"

// Concurrent writes: higher timestamp wins
let r1 = lww_register.set(r, "from_node_a", timestamp: 3000)
let r2 = lww_register.set(r, "from_node_b", timestamp: 3001)
let merged = lww_register.merge(r1, r2)
lww_register.value(merged)  // => "from_node_b"
```

The register MUST be generic over its value type. Timestamps MUST be comparable (Int or custom clock).

#### FR-6: MV-Register (Multi-Value Register)

A register that preserves all concurrently written values, letting the application decide.

```gleam
import lattice/register/mv_register

let r = mv_register.new(ReplicaId("node1"))
let r = mv_register.set(r, "value_a")

// Concurrent writes on different replicas
let r2 = mv_register.new(ReplicaId("node2"))
let r2 = mv_register.set(r2, "value_b")

let merged = mv_register.merge(r, r2)
mv_register.value(merged)  // => ["value_a", "value_b"] (both preserved)

// Resolving: writing after merge clears concurrency
let resolved = mv_register.set(merged, "resolved")
mv_register.value(resolved)  // => ["resolved"]
```

Uses version vectors for causal tracking.

### 4.4 Sets

#### FR-7: G-Set (Grow-Only Set)

A set that supports add only. Elements can never be removed.

```gleam
import lattice/set/g_set

let s = g_set.new()
let s = s |> g_set.add("alice") |> g_set.add("bob")
g_set.contains(s, "alice")  // => True
g_set.value(s)  // => set.from_list(["alice", "bob"])

// Merge is set union
let merged = g_set.merge(s1, s2)
```

#### FR-8: 2P-Set (Two-Phase Set)

A set that supports add and remove, but removed elements can never be re-added.

```gleam
import lattice/set/two_phase_set

let s = two_phase_set.new()
let s = s |> two_phase_set.add("alice") |> two_phase_set.remove("alice")
two_phase_set.contains(s, "alice")  // => False
// two_phase_set.add(s, "alice") has no effect — "alice" is in the tombstone set
```

Internal representation: pair of G-Sets (added, removed). Value = added - removed.

#### FR-9: OR-Set (Observed-Remove Set / Add-Wins Set)

A set that supports add and remove with add-wins semantics on concurrent operations. Elements can be re-added after removal.

```gleam
import lattice/set/or_set

let s = or_set.new(ReplicaId("node1"))
let s = s |> or_set.add("alice")
let s = s |> or_set.remove("alice")
let s = s |> or_set.add("alice")  // Re-add works!
or_set.contains(s, "alice")  // => True

// Concurrent add + remove: add wins
let s1 = or_set.add(base, "bob")
let s2 = or_set.remove(base, "bob")
let merged = or_set.merge(s1, s2)
or_set.contains(merged, "bob")  // => True (add wins)
```

Uses unique tags (replica ID + logical clock) to track individual add operations. Remove only removes tags that the removing replica has observed.

### 4.5 Maps

#### FR-10: OR-Map (Observed-Remove Map)

A map whose keys can be added and removed (with add-wins semantics), and whose values are themselves CRDTs that merge automatically.

```gleam
import lattice/map/or_map
import lattice/counter/pn_counter

// Map from String keys to PN-Counter values
let m = or_map.new(ReplicaId("node1"))
let m = m |> or_map.update("likes", pn_counter.increment(_, 1))
let m = m |> or_map.update("likes", pn_counter.increment(_, 1))

or_map.get(m, "likes") |> pn_counter.value  // => 2

// Remove a key
let m = m |> or_map.remove("likes")

// Concurrent update + remove: update wins (add-wins)
```

#### FR-11: LWW-Map (Last-Write-Wins Element Map)

A simpler map using LWW-Register semantics for each key. More space-efficient than OR-Map for use cases that don't need add-wins behavior.

```gleam
import lattice/map/lww_map

let m = lww_map.new()
let m = m |> lww_map.set("name", "Alice", timestamp: 1000)
let m = m |> lww_map.set("name", "Bob", timestamp: 2000)
lww_map.get(m, "name")  // => Ok("Bob")
```

### 4.6 Causal Context Utilities

#### FR-12: Version Vector

A vector clock tracking causal history per replica.

```gleam
import lattice/clock/version_vector

let vv = version_vector.new()
let vv = vv |> version_vector.increment(ReplicaId("node1"))
let vv = vv |> version_vector.increment(ReplicaId("node1"))
version_vector.get(vv, ReplicaId("node1"))  // => 2

// Causal ordering
version_vector.compare(vv1, vv2)
// => Before | After | Concurrent | Equal
```

#### FR-13: Dot Context

A dot (replica, sequence number) context for tracking individual operations, used internally by OR-Set and OR-Map.

```gleam
import lattice/clock/dot_context

pub type Dot {
  Dot(replica: ReplicaId, counter: Int)
}
```

### 4.7 Serialization

#### FR-14: JSON Encoding/Decoding

Every CRDT type MUST provide JSON encoder/decoder functions:

```gleam
import lattice/counter/g_counter
import gleam/json

let encoded = g_counter.to_json(counter)
let decoded = g_counter.from_json(json_string)
```

The JSON format MUST be stable across versions for wire compatibility.

### 4.8 Delta-State Support

#### FR-15: Delta Mutations

For efficient replication, CRDT types SHOULD support producing and applying deltas:

```gleam
// Produce a delta for the last mutation
let #(updated_counter, delta) = g_counter.increment_delta(counter, 1)

// Apply delta on remote replica (smaller than full state)
let remote = g_counter.apply_delta(remote, delta)
```

Delta-state support allows sending only changes rather than full state, critical for bandwidth-constrained scenarios.

---

## 5. Non-Functional Requirements

### 5.1 Performance

| Metric | Requirement |
|--------|-------------|
| G-Counter merge (100 replicas) | < 50μs |
| OR-Set add (1000 elements) | < 10μs |
| OR-Set merge (1000 elements each) | < 5ms |
| G-Set merge (10,000 elements) | < 10ms |
| Memory: G-Counter per replica | O(n) where n = replica count |
| Memory: OR-Set per element | O(1) amortized with compaction |

### 5.2 Correctness

- Every CRDT type MUST have property-based tests verifying merge commutativity, associativity, and idempotency
- OR-Set MUST pass add-wins concurrency tests
- 2P-Set MUST enforce tombstone permanence
- Counters MUST never lose increments across merges
- All types MUST converge: after exchanging all states, all replicas MUST have identical query results

### 5.3 Compatibility

| Requirement | Details |
|-------------|---------|
| Gleam version | >= 1.0 |
| Erlang/OTP | >= 26 |
| Node.js | >= 18 |
| Deno | >= 1.40 |
| Bun | >= 1.0 |

### 5.4 Dependencies

Minimize external dependencies:

- `gleam_stdlib` — Required (Dict, Set, List, Option, Order)
- `gleam_json` — For JSON serialization (optional, behind feature flag or separate package)

No other dependencies. Counters, sets, registers, maps, and clocks are all implementable with `gleam_stdlib` primitives.

---

## 6. API Design Principles

### 6.1 Progressive Disclosure

```gleam
// Level 1: Simple counter
let c = g_counter.new(ReplicaId("node1"))
let c = g_counter.increment(c, 1)

// Level 2: Merge replicas
let merged = g_counter.merge(c1, c2)

// Level 3: Compose types
let m = or_map.new(ReplicaId("node1"))
let m = or_map.update(m, "score", pn_counter.increment(_, 1))

// Level 4: Delta-state replication
let #(c, delta) = g_counter.increment_delta(c, 1)
let remote = g_counter.apply_delta(remote, delta)
```

### 6.2 Type Safety Over Convenience

- Replica IDs are opaque types, not bare strings
- Timestamps are explicit parameters, never implicit wall-clock reads
- Merge operations are type-safe — you cannot merge a G-Counter with a PN-Counter
- OR-Set/OR-Map operations that require replica identity take `ReplicaId` explicitly

### 6.3 Composition Over Inheritance

CRDTs compose via nesting rather than via shared behavior/trait abstractions. An OR-Map of PN-Counters is expressed as a concrete type, not via dynamic dispatch:

```gleam
// Explicit composition, not abstract CRDT interface
or_map.update(m, "likes", fn(counter) { pn_counter.increment(counter, 1) })
```

### 6.4 Functional Purity

- All CRDT operations return new values (no mutation)
- No hidden global state
- No implicit timestamp generation — the caller provides clocks
- Deterministic: same inputs always produce same outputs

### 6.5 Cross-Platform by Default

- All types work on both Erlang and JavaScript targets
- No target-specific FFI in core types
- Implementation uses only `gleam_stdlib` data structures (Dict, Set, List)

---

## 7. Module Structure

```
src/
├── lattice.gleam                  # Re-exports and top-level docs
├── lattice/
│   ├── replica.gleam              # ReplicaId type
│   ├── counter/
│   │   ├── g_counter.gleam        # Grow-only counter
│   │   └── pn_counter.gleam       # Positive-negative counter
│   ├── register/
│   │   ├── lww_register.gleam     # Last-write-wins register
│   │   └── mv_register.gleam      # Multi-value register
│   ├── set/
│   │   ├── g_set.gleam            # Grow-only set
│   │   ├── two_phase_set.gleam    # Two-phase set
│   │   └── or_set.gleam           # Observed-remove set
│   ├── map/
│   │   ├── lww_map.gleam          # LWW-element map
│   │   └── or_map.gleam           # Observed-remove map
│   ├── clock/
│   │   ├── version_vector.gleam   # Version vector
│   │   └── dot_context.gleam      # Dot context for causal tracking
│   └── json/
│       ├── encode.gleam           # JSON encoders for all types
│       └── decode.gleam           # JSON decoders for all types
```

---

## 8. Open Questions

### 8.1 OR-Set Implementation Strategy

| Option | Approach | Trade-offs |
|--------|----------|------------|
| **A** | Unique-tag based (classic) | Simple, but metadata grows with operations |
| **B** | Dot-kernel / optimized (ORSWOT) | More compact, but complex implementation |
| **C** | Start with A, optimize to B in Phase 2 | Pragmatic, but API may need to change |

**Recommendation:** Option C — ship the simple version first, optimize with ORSWOT-style compaction later. Keep the public API stable across both.

### 8.2 Generic CRDT Composition for OR-Map

How should OR-Map accept arbitrary CRDT value types?

| Option | Approach | Trade-offs |
|--------|----------|------------|
| **A** | Records of functions (merge, default) passed at creation | Flexible, but verbose |
| **B** | Separate OR-Map modules per value type | Type-safe, but boilerplate |
| **C** | Higher-kinded type emulation via callbacks | Gleam-idiomatic, composable |

**Recommendation:** Option A — pass a "CRDT spec" record containing `new`, `merge` functions. This is the most Gleam-idiomatic approach:

```gleam
pub type CrdtSpec(a) {
  CrdtSpec(
    empty: a,
    merge: fn(a, a) -> a,
  )
}

let counter_map = or_map.new(
  ReplicaId("node1"),
  CrdtSpec(empty: pn_counter.new(rid), merge: pn_counter.merge),
)
```

### 8.3 Timestamp Strategy for LWW Types

| Option | Approach | Trade-offs |
|--------|----------|------------|
| **A** | Int timestamps (caller provides) | Pure, portable, caller controls clock |
| **B** | Wall-clock with platform FFI | Convenient, but impure and clock-skew risk |
| **C** | Hybrid Logical Clocks (HLC) | Best correctness, more complex |

**Recommendation:** Option A for Phase 1 (keep it pure), with HLC utilities in Phase 3.

### 8.4 Separate JSON Package?

| Option | Approach | Trade-offs |
|--------|----------|------------|
| **A** | JSON support in main package | Convenient, adds `gleam_json` dependency |
| **B** | Separate `lattice_json` package | Core stays dependency-free |

**Recommendation:** Option B — keep the core package dependency-free. Provide `lattice_json` as a companion.

### 8.5 Sequence/Text CRDTs

Sequence CRDTs (RGA, Logoot, LSEQ) and text CRDTs (Yjs-style, Peritext) are significantly more complex than the basic types. Should they be in-scope?

**Recommendation:** Defer to Phase 3 or a separate package (`lattice_text`). Focus on getting counters, registers, sets, and maps right first.

---

## 9. Implementation Phases

### Phase 1: Core Types (MVP)

- [ ] `ReplicaId` type
- [ ] `GCounter` — new, increment, value, merge
- [ ] `PNCounter` — new, increment, decrement, value, merge
- [ ] `GSet` — new, add, contains, value, merge
- [ ] `TwoPhaseSet` — new, add, remove, contains, value, merge
- [ ] `LWWRegister` — new, set, value, merge
- [ ] `VersionVector` — new, increment, get, compare, merge
- [ ] Property-based tests for all merge laws
- [ ] Works on Erlang and JavaScript targets

**Deliverable:** Usable CRDT primitives for basic distributed state

### Phase 2: Advanced Types

- [ ] `ORSet` — add, remove, contains, value, merge (add-wins)
- [ ] `MVRegister` — set, value, merge (preserves concurrent values)
- [ ] `LWWMap` — set, get, remove, keys, value, merge
- [ ] `ORMap` — update, get, remove, keys, merge (with CrdtSpec composition)
- [ ] `DotContext` — causal tracking for OR types
- [ ] JSON serialization (`lattice_json` companion package)

**Deliverable:** Full CRDT toolkit for production distributed applications

### Phase 3: Optimization & Extensions

- [ ] Delta-state support for all types
- [ ] ORSWOT-optimized OR-Set (dot-kernel compaction)
- [ ] Hybrid Logical Clock utility
- [ ] Sequence CRDT (RGA or similar)
- [ ] Benchmarks and performance optimization
- [ ] Optional Erlang distribution helpers (gossip protocol utilities)

**Deliverable:** Performance-optimized library with advanced types

---

## 10. Testing Strategy

### 10.1 Property-Based Tests (Critical)

Every CRDT type MUST have property tests for:

- **Merge commutativity:** `merge(a, b) == merge(b, a)` for arbitrary states
- **Merge associativity:** `merge(merge(a, b), c) == merge(a, merge(b, c))`
- **Merge idempotency:** `merge(a, a) == a`
- **Convergence:** After all-to-all state exchange, all replicas produce identical query results
- **Monotonicity:** The lattice ordering never decreases after merge

### 10.2 Semantic Tests

- G-Counter: increments from multiple replicas sum correctly
- PN-Counter: value equals total increments minus total decrements
- G-Set: union semantics, no element loss
- 2P-Set: removed elements cannot be re-added
- OR-Set: concurrent add + remove → add wins
- OR-Set: sequential remove + add → element present
- LWW-Register: higher timestamp always wins
- MV-Register: concurrent writes preserved, resolved by subsequent write
- OR-Map: concurrent key update + remove → update wins

### 10.3 Serialization Round-Trip Tests

- Encode → decode produces identical CRDT state
- Cross-target: state encoded on Erlang can be decoded on JS and vice versa
- Schema stability: format does not change between minor versions

### 10.4 Cross-Target Tests

- All tests pass on both Erlang and JavaScript targets
- `gleam test --target erlang && gleam test --target javascript`

---

## 11. Documentation Plan

### 11.1 README

- What are CRDTs? (2-paragraph primer)
- Quick start: counter in 5 lines
- Type catalog with one-line descriptions
- When to use which type (decision table)

### 11.2 Hexdocs

- Complete API docs for every module
- Module-level guides explaining the CRDT type, its semantics, and trade-offs
- Merge semantics visualized with before/after examples

### 11.3 Guides

- "Introduction to CRDTs in Gleam"
- "Choosing the Right CRDT Type"
- "Building a Collaborative Feature with Lattice"
- "Replicating State Across BEAM Nodes"
- "Using Lattice with Beryl for Presence Tracking"

---

## 12. Success Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Adoption | 300+ downloads in first month | Hex.pm stats |
| Correctness | Zero merge-related bugs | GitHub issues + property tests |
| Coverage | 100% of merge paths covered | Property test coverage |
| Compatibility | Zero cross-target issues | CI on both targets |
| Composability | OR-Map works with all value CRDTs | Integration tests |

---

## Appendix A: CRDT Type Catalog

| Type | Category | Operations | Conflict Resolution | Use Case |
|------|----------|-----------|---------------------|----------|
| **G-Counter** | Counter | increment | Pairwise max | View counts, likes |
| **PN-Counter** | Counter | increment, decrement | Pairwise max (P and N) | Inventory, bidirectional counts |
| **LWW-Register** | Register | set | Highest timestamp wins | User profile fields |
| **MV-Register** | Register | set | Preserve all concurrent values | Shopping cart quantities |
| **G-Set** | Set | add | Set union | Seen message IDs, vote tracking |
| **2P-Set** | Set | add, remove (once) | Union of add/remove sets | Simple membership with removal |
| **OR-Set** | Set | add, remove (re-add OK) | Add wins on concurrent conflict | Tags, labels, active users |
| **LWW-Map** | Map | set, remove | Per-key LWW | User preferences, config |
| **OR-Map** | Map | update, remove | Add-wins keys, CRDT-merge values | Complex nested state |

## Appendix B: Comparison with Existing Solutions

| Feature | lww-register-crdt | Lattice |
|---------|-------------------|---------|
| Erlang target | ✅ | ✅ |
| JavaScript target | ? | ✅ |
| G-Counter | ❌ | ✅ |
| PN-Counter | ❌ | ✅ |
| LWW-Register | ✅ | ✅ |
| MV-Register | ❌ | ✅ |
| G-Set | ❌ | ✅ |
| 2P-Set | ❌ | ✅ |
| OR-Set | ❌ | ✅ |
| OR-Map | ❌ | ✅ |
| Version Vectors | ❌ | ✅ |
| Delta-state support | ❌ | ✅ (Phase 3) |
| JSON serialization | ❌ | ✅ (companion pkg) |
| Property-based tests | ❌ | ✅ |
| Composable types | ❌ | ✅ |

## Appendix C: Example Usage

### Distributed Counter

```gleam
import lattice/counter/g_counter
import lattice/replica.{ReplicaId}

pub fn main() {
  // Node 1 increments
  let c1 = g_counter.new(ReplicaId("node1"))
    |> g_counter.increment(5)

  // Node 2 increments independently
  let c2 = g_counter.new(ReplicaId("node2"))
    |> g_counter.increment(3)

  // After state exchange, both merge
  let merged = g_counter.merge(c1, c2)
  g_counter.value(merged)  // => 8
}
```

### Collaborative Tags with OR-Set

```gleam
import lattice/set/or_set
import lattice/replica.{ReplicaId}

pub fn handle_tag_sync(local: ORSet(String), remote: ORSet(String)) {
  let merged = or_set.merge(local, remote)
  // If Alice added "urgent" while Bob removed "urgent",
  // add-wins: "urgent" is present in merged
  or_set.to_list(merged)
}
```

### Nested State with OR-Map

```gleam
import lattice/map/or_map
import lattice/counter/pn_counter
import lattice/replica.{ReplicaId}

pub fn shopping_cart_example() {
  let rid = ReplicaId("client1")
  let spec = or_map.CrdtSpec(
    empty: pn_counter.new(rid),
    merge: pn_counter.merge,
  )

  let cart = or_map.new(rid, spec)
  let cart = cart
    |> or_map.update("apples", pn_counter.increment(_, 3))
    |> or_map.update("bananas", pn_counter.increment(_, 2))
    |> or_map.update("apples", pn_counter.decrement(_, 1))

  // apples: 2, bananas: 2
  or_map.get(cart, "apples") |> pn_counter.value  // => 2
}
```

### Presence Tracking (Beryl Integration)

```gleam
import lattice/map/or_map
import lattice/register/lww_register
import lattice/replica.{ReplicaId}

/// Track online users with metadata (status, last_seen)
pub fn presence_example() {
  let node = ReplicaId("web1")
  let spec = or_map.CrdtSpec(
    empty: lww_register.new("", timestamp: 0),
    merge: lww_register.merge,
  )

  let presence = or_map.new(node, spec)
  let presence = presence
    |> or_map.update("user:alice", fn(_) {
      lww_register.new("online", timestamp: now())
    })

  // When Alice disconnects on another node, merge resolves via LWW
}
```
