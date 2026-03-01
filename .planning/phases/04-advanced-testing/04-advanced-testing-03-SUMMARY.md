---
phase: 04-advanced-testing
plan: "03"
subsystem: testing
tags: [gleam, qcheck, property-based-testing, crdt, convergence, bottom-identity, monotonicity]

requires:
  - phase: 04-advanced-testing-01
    provides: serialization property tests for all CRDT types
  - phase: 03-maps-serialization
    provides: LWWMap, ORMap, and JSON serialization for all CRDT types

provides:
  - Bottom identity property tests for all 9 CRDT types (TEST-05)
  - Monotonicity/inflation property tests for 5 CRDT types (TEST-06)
  - 3-replica convergence property tests for 5 CRDT types (TEST-04)
  - OR-Set concurrent add-wins property test (TEST-09)
  - 2P-Set tombstone permanence property test (TEST-10)
  - Cross-target JSON serialization smoke tests for 3 CRDT types (TEST-08)

affects: []

tech-stack:
  added: []
  patterns:
    - small_test_config pattern (test_count 10, max_retries 3, seed 42) for all property tests
    - 3-replica all-to-all merge for convergence verification
    - Distinct timestamp ranges per replica (1-30, 31-60, 61-90) to avoid LWW tie-break ambiguity

key-files:
  created:
    - test/property/advanced_property_test.gleam
  modified:
    - test/property/map_property_test.gleam

key-decisions:
  - "LWW-Register bottom identity uses ts+1 to guarantee non-zero register beats zero-timestamp bottom"
  - "MV-Register bottom identity compares sorted value() lists (not structural equality)"
  - "OR-Map bottom identity compares set.from_list(keys()) on both sides"
  - "Monotonicity for PN-Counter uses increment-only (not decrement) to ensure clean upward direction"
  - "LWW-Map convergence uses distinct timestamp ranges per replica to avoid tie-break ambiguity"
  - "OR-Set concurrent add-wins: replica_b syncs then removes; replica_a re-adds concurrently; add must win"
  - "2P-Set tombstone permanence tested under both merge orders (ab and ba)"
  - "Cross-target tests use deterministic fixed values, not qcheck generators (smoke tests not property tests)"

patterns-established:
  - "Convergence pattern: 3 replicas, each merges with both others, compare observable values"
  - "Add-wins property: sync-remove vs concurrent-re-add, verify element present after merge"

requirements-completed: [TEST-04, TEST-05, TEST-06, TEST-08, TEST-09, TEST-10]

duration: 2min
completed: "2026-03-01"
---

# Phase 04 Plan 03: Advanced Property Tests Summary

**24 advanced property tests verifying bottom identity (9 types), monotonicity (5 types), 3-replica convergence (5 types), OR-Set add-wins, 2P-Set tombstone permanence, and cross-target JSON round-trips**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-01T22:15:05Z
- **Completed:** 2026-03-01T22:17:30Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- 9 bottom identity tests prove merge(a, new()) preserves observable value for all CRDT types
- 5 monotonicity tests prove values are non-decreasing after merges (GCounter, PNCounter, GSet, ORSet, LWWRegister)
- 5 convergence tests prove 3-replica all-to-all exchange produces identical state (GCounter, PNCounter, GSet, LWWRegister, LWWMap)
- OR-Set concurrent add-wins property test with random elements (concurrent add always beats observed-remove)
- 2P-Set tombstone permanence test under both merge orders (tombstoned elements never revive)
- 3 cross-target JSON round-trip smoke tests prove no BEAM-specific types in JSON encoding

## Task Commits

Each task was committed atomically:

1. **Task 1: Bottom identity + monotonicity/inflation property tests** - `c358e8d` (test)
2. **Task 2: Convergence + OR-Set add-wins + 2P-Set tombstone + cross-target tests** - `507f165` (test)

**Plan metadata:** (pending docs commit)

_Note: TDD tests pass immediately since implementations already satisfy these mathematical properties_

## Files Created/Modified

- `test/property/advanced_property_test.gleam` - 464 lines; bottom identity (9 tests), monotonicity (5 tests), convergence (5 tests), OR-Set add-wins (1 test), 2P-Set tombstone permanence (1 test), cross-target smoke tests (3 tests)
- `test/property/map_property_test.gleam` - Auto-fixed pre-existing compilation error (Rule 3 - blocking): `lattice/g_counter` path syntax replaced with imported `g_counter` module name

## Decisions Made

- LWW-Register bottom identity uses `ts+1` to guarantee the register always beats the zero-timestamp bottom element
- MV-Register bottom identity compares `list.sort(value(...), int.compare)` to handle ordering independence
- OR-Map bottom identity compares `set.from_list(keys(...))` rather than structural equality
- PN-Counter monotonicity uses increment-only scenario (both inputs positive) to ensure clean upward monotonicity
- LWW-Map convergence uses distinct timestamp ranges per replica (1-30, 31-60, 61-90) to eliminate tie-break ambiguity while keeping values within qcheck-compatible ranges
- Cross-target tests are deterministic smoke tests (not property-based) since they verify specific JSON values rather than probabilistic properties

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Fixed map_property_test.gleam compilation error**
- **Found during:** Task 1 (initial test run revealed compilation error)
- **Issue:** `map_property_test.gleam` used `lattice/g_counter.increment` (module path syntax) instead of `g_counter.increment` (imported module name). Gleam does not support inline module path access without import.
- **Fix:** Added `import lattice/g_counter` to the file and replaced path-style calls with imported name. Gleam linter also extracted inline closures to a named helper function.
- **Files modified:** `test/property/map_property_test.gleam`
- **Verification:** `gleam test` passes with 228 tests, no compilation errors
- **Committed in:** c358e8d (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking compilation error)
**Impact on plan:** The blocking error was pre-existing (from a prior plan's uncommitted file). Fix was necessary to compile the new test file. No scope creep.

## Issues Encountered

None - all planned tests implemented and passing immediately. Existing CRDT implementations already satisfy all the mathematical properties being tested.

## Next Phase Readiness

- Phase 04 plan 03 complete: all 6 requirement TEST IDs (TEST-04 through TEST-06, TEST-08 through TEST-10) satisfied
- Total test count: 228 (up from 195 at plan start)
- No blockers or concerns

## Self-Check: PASSED

- FOUND: test/property/advanced_property_test.gleam (464 lines)
- FOUND: .planning/phases/04-advanced-testing/04-advanced-testing-03-SUMMARY.md
- FOUND: c358e8d (Task 1 commit: bottom identity + monotonicity)
- FOUND: 507f165 (Task 2 commit: convergence + add-wins + tombstone + cross-target)
- FOUND: 09090bd (metadata commit: SUMMARY + STATE + ROADMAP)
- VERIFIED: 228 tests passing, 0 failures

---
*Phase: 04-advanced-testing*
*Completed: 2026-03-01*
