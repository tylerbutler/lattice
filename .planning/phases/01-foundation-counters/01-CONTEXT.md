# Phase 1: Foundation & Counters - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning
**Source:** Phase 1 discussion

<domain>
## Phase Boundary

This phase delivers:
- Build/test infrastructure (gleam test working)
- Version Vector (CLOCK-01 to CLOCK-05)
- G-Counter (COUNTER-01 to COUNTER-04)
- PN-Counter (COUNTER-05 to COUNTER-09)
- Property-based tests for merge laws (TEST-01, TEST-02)

**Implementation Order (dependency chain):**
1. Version Vector — foundational, used by G-Counter internally
2. G-Counter — uses VV for per-replica tracking
3. PN-Counter — built on two G-Counters (positive/negative)

</domain>

<decisions>
## Implementation Decisions

### TDD Approach
- **Locked Decision:** Tests written first (Red), then minimal implementation (Green), then refactor
- Test naming: `<type>_<behavior>_test`
- Use gleeunit for unit tests

### Test Structure
- **Locked Decision:** Tests in test/counter/ and test/clock/ subdirectories
- One test file per CRDT type

### Implementation Order
- **Locked Decision:** Version Vector before G-Counter (dependency)
- **Locked Decision:** G-Counter before PN-Counter (dependency)

### Version Vector
- Use Dict to store replica -> counter mapping
- compare() returns: Before, After, Concurrent, Equal

### G-Counter
- Internal representation: Dict(ReplicaId, Int)
- Merge: pairwise max per replica
- Value: sum of all replica counts

### PN-Counter
- Internal representation: pair of G-Counters (positive, negative)
- Value: positive sum - negative sum

### Claude's Discretion
- Whether to use qcheck for property-based tests (Gleam ecosystem)
- Internal data structure choices (Dict vs List)
- Module organization within src/lattice/

</decisions>

<specifics>
## Specific Ideas

From TEST.md:
- Merge commutativity: merge(a,b) == merge(b,a)
- Merge associativity: merge(merge(a,b),c) == merge(a,merge(b,c))
- Merge idempotency: merge(a,a) == a
- Convergence: all-to-all exchange produces identical results

</specifics>

<deferred>
## Deferred Ideas

None — Phase 1 scope is well-defined

</deferred>

---

*Phase: 01-foundation-counters*
*Context gathered: 2026-02-28 via Phase 1 discussion*
