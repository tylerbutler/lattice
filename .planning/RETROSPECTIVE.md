# Retrospective

## Milestone: v1.0 — CRDT Library

**Shipped:** 2026-03-01
**Phases:** 4 | **Plans:** 14

### What Was Built
- 10 CRDT types (counters, registers, sets, maps) + Dot Context
- Crdt tagged union with generic merge dispatch and JSON serialization
- Self-describing JSON format with type/version envelope
- 228 property-based and unit tests across 25 test files
- 1,402 LOC source, 3,338 LOC tests

### What Worked
- TDD caught a real bug: MV-Register merge dropped entries on self-merge (idempotency violation)
- Wave-based parallel execution: Plans 01/02/03 in Phase 2 ran concurrently with zero conflicts
- qcheck small_test_config (test_count: 10, seed: 42) prevented timeout issues reliably
- Self-describing JSON format makes debugging and forward compatibility straightforward
- Crdt union serving double duty (OR-Map values + generic JSON decoder) was a clean design

### What Was Inefficient
- Phase 2 parallel agents created stub files for each other due to import resolution — worked around but added noise
- REQUIREMENTS.md checkboxes fell behind actual implementation — documentation debt accumulated
- STATE.md wasn't always updated correctly by parallel agents — some fields stuck at null

### Patterns Established
- TDD for all CRDT implementations (tests first, implementation second)
- startest + qcheck as testing stack (replaced gleeunit)
- Observable equality for property tests (compare `value()` output, not structural records)
- Non-overlapping timestamp ranges for LWW commutativity tests
- Skip associativity tests for types with complex internal state (MV-Register, OR-Map)

### Key Lessons
- Property-based tests are essential for CRDTs — they find bugs that unit tests miss
- Gleam's type system forces the Crdt union to fix type parameters (String for v1) — plan for this constraint early
- Circular import avoidance requires careful module design — crdt.gleam imports leaf modules but never the reverse
- LWW tombstone semantics (Option value) are critical for correct remove-across-merge behavior

### Cost Observations
- Model mix: ~90% sonnet (execution), ~10% opus (orchestration)
- Sessions: 1 main session covering all 4 phases
- Notable: Phase 2-4 each completed in one wave cycle with minimal rework

---

## Cross-Milestone Trends

| Metric | v1.0 |
|--------|------|
| Phases | 4 |
| Plans | 14 |
| Tests | 228 |
| Source LOC | 1,402 |
| Test LOC | 3,338 |
| Test:Source Ratio | 2.4:1 |
