# Project Research Summary

**Project:** Lattice — CRDT Library for Gleam
**Domain:** CRDT (Conflict-free Replicated Data Type) Library
**Researched:** 2026-02-28
**Confidence:** HIGH

## Executive Summary

Lattice is a Gleam library providing CRDT implementations for the Erlang and JavaScript targets. CRDTs are data structures that guarantee eventual consistency across distributed systems without coordination—critical for collaborative applications, offline-first apps, and distributed databases. Research confirms this is a genuine gap in the Gleam ecosystem (only lpil's LWW-Register exists).

The recommended approach implements state-based (CvRDT) CRDTs as pure Gleam modules, enabling cross-target compatibility. Property-based testing with qcheck is essential—Ditto's research found bugs in academic papers through property testing. The stack is straightforward: Gleam 1.14.0, gleam_stdlib, gleam_json (companion package), gleeunit, and qcheck.

Key risks center on merge law violations causing convergence failures. Every CRDT type must satisfy commutativity, associativity, and idempotency. OR-Set semantics (concurrent add wins) are counterintuitive and require careful documentation. Tombstone accumulation will cause unbounded memory growth without GC mechanisms.

## Key Findings

### Recommended Stack

Gleam 1.14.0 with gleam_stdlib provides the foundation. The companion serialization package uses gleam_json (v3.0.2, Apache-2.0). Testing requires gleeunit plus qcheck for property-based verification—critical for CRDT correctness.

**Core technologies:**
- **Gleam 1.14.0:** Project-pinned, compiles to Erlang and JavaScript natively, zero-cost abstractions ideal for CRDTs
- **gleam_stdlib:** Dict, List, Set, Result, Option types—no runtime dependencies
- **gleam_json:** Companion package per project requirements; most downloaded JSON library
- **qcheck:** Property-based testing with shrinking—CRITICAL for verifying merge laws (commutativity, associativity, idempotency, convergence)
- **@external attribute:** For target-specific implementations (Erlang distribution, performance optimizations)

### Expected Features

**Must have (table stakes):**
- **G-Counter / PN-Counter** — Foundation counters for metrics, votes
- **G-Set / 2P-Set / OR-Set** — THE critical set type; OR-Set allows re-adding after removal
- **LWW-Register / MV-Register** — Single value containers with last-writer-wins or multi-value conflict preservation
- **LWW-Map** — Key-value map with per-key timestamps
- **Version Vector** — Essential causal tracking for OR-Set, OR-Map
- **JSON Serialization** — Cross-system interoperability
- **Property-based Tests** — Verify merge laws for all types

**Should have (competitive):**
- **OR-Map** — Nested CRDT values in maps (compose counters, sets)
- **Delta-CRDT Support** — Efficient state transfer for replication
- **Causal Context Utilities** — Efficient metadata tracking

**Defer (v2+):**
- **Text CRDT (RGA)** — Collaborative text editing is VERY HIGH complexity
- **Sequence/List CRDT** — Foundation for text
- **Erlang Distribution Helpers** — Only with significant demand

### Architecture Approach

State-based (CvRDT) CRDTs are the default—simpler to reason about, easier to verify merge properties. Each CRDT type in its own module following Gleam conventions. The recommended project structure uses `lattice/` submodules grouped by category: `counter.gleam`, `register.gleam`, `set/`, `map/`, `version_vector.gleam`.

Composite CRDTs (OR-Map) use lattice inflation—map values are themselves CRDTs; map merge propagates to nested values.

**Major components:**
1. **Primitive CRDTs** — Individual types (Counter, Register, Set) with new(), update(), merge(), value() functions
2. **Version Vector** — Causal history tracking per replica; foundation for OR-Set
3. **Merge Engine** — Pure functions verifying C-A-I properties
4. **Serialization Layer** — JSON encoder/decoder (companion package)

### Critical Pitfalls

1. **Merge Law Violations** — CRDTs only converge if merge is commutative, associative, idempotent. Property-based tests are non-negotiable.
2. **OR-Set Concurrent Add Wins** — Counterintuitive: concurrent add+remove results in add winning. Document clearly.
3. **LWW-Register Timestamp Tiebreaker** — Equal timestamps must use replica ID as tiebreaker; otherwise breaks commutativity.
4. **Tombstone Accumulation** — OR-Set/OR-Map accumulate tombstones indefinitely. Plan GC from design phase.
5. **Version Vector Comparison Errors** — `{A:2, B:1}` vs `{A:1, B:2}` are concurrent, not comparable. Many implementations get this wrong.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Foundation & Primitives
**Rationale:** Version vector is required infrastructure; counter validates build/test pipeline
**Delivers:** Build system, testing infrastructure, Version Vector, G-Counter, PN-Counter
**Implements:** counter.gleam, version_vector.gleam with property tests
**Avoids:** Starting with complex types before verifying the system works

### Phase 2: Registers & Simple Sets
**Rationale:** Low complexity types that validate merge semantics
**Delivers:** LWW-Register, MV-Register, G-Set, 2P-Set
**Implements:** register.gleam, set/g_set.gleam, set/two_p_set.gleam
**Avoids:** LWW timestamp tiebreaker pitfalls through explicit test cases

### Phase 3: OR-Set (Critical)
**Rationale:** THE critical type; requires Version Vector infrastructure; complex semantics
**Delivers:** OR-Set implementation with full test coverage
**Implements:** set/or_set.gleam with concurrent add/remove/re-add scenarios
**Avoids:** OR-Set add-wins confusion through documentation and test cases

### Phase 4: Maps & Serialization
**Rationale:** Combines primitives; serialization depends on all types being stable
**Delivers:** LWW-Map, OR-Map, JSON serialization companion package
**Implements:** map/crdt_map.gleam, serialization utilities
**Avoids:** Cross-platform serialization mismatch through canonical JSON format

### Phase 5: Advanced Features
**Rationale:** Only after core is validated; high complexity
**Delivers:** Delta-CRDT support, RGA (if demand exists), Erlang distribution helpers
**Implements:** Optimizations and advanced types
**Avoids:** Premature optimization before product-market fit

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 3 (OR-Set):** Complex integration, needs API design research—tags, causal context handling
- **Phase 5 (RGA):** Niche domain, sparse documentation on sequence CRDTs in Gleam

Phases with standard patterns (skip research-phase):
- **Phase 1-2:** Well-documented CRDT patterns from riak_dt, rust-crdt
- **Phase 4:** Serialization follows gleam_json patterns

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Project-pinned Gleam version; established Gleam ecosystem libraries |
| Features | HIGH | Comprehensive analysis from rust-crdt, Yjs, Loro competitors |
| Architecture | HIGH | Based on riak_dt, delta_crdt_ex, Automerge patterns |
| Pitfalls | HIGH | Academic sources + Ditto's practical testing findings |

**Overall confidence:** HIGH

### Gaps to Address

- **Delta-CRDT patterns in Gleam:** Limited examples; may need research-phase during Phase 5
- **RGA implementation:** Few Gleam-specific resources; will need Elixir/Rust porting
- **Property test generators:** qcheck generators for CRDT-specific data need validation during Phase 1

## Sources

### Primary (HIGH confidence)
- **gleam_stdlib, gleam_json, gleeunit, qcheck** — Hex.pm package documentation (v0.69.0, v3.0.2, v1.9.0, v1.0.4)
- **riak_dt** — Original Erlang CRDT library; composable Map pattern source
- **rust-crdt** — Apache-2.0 licensed, most downloaded Rust CRDT library
- **delta_crdt_ex** — Delta CRDT implementation in Elixir

### Secondary (MEDIUM confidence)
- **Yjs (21k+ stars)** — De facto JS CRDT standard
- **Loro** — High-performance Rust/JS CRDT with text focus
- **Ditto blog** — "Testing CRDTs in Rust, from theory to practice" — Property testing findings

### Tertiary (LOW confidence)
- **RGA/Logoot academic papers** — Limited Gleam-specific implementation guidance
- **Akka OR-Set issues** — Known tombstone accumulation issues, needs Gleam adaptation

---
*Research completed: 2026-02-28*
*Ready for roadmap: yes*
