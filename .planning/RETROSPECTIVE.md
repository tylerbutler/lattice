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

## Milestone: v1.1 — Production Ready

**Shipped:** 2026-03-06
**Phases:** 3 | **Plans:** 7

### What Was Built
- JavaScript target verification: all 228 tests passing with zero code changes needed
- Dual-target CI: separate test-erlang and test-js jobs in GitHub Actions
- Complete documentation: /// doc comments on all public functions/types, module-level docs with examples
- API polish: opaque types (Tag, DotContext, VersionVector, MVRegister), consistent function ordering
- Hex.pm metadata: gleam.toml v1.1.0, README with type catalog, CHANGELOG via changie

### What Worked
- Phase 5 was effortless: all 228 tests already passed on JS target with zero failures — the pure functional design from v1.0 paid off
- Docs and API review in one phase (Phase 6) was efficient — reviewing signatures naturally leads to writing doc comments
- changie for changelog generation worked well once configured
- Pre-publish verification script caught gleam.toml format issues before they could block a publish

### What Was Inefficient
- gleam.toml links format required a fix commit — TOML array-of-tables syntax ([[links]]) wasn't obvious
- changie `body:block:true` config silently dropped entries passed via `--body` flag — required manual correction
- Phase 7 Plan 02 (publish) is a human-action gate that can't be automated without credentials — would benefit from a "deferred action" plan type

### Patterns Established
- Hex.pm links format: `[[links]]` with title/href fields (TOML array of tables)
- Two explicit CI jobs (test-erlang, test-js) instead of matrix — clearer setup when requirements differ
- Opaque type decision framework: make opaque unless sibling modules need to destructure

### Key Lessons
- Pure functional design gives you cross-target compatibility for free — no code changes needed for JS
- API review and documentation are synergistic — do them together, not separately
- Publish verification should be a checklist script, not manual — catches format/metadata issues early
- Human-gated tasks (needing credentials) should be clearly marked in plans

### Cost Observations
- Model mix: ~90% sonnet (execution), ~10% opus (orchestration)
- Sessions: 3 sessions across 5 days
- Notable: Phase 5 completed in ~4 minutes total (2 plans) — no code changes needed

---

## Cross-Milestone Trends

| Metric | v1.0 | v1.1 |
|--------|------|------|
| Phases | 4 | 3 |
| Plans | 14 | 7 |
| Tests | 228 | 228 (unchanged) |
| Source LOC | 1,402 | ~1,500 (docs added) |
| Commits | 67 | 29 |
| Timeline | 2 days | 5 days |
