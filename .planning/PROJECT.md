# Lattice — CRDT Library for Gleam

## What This Is

A cross-platform CRDT (Conflict-free Replicated Data Type) library for Gleam providing 10 data types (counters, registers, sets, maps), a Crdt union type for generic dispatch, JSON serialization for all types, and comprehensive property-based test coverage (228 tests). Works on both Erlang and JavaScript targets with full documentation and consistent API design.

## Core Value

A comprehensive CRDT library for Gleam with correct merge semantics verified by property-based tests, providing developers with battle-tested data structures for building distributed, collaborative, or offline-first applications.

## Latest Milestone: v1.1 Production Ready (shipped 2026-03-06)

**Delivered:** Cross-target testing, full documentation, API polish, and Hex.pm publish preparation.

**What shipped:**
- JavaScript target: all 228 tests pass, CI enforces dual-target
- Documentation: all 12 modules with /// doc comments, module-level docs, clean hexdocs
- API polish: opaque types, consistent naming, function ordering
- Publishing: gleam.toml metadata, README with type catalog, CHANGELOG via changie

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
- ✓ Cross-target support (Erlang + JavaScript) — v1.1 (228 tests, dual-target CI)
- ✓ Full API documentation with doc comments — v1.1 (all 12 modules)
- ✓ Consistent API design with opaque types — v1.1
- ✓ Package metadata and README for Hex.pm — v1.1

### Active

- [ ] Operation-based (CmRDT) variants for common types
- [ ] Delta-state CRDT support for efficient replication
- [ ] Sequence/list CRDTs (RGA or similar)
- [ ] Text CRDT for collaborative editing
- [ ] Erlang distribution helpers (gossip, anti-entropy)
- [ ] Convenience functions (size/is_empty for sets and maps)

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
- Shipped v1.0 (2026-03-01): 10 CRDT types, 228 tests, 1,402 LOC
- Shipped v1.1 (2026-03-06): JS target, docs, API polish, publish-ready

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
| Explicit CI jobs over matrix | Different setup for Erlang/JS; matrix obscures | ✓ Good |
| Opaque types for internals | Tag, DotContext, VersionVector, MVRegister hidden | ✓ Good |
| GCounter/PNCounter remain pub | pn_counter destructures GCounter for serialization | ✓ Good |
| Crdt/CrdtSpec remain pub | or_map pattern-matches on CrdtSpec variants | ✓ Good |
| API-03 gaps deferred | size/is_empty need tests; out of scope for v1.1 | — Pending |
| TOML array-of-tables for links | gleam.toml requires [[links]] not [links] | ✓ Good |

---
*Last updated: 2026-03-06 after v1.1 milestone*
