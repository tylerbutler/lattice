# Lattice — CRDT Library for Gleam

## What This Is

A cross-platform CRDT (Conflict-free Replicated Data Type) library for Gleam providing 10 data types (counters, registers, sets, maps), a Crdt union type for generic dispatch, JSON serialization for all types, and comprehensive property-based test coverage (228 tests). Works on Erlang and JavaScript targets.

## Core Value

A comprehensive CRDT library for Gleam with correct merge semantics verified by property-based tests, providing developers with battle-tested data structures for building distributed, collaborative, or offline-first applications.

## Current Milestone: v1.1 Production Ready

**Goal:** Polish, document, test on JS target, and publish lattice to Hex.pm.

**Target features:**
- Full JavaScript target testing (all 228+ tests pass on both Erlang and JS)
- Documentation (/// doc comments on all public functions, hexdocs generation, usage examples)
- API polish (review public surface for consistency, naming, ergonomics)
- Hex.pm publishing (finalize metadata, README, license)

## Current State

**Shipped:** v1.0 (2026-03-01)
**Source:** 1,402 LOC across 12 modules
**Tests:** 3,338 LOC across 25 test files (228 tests)

### CRDT Types Delivered
- **Counters:** G-Counter, PN-Counter
- **Registers:** LWW-Register, MV-Register
- **Sets:** G-Set, 2P-Set, OR-Set (add-wins)
- **Maps:** LWW-Map (tombstone remove), OR-Map (nested CRDTs)
- **Clocks:** Version Vector, Dot Context
- **Infrastructure:** Crdt tagged union with generic merge/JSON dispatch

### Property Test Coverage
- Merge laws: commutativity, associativity, idempotency for all types
- Bottom identity: merge(a, new()) == a for all 9 main types
- Monotonicity: values non-decreasing after merges
- Convergence: 3-replica all-to-all exchange
- OR-Set concurrent add-wins edge cases
- 2P-Set tombstone permanence
- JSON round-trip for all types

## Requirements

### Validated

- ✓ State-based (CvRDT) implementations of all core types — v1.0
- ✓ Correct, commutative, associative, idempotent merge for every type — v1.0
- ✓ Composable types (CRDTs as values in maps) — v1.0 (OR-Map with Crdt union)
- ✓ JSON serialization/deserialization — v1.0 (self-describing format with type tag + version)
- ✓ Version vectors and causal context utilities — v1.0

### Active

- [ ] Cross-target support (Erlang + JavaScript) — smoke tests done, full JS target testing needed
- [ ] Operation-based (CmRDT) variants for common types
- [ ] Delta-state CRDT support for efficient replication
- [ ] Sequence/list CRDTs (RGA or similar)
- [ ] Text CRDT for collaborative editing
- [ ] Erlang distribution helpers (gossip, anti-entropy)

### Out of Scope

- Networking / transport — Lattice provides data structures, not replication protocols
- Persistence / storage — Serialization is in scope; database integration is not
- Conflict resolution UI — Lattice resolves conflicts automatically
- Full Automerge clone — Focus on individual CRDT primitives, not document-level framework
- Consensus / coordination — CRDTs are coordination-free by design
- Binary serialization — JSON sufficient for v1; binary format deferred

## Context

- Gleam project targeting Erlang (BEAM) and JavaScript
- No comprehensive CRDT library exists in Gleam ecosystem
- Users: Application developers, library authors, distributed systems engineers
- Runtime dependencies: gleam_stdlib, gleam_json
- Dev dependencies: startest (test runner), qcheck (property-based testing)

## Constraints

- **Gleam Version**: >= 1.7.0
- **Erlang/OTP**: >= 26
- **Node.js**: >= 18
- **Dependencies**: gleam_stdlib + gleam_json (JSON moved to same package in v1.0)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Pure functional design | Deterministic merge behavior, easier testing | ✓ Good |
| Explicit timestamps for LWW types | Avoid impure wall-clock reads, caller controls clock | ✓ Good |
| OR-Set unique-tag based | Simple, correct; ORSWOT optimization deferred | ✓ Good |
| JSON in same package (not companion) | Simpler API, gleam_json is lightweight | ✓ Good |
| Crdt tagged union for OR-Map values | Serves double duty: generic JSON decoder + OR-Map storage | ✓ Good |
| Type parameters fixed to String in v1 | Gleam type system necessity for union enum | ⚠️ Revisit for v2 |
| LWW-Map tombstone remove | Dict(String, #(Option(String), Int)) prevents resurrection bug | ✓ Good |
| startest over gleeunit | Better test runner with describe/it and expect matchers | ✓ Good |
| TDD approach throughout | Property tests caught real MV-Register idempotency bug | ✓ Good |
| qcheck small_test_config | test_count: 10, seed: 42 prevents timeout issues | ✓ Good |

---
*Last updated: 2026-03-01 after v1.1 milestone start*
