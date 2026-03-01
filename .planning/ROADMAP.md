# Lattice — Roadmap

## Phases

- [ ] **Phase 1: Foundation & Counters** - Build system, testing infrastructure, Version Vector, G-Counter, PN-Counter with TDD
- [x] **Phase 2: Registers & Sets** - LWW-Register, MV-Register, G-Set, 2P-Set, OR-Set with property tests
- [x] **Phase 3: Maps & Serialization** - LWW-Map, OR-Map, JSON serialization with round-trip tests
- [ ] **Phase 4: Advanced Testing** - Cross-target serialization, OR-Set edge cases, convergence tests

## Phase Details

### Phase 1: Foundation & Counters

**Goal:** Establish build system, testing infrastructure, and deliver the simplest CRDT types (counters) with property-based test coverage

**Depends on:** Nothing (first phase)

**Requirements:** COUNTER-01 to COUNTER-09, CLOCK-01 to CLOCK-05, TEST-01 to TEST-08 (subset: counter merge laws)

**Success Criteria** (what must be TRUE):
  1. Developer can run `gleam test` and see all counter tests pass
  2. G-Counter merge satisfies commutativity: `merge(a, b) == merge(b, a)` for any states
  3. G-Counter merge satisfies associativity: `merge(merge(a, b), c) == merge(a, merge(b, c))`
  4. G-Counter merge satisfies idempotency: `merge(a, a) == a`
  5. PN-Counter converges after all-to-all exchange: all replicas produce identical `value()`
  6. Version Vector compare returns correct Order (Before/After/Concurrent/Equal) for any two vectors
  7. Property tests shrink correctly (qcheck generators produce minimal counterexamples)

**Plans**: 3 plans

Plans:
- [x] 01-PLAN.md — Version Vector and G-Counter with TDD (COMPLETED)
- [x] 02-PLAN.md — PN-Counter implementation (COMPLETED)
- [x] 03-PLAN.md — Property-based tests for merge laws (COMPLETED)

---

### Phase 2: Registers & Sets

**Goal:** Deliver register and set CRDT types with full property test coverage

**Depends on:** Phase 1

**Requirements:** REG-01 to REG-08, SET-01 to SET-17, TEST-01 to TEST-08 (subset: register/set merge laws)

**Success Criteria** (what must be TRUE):
  1. LWW-Register correctly resolves conflicts: higher timestamp always wins
  2. MV-Register preserves concurrent values: `merge(a, b)` contains both values when sets are concurrent
  3. G-Set merge is union: `value(merge(a, b))` contains elements from both sets
  4. 2P-Set tombstone is permanent: after `remove(element)`, `contains(element)` returns False forever
  5. OR-Set allows re-add after remove: `add(remove(add("a")))` contains "a"
  6. OR-Set concurrent add wins: concurrent `add("x")` and `remove("x")` results in add winning
  7. All register and set types pass merge commutativity, associativity, idempotency tests

**Plans**: 4 plans

Plans:
- [x] 01-PLAN.md — LWW-Register and MV-Register with TDD (COMPLETED)
- [x] 02-PLAN.md — G-Set and 2P-Set with TDD (COMPLETED)
- [x] 03-PLAN.md — OR-Set with add-wins semantics (COMPLETED)
- [x] 04-PLAN.md — Property tests for register/set merge laws (COMPLETED)

---

### Phase 3: Maps & Serialization

**Goal:** Deliver map CRDTs and JSON serialization with cross-platform compatibility

**Depends on:** Phase 2

**Requirements:** MAP-01 to MAP-14, JSON-01 to JSON-20

**Success Criteria** (what must be TRUE):
  1. LWW-Map correctly resolves per-key conflicts: each key's value determined by highest timestamp
  2. OR-Map nested CRDTs merge correctly: updating a key's CRDT value merges with existing
  3. OR-Map concurrent update vs remove: update wins (add-wins semantics)
  4. G-Counter JSON round-trip: `from_json(to_json(counter))` produces identical counter
  5. All CRDT types serialize/deserialize correctly to/from JSON
  6. Cross-target serialization works: state encoded on Erlang decodes identically on JS

**Plans**: 4 plans

