# Milestones

## v1.0 CRDT Library (Shipped: 2026-03-01)

**Phases completed:** 4 phases, 14 plans
**Source:** 1,402 LOC (12 modules) | **Tests:** 3,338 LOC (25 files, 228 tests)
**Timeline:** 2026-02-28 → 2026-03-01 | **Commits:** 67

**Key accomplishments:**
- Implemented 10 CRDT types: G-Counter, PN-Counter, LWW-Register, MV-Register, G-Set, 2P-Set, OR-Set, LWW-Map, OR-Map, Version Vector + Dot Context
- Created Crdt tagged union with generic merge dispatch and JSON serialization
- Self-describing JSON format with type tag and version field for all types
- Comprehensive property-based test coverage: merge laws, bottom identity, monotonicity, convergence
- TDD approach throughout — caught real MV-Register idempotency bug via property tests
- OR-Map with add-wins semantics using Crdt union for nested values

**Archive:** `.planning/milestones/v1.0-ROADMAP.md`, `.planning/milestones/v1.0-REQUIREMENTS.md`

---

