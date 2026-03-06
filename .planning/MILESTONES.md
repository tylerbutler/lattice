# Milestones

## v1.1 Production Ready (Shipped: 2026-03-06)

**Phases completed:** 3 phases, 7 plans
**Timeline:** 2026-03-01 → 2026-03-05 | **Commits:** 29
**Files modified:** 47 (+4,449 / -915)

**Key accomplishments:**
- All 228 tests verified passing on JavaScript target with zero failures
- CI enforces dual-target (Erlang + JS) testing on every push via separate parallel jobs
- All 12 CRDT modules documented with /// doc comments, module-level docs, and consistent API ordering
- Opaque types applied for encapsulation (Tag, DotContext, VersionVector, MVRegister)
- Package metadata, README with CRDT type catalog, and CHANGELOG prepared for Hex.pm
- Pre-publish verification passed (build, tests, docs all clean on both targets)

### Known Gaps
- **PUB-04**: Package not yet published to Hex.pm — awaiting user action (`gleam publish` or CI tag)

**Archive:** `.planning/milestones/v1.1-ROADMAP.md`, `.planning/milestones/v1.1-REQUIREMENTS.md`

---

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

