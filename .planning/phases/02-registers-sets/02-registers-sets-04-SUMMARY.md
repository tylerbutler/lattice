---
phase: 02-registers-sets
plan: "04"
subsystem: testing
tags: [qcheck, property-based-testing, crdt, gleam, lww-register, mv-register, g-set, two-p-set, or-set]

# Dependency graph
requires:
  - phase: 02-registers-sets
    provides: LWW-Register, MV-Register, G-Set, 2P-Set, OR-Set implementations (plans 01-03)
  - phase: 01-foundation-counters
    provides: qcheck property-test pattern with small_test_config
provides:
  - Property-based tests verifying merge laws for all 5 register/set CRDT types
  - Bug fix: MV-Register merge now correctly handles self-merge idempotency
affects: [03-maps-serialization, 04-advanced-testing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "small_test_config pattern: test_count=10, max_retries=3, seed=42 to prevent qcheck timeout"
    - "Generate scalar values (ints), construct CRDTs in test body (do not generate CRDT state directly)"
    - "Sort list-valued register outputs before comparison for order-independent equality"
    - "Compare set-valued outputs with == (Gleam set equality is structural, order-independent)"
    - "Compare OR-Set on value() not structural equality (replica_id differs post-merge)"

key-files:
  created:
    - test/property/register_set_property_test.gleam
  modified:
    - src/lattice/mv_register.gleam

key-decisions:
  - "MV-Register merge(a, a) bug fixed: entries must survive if shared (dict.has_key check) — strict < filter excluded entries when vclock[rid] == tag.counter on self-merge"
  - "MV-Register idempotency tested at value level (sorted list comparison) — structural equality not appropriate since vclock state merges"
  - "OR-Set commutativity and idempotency tested at value level (set.Set) since replica_id in merged ORSet struct depends on merge order"
  - "MV-Register associativity skipped per plan spec — complex to construct valid vclock triples"

patterns-established:
  - "Property test for CRDT merge law: generate Int params, construct CRDTs, assert law holds"
  - "Self-merge idempotency: assert merge(a, a) == a or sorted value(merge(a,a)) == sorted value(a)"

requirements-completed: [TEST-01, TEST-02, TEST-03]

# Metrics
duration: 2min
completed: "2026-02-28"
---

# Phase 2 Plan 04: Register & Set Property Tests Summary

**qcheck property tests for merge laws (commutativity, associativity, idempotency) across all 5 Phase 2 CRDT types, plus MV-Register idempotency bug fix revealed by tests**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-28T21:44:36Z
- **Completed:** 2026-02-28T21:46:54Z
- **Tasks:** 2 (both implemented in single file)
- **Files modified:** 2

## Accomplishments

- 13 property tests covering merge laws for LWW-Register, MV-Register, G-Set, 2P-Set, and OR-Set
- All 92 tests now pass (up from 91 before bug fix)
- Discovered and fixed MV-Register self-merge idempotency bug (entries dropped by strict < filter)
- Established value-level comparison patterns for list-valued and set-valued CRDTs

## Task Commits

Each task was committed atomically:

1. **Task 1+2: Property tests for all registers and sets** - `51c1ca0` (test)
2. **Rule 1 Auto-fix: MV-Register merge idempotency bug** - `23bf7f6` (fix)

**Plan metadata:** (this commit)

_Note: Tasks 1 and 2 were implemented together in a single file; the TDD cycle surfaced a bug that was fixed in a separate commit._

## Files Created/Modified

- `test/property/register_set_property_test.gleam` - 13 property tests for 5 CRDT types using qcheck small_test_config pattern
- `src/lattice/mv_register.gleam` - Fixed merge filter to preserve shared entries (enables self-merge idempotency)

## Decisions Made

- MV-Register idempotency required bug fix rather than test workaround: `merge(a, a)` must return same values as `a`
- OR-Set tests use `or_set.value()` for comparison rather than structural equality, since merged ORSet's replica_id depends on argument order
- MV-Register value lists are sorted before comparison since `dict.values()` order is not guaranteed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed MV-Register merge self-merge idempotency**
- **Found during:** Task 1 (MV-Register property tests — `mv_register_idempotency__test`)
- **Issue:** `merge(reg, reg)` returned `[]` instead of the register's values. The merge filter `version_vector.get(b.vclock, tag.replica_id) < tag.counter` uses strict `<`. When `b == a`, `b.vclock[rid] = tag.counter`, so `N < N = False` — all entries dropped.
- **Fix:** Added OR clause `|| dict.has_key(b.entries, tag)` so entries present in both registers always survive (handles self-merge and duplicate-merge correctly)
- **Files modified:** `src/lattice/mv_register.gleam`
- **Verification:** `gleam test` — all 92 tests pass; `gleam check` — no type errors
- **Committed in:** `23bf7f6`

---

**Total deviations:** 1 auto-fixed (Rule 1 - Bug)
**Impact on plan:** Bug fix required for correctness. The property test was the intended deliverable and it correctly identified a real CRDT implementation bug. No scope creep.

## Issues Encountered

None beyond the MV-Register bug documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All 5 Phase 2 CRDT types have passing property tests for merge laws
- Phase 3 (Maps & Serialization) can proceed
- The small_test_config + sorted-value-comparison pattern is established and ready to extend to future types

## Self-Check: PASSED

- FOUND: test/property/register_set_property_test.gleam
- FOUND: src/lattice/mv_register.gleam
- FOUND: .planning/phases/02-registers-sets/02-registers-sets-04-SUMMARY.md
- FOUND: commit 51c1ca0 (property tests)
- FOUND: commit 23bf7f6 (mv_register fix)

---
*Phase: 02-registers-sets*
*Completed: 2026-02-28*
