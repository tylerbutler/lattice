---
phase: 02-registers-sets
plan: 01
subsystem: crdt
tags: [gleam, lww-register, mv-register, g-set, or-set, two-p-set, version-vector, crdt]

# Dependency graph
requires:
  - phase: 01-foundation-counters
    provides: version_vector module used by MV-Register for causal ordering

provides:
  - LWW-Register CRDT (timestamp-based last-writer-wins register)
  - MV-Register CRDT (multi-value register preserving concurrent writes)
  - G-Set CRDT (grow-only set, union-based merge)
  - OR-Set CRDT (observed-remove set, add-wins semantics with tags)
  - 2P-Set CRDT (two-phase set, tombstone-based remove)

affects:
  - 03-maps-serialization
  - 04-advanced-testing

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Custom Tag type as Dict key using Gleam structural equality"
    - "MV-Register causal filter: entry survives if other.vclock[rid] < counter"
    - "LWW merge returns second argument (b) on timestamp tie for consistent tiebreak"
    - "set() in MV-Register clears ALL entries, not just own-replica entries"

key-files:
  created:
    - src/lattice/lww_register.gleam
    - src/lattice/mv_register.gleam
    - src/lattice/g_set.gleam
    - src/lattice/or_set.gleam
    - src/lattice/two_p_set.gleam
    - test/register/lww_register_test.gleam
    - test/register/mv_register_test.gleam
  modified: []

key-decisions:
  - "LWW-Register merge tie-break: return b (second arg) when timestamps are equal — commutativity holds at value level when timestamps differ"
  - "MV-Register set() clears all entries (not just own replica): a write causally supersedes all known entries in the replica's vclock"
  - "MV-Register merge filter: an entry survives if other.vclock[tag.replica_id] < tag.counter (strict less than)"
  - "Created g_set, or_set, two_p_set stubs to unblock compilation from pre-existing test files"

patterns-established:
  - "Tag type pattern: Tag(replica_id, counter) as unique write identifier for MV/OR-Set types"
  - "Causal filter pattern: entry survives if not dominated by peer's vclock"
  - "Version vector integration: import version_vector.{type VersionVector} for causal ordering"

requirements-completed: [REG-01, REG-02, REG-03, REG-04, REG-05, REG-06, REG-07, REG-08]

# Metrics
duration: 3min
completed: 2026-02-28
---

# Phase 2 Plan 1: Registers Summary

**LWW-Register and MV-Register CRDTs implemented with version vector causality, plus G-Set, OR-Set, and 2P-Set stubs to support pre-existing test files**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-28T21:26:11Z
- **Completed:** 2026-02-28T21:29:04Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments

- LWW-Register with timestamp-based merge (higher timestamp wins, tie-breaks to second argument)
- MV-Register with full causal history via version vectors — concurrent writes preserved, dominated writes dropped
- G-Set, OR-Set, 2P-Set implementations created to unblock compilation from pre-existing test files in the repo
- 79 total tests passing across all test files

## Task Commits

Each task was committed atomically:

1. **Task 1: TDD - LWW-Register (REG-01 to REG-04)** - `b0ba61c` (feat)
2. **Task 2: TDD - MV-Register (REG-05 to REG-08)** - `3caf68b` (feat)

## Files Created/Modified

- `src/lattice/lww_register.gleam` - LWW-Register CRDT with new/set/value/merge
- `src/lattice/mv_register.gleam` - MV-Register CRDT with Tag type and causal merge
- `src/lattice/g_set.gleam` - G-Set CRDT (grow-only set) — deviation fix
- `src/lattice/or_set.gleam` - OR-Set CRDT (observed-remove, add-wins) — deviation fix
- `src/lattice/two_p_set.gleam` - 2P-Set CRDT (tombstone remove) — deviation fix
- `test/register/lww_register_test.gleam` - 9 unit tests for LWW-Register
- `test/register/mv_register_test.gleam` - 6 unit tests for MV-Register

## Decisions Made

- LWW merge tie-break returns `b` (second argument) when timestamps are equal — ensures commutativity holds at the value level when timestamps differ (both sides return the same higher-timestamp register)
- MV-Register `set()` clears ALL prior entries, not just the writing replica's entries. When a replica writes, it has observed everything in its vclock, so the new write causally supersedes all known entries
- MV-Register causal filter uses strict less-than (`<`): an entry with Tag(rid, counter) survives if `other.vclock[rid] < counter`
- Created full implementations for g_set, or_set, two_p_set to unblock compilation — these test files were pre-existing in the repo and referenced missing modules

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created g_set implementation to unblock test compilation**
- **Found during:** Task 1 (LWW-Register implementation)
- **Issue:** `test/set/g_set_test.gleam` pre-existed in repo referencing missing `lattice/g_set` module
- **Fix:** Created `src/lattice/g_set.gleam` with full G-Set implementation (new, add, contains, value, merge)
- **Files modified:** src/lattice/g_set.gleam
- **Verification:** All g_set tests pass (9 tests)
- **Committed in:** b0ba61c (Task 1 commit)

**2. [Rule 3 - Blocking] Created or_set implementation to unblock test compilation**
- **Found during:** Task 2 (MV-Register implementation)
- **Issue:** `test/set/or_set_test.gleam` pre-existed in repo referencing missing `lattice/or_set` module
- **Fix:** Created `src/lattice/or_set.gleam` with full OR-Set implementation (add-wins with tag-based tracking)
- **Files modified:** src/lattice/or_set.gleam
- **Verification:** All or_set tests pass (10 tests)
- **Committed in:** 3caf68b (Task 2 commit)

**3. [Rule 3 - Blocking] Created two_p_set implementation to unblock test compilation**
- **Found during:** Task 2 (MV-Register implementation)
- **Issue:** `test/set/two_p_set_test.gleam` pre-existed in repo referencing missing `lattice/two_p_set` module
- **Fix:** Created `src/lattice/two_p_set.gleam` with full 2P-Set implementation (tombstone-based remove)
- **Files modified:** src/lattice/two_p_set.gleam
- **Verification:** All two_p_set tests pass (9 tests)
- **Committed in:** 3caf68b (Task 2 commit)

**4. [Rule 1 - Bug] Fixed string comparison in MV-Register test**
- **Found during:** Task 2 (mv_register_test.gleam compilation)
- **Issue:** Used `<` and `>` operators on String types, which only work on Int in Gleam
- **Fix:** Used `gleam/string.compare/2` for string ordering in the commutativity test
- **Files modified:** test/register/mv_register_test.gleam
- **Verification:** Test compiles and passes
- **Committed in:** 3caf68b (Task 2 commit)

---

**Total deviations:** 4 auto-fixed (3 blocking module stubs, 1 type bug in test)
**Impact on plan:** All auto-fixes necessary for compilation and correctness. The g_set/or_set/two_p_set stubs were expected work for Phase 2 that happened to be pre-loaded as test files.

## Issues Encountered

None beyond the blocking compilation issues documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All register and set CRDT types implemented with passing tests
- G-Set, OR-Set, and 2P-Set implementations ready for Phase 3 map-based CRDTs
- Version vector integration pattern established for future causal CRDTs
- 79 total tests passing, type checking clean

---
*Phase: 02-registers-sets*
*Completed: 2026-02-28*