Plans:
- [x] 01-PLAN.md — LWW-Map + gleam_json dependency (Wave 1) (COMPLETED)
- [x] 02-PLAN.md — JSON serialization for all 8 leaf types + Version Vector (Wave 1, parallel) (COMPLETED)
- [x] 03-PLAN.md — Crdt union type + OR-Map implementation (Wave 2) (COMPLETED)
- [x] 04-PLAN.md — Map JSON + round-trip property tests (Wave 3) (COMPLETED)

---

### Phase 4: Advanced Testing

**Goal:** Complete property-based test coverage for all CRDT types

**Depends on:** Phase 3

**Requirements:** TEST-01 to TEST-10 (remaining), CLOCK-06 to CLOCK-09

**Success Criteria** (what must be TRUE):
  1. All CRDT types pass merge commutativity tests
  2. All CRDT types pass merge associativity tests
  3. All CRDT types pass merge idempotency tests
  4. All-to-all exchange convergence holds for all types (random replica subsets)
  5. Bottom identity tests pass: `merge(a, new()) == a` for all types
  6. Inflation/monotonicity tests pass: values only increase after merges
  7. OR-Set concurrent add-wins edge cases verified (rust-crdt scenarios)
  8. 2P-Set tombstone permanence verified under various merge orders
  9. Cross-target serialization round-trips verified

**Plans**: 3 plans

Plans:
- [x] 01-PLAN.md — Dot Context implementation + unit tests (CLOCK-06 to CLOCK-09) (COMPLETED)
- [x] 02-PLAN.md — Map merge-law property tests + remaining serialization round-trips (TEST-01/02/03 maps, TEST-07) (COMPLETED)
- [ ] 03-PLAN.md — Convergence + bottom identity + monotonicity + edge cases + cross-target (TEST-04/05/06/08/09/10)

---

## Progress Table

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation & Counters | 3/3 | Complete | 2026-02-28 |
| 2. Registers & Sets | 4/4 | Complete | 2026-02-28 |
| 3. Maps & Serialization | 4/4 | Complete | 2026-03-01 |
| 4. Advanced Testing | 2/3 | In Progress | - |

---

## Coverage Map

| Requirement | Phase | Status |
|-------------|-------|--------|
| COUNTER-01 to COUNTER-04 | Phase 1 | Complete |
| COUNTER-05 to COUNTER-09 | Phase 1 | Complete |
| CLOCK-01 to CLOCK-05 | Phase 1 | Complete |
| TEST-01 to TEST-02 (counter portion) | Phase 1 | Complete |
| REG-01 to REG-08 | Phase 2 | Complete |
| SET-01 to SET-17 | Phase 2 | Complete (all set types implemented; property tests pending Plan 04) |
| TEST-01 to TEST-03 (register/set portion) | Phase 2 | Complete (unit tests; property tests pending) |
| MAP-01 to MAP-07 | Phase 3 | Complete (LWW-Map implemented) |
| MAP-08 to MAP-14 | Phase 3 | Complete (OR-Map + Crdt union implemented) |
| JSON-01 to JSON-14, JSON-19, JSON-20 | Phase 3 | Complete (leaf types + VersionVector done) |
| JSON-15 to JSON-18 | Phase 3 | Complete (LWW-Map and OR-Map JSON done) |
| TEST-04 to TEST-08 (convergence, serialization) | Phase 3/4 | Partial (round-trip property tests done; convergence pending) |
| CLOCK-06 to CLOCK-09 | Phase 4 | Complete (DotContext module) |
| TEST-01 to TEST-03 (map merge laws, OR-Set assoc) | Phase 4 | Complete (plan 02) |
| TEST-07 (serialization round-trips all types) | Phase 4 | Complete (plan 02) |
| TEST-04/05/06/08/09/10 (convergence, edge cases) | Phase 4 | Pending (plan 03) |
| TEST-09 (OR-Set concurrent add-wins) | Phase 4 | Pending |
| TEST-10 (2P-Set tombstone permanence) | Phase 4 | Pending |

**Coverage:**
- v1 requirements: 87 total
- Mapped to phases: 87
- Unmapped: 0 ✓

---

## Notes

- **TDD Approach**: Each phase implements tests first (red), then implementation (green), then refactor
- **Property-based testing**: qcheck is critical for verifying merge laws (commutativity, associativity, idempotency)
- **Quick depth**: 4 phases compressed from original 5 to match "quick" setting
- **Phase 3 & 4 dependency**: Maps need Sets (OR-Map uses OR-Set); Testing completes after all types exist

---

*Roadmap created: 2026-02-28*
