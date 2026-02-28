# Lattice — CRDT Library for Gleam

## What This Is

A cross-platform CRDT (Conflict-free Replicated Data Type) library for Gleam that provides the standard catalog of counters, registers, sets, and maps as composable, type-safe building blocks. Works identically on Erlang and JavaScript targets. The name reflects the mathematical foundation: join-semilattices, where every pair of states has a well-defined least upper bound (merge).

## Core Value

A comprehensive CRDT library for Gleam with correct merge semantics verified by property-based tests, providing developers with battle-tested data structures for building distributed, collaborative, or offline-first applications.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Cross-target support (Erlang + JavaScript)
- [ ] State-based (CvRDT) implementations of all core types
- [ ] Correct, commutative, associative, idempotent merge for every type
- [ ] Composable types (CRDTs as values in maps)
- [ ] Operation-based (CmRDT) variants for common types
- [ ] Delta-state CRDT support for efficient replication
- [ ] JSON serialization/deserialization
- [ ] Version vectors and causal context utilities
- [ ] Sequence/list CRDTs (RGA or similar)
- [ ] Text CRDT for collaborative editing
- [ ] Erlang distribution helpers (gossip, anti-entropy)

### Out of Scope

- Networking / transport — Lattice provides data structures, not replication protocols
- Persistence / storage — Serialization is in scope; database integration is not
- Conflict resolution UI — Lattice resolves conflicts automatically
- Full Automerge clone — Focus on individual CRDT primitives, not document-level framework
- Consensus / coordination — CRDTs are coordination-free by design

## Context

- Existing Gleam project with src/ and test/ directories
- Target platforms: Erlang (BEAM) and JavaScript
- Existing similar package: lpil's `lww-register-crdt` (single data type only)
- No comprehensive CRDT library exists in Gleam ecosystem
- Users: Application developers, library authors, distributed systems engineers, frontend developers

## Constraints

- **Gleam Version**: >= 1.0
- **Erlang/OTP**: >= 26
- **Node.js**: >= 18
- **Dependencies**: Zero runtime dependencies beyond gleam_stdlib (JSON support as companion package)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Pure functional design | Deterministic merge behavior, easier testing | — Pending |
| Explicit timestamps for LWW types | Avoid impure wall-clock reads, caller controls clock | — Pending |
| OR-Set implementation | Start with unique-tag based, optimize to ORSWOT later | — Pending |
| JSON as companion package | Keep core dependency-free | — Pending |

---
*Last updated: 2026-02-28 after initialization*
