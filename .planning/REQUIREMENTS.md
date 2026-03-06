# Requirements: Lattice — CRDT Library for Gleam

**Defined:** 2026-03-01
**Core Value:** A comprehensive CRDT library for Gleam with correct merge semantics verified by property-based tests, providing developers with battle-tested data structures for building distributed, collaborative, or offline-first applications.

## v1.1 Requirements

Requirements for production-ready release. Each maps to roadmap phases.

### Cross-Target

- [x] **TARGET-01**: All existing tests pass with `gleam test --target javascript`
- [x] **TARGET-02**: Fix any JS-specific failures (if discovered)
- [x] **TARGET-03**: CI workflow runs tests on both Erlang and JavaScript targets

### Documentation

- [x] **DOCS-01**: All public functions have `///` doc comments with descriptions
- [x] **DOCS-02**: All public types have `///` doc comments
- [x] **DOCS-03**: Usage examples in module-level documentation
- [x] **DOCS-04**: `gleam docs build` generates clean hexdocs without warnings

### API Polish

- [x] **API-01**: Review all public function signatures for consistency (naming, argument order)
- [x] **API-02**: Ensure opaque types where internal structure should be hidden
- [x] **API-03**: Add missing convenience functions if any obvious gaps exist

### Publishing

- [x] **PUB-01**: gleam.toml metadata complete (name, description, repository, licenses)
- [x] **PUB-02**: README.md with installation, quickstart, and type overview
- [x] **PUB-03**: CHANGELOG.md or equivalent for v1.0 → v1.1
- [ ] **PUB-04**: Package published to Hex.pm via `gleam publish`

## Future Requirements

Deferred to future releases.

### Advanced Types
- **DELTA-01**: Delta-CRDT support for G-Counter
- **DELTA-02**: Delta-CRDT support for PN-Counter
- **DELTA-03**: Delta-CRDT support for OR-Set
- **DELTA-04**: Delta-CRDT support for OR-Map

### Sequence Types
- **SEQ-01**: RGA (Replicated Growable Array) implementation
- **SEQ-02**: RGA: insert(element, position) -> rga
- **SEQ-03**: RGA: remove(position) -> rga
- **SEQ-04**: RGA: value(rga) -> List(element)
- **SEQ-05**: RGA: merge(a, b) -> rga

### Distribution
- **DIST-01**: Erlang gossip protocol utilities
- **DIST-02**: Anti-entropy state synchronization helpers

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| New CRDT types | v1.1 is polish only — new types in v2.0 |
| Operation-based (CmRDT) variants | Deferred to future — CvRDT sufficient for v1.x |
| Binary serialization | JSON sufficient; binary format deferred |
| Networking / transport | Lattice provides data structures, not protocols |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TARGET-01 | Phase 5 | Complete |
| TARGET-02 | Phase 5 | Complete |
| TARGET-03 | Phase 5 | Complete |
| DOCS-01 | Phase 6 | Complete (all 12 modules) |
| DOCS-02 | Phase 6 | Complete (all 12 modules) |
| DOCS-03 | Phase 6 | Complete (all 12 modules) |
| DOCS-04 | Phase 6 | Complete |
| API-01 | Phase 6 | Complete (all 12 modules) |
| API-02 | Phase 6 | Complete (all 12 modules) |
| API-03 | Phase 6 | Complete (gaps documented; deferred to future plan) |
| PUB-01 | Phase 7 | Complete |
| PUB-02 | Phase 7 | Complete |
| PUB-03 | Phase 7 | Complete |
| PUB-04 | Phase 7 | Pending |

**Coverage:**
- v1.1 requirements: 14 total
- Mapped to phases: 14
- Unmapped: 0

---
*Requirements defined: 2026-03-01*
*Last updated: 2026-03-01 after Phase 6 Plan 02 completion (DOCS-01/02/03, API-01/02/03 complete — all 12 modules)*
