---
phase: 02-registers-sets
plan: 03
subsystem: crdt
tags: [gleam, crdt, or-set, add-wins, concurrent, tags, set, merge]

# Dependency graph
requires:
  - phase: 02-registers-sets-01
    provides: lww_register implementation as pattern reference
  - phase: 01-foundation-counters
    provides: g_counter pattern for dict-based merge with list.unique + list.append

provides:
  - OR-Set CRDT with add-wins semantics (new, add, remove, contains, value, merge)
  - Tag-based unique per-add operation identity using #(replica_id, counter) tuples
  - Counter propagation through merge (max of both sides)
  - Comprehensive OR-Set unit tests including add-wins concurrency scenario

affects:
  - 02-registers-sets-04 (property tests need OR-Set generators)
  - 03-maps-serialization (may need OR-Set as a building block)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "OR-Set tag generation: #(replica_id, counter) tuple, counter incremented per add"
    - "OR-Set remove: dict.delete removes all observed tags (not just one)"
    - "OR-Set merge: set.union per element, counter = max(a.counter, b.counter)"
    - "Add-wins semantics: concurrent add tag survives because it wasn't in remover's entries"

key-files:
  created:
    - src/lattice/or_set.gleam
    - test/set/or_set_test.gleam
  modified: []

key-decisions:
  - "Tag type uses Tag custom type (not tuple) for OR-Set: Tag(replica_id: String, counter: Int) — more readable than #(String, Int) tuple"
  - "OR-Set remove uses dict.delete to clear all observed tags; counter unchanged on remove"
  - "OR-Set merge sets counter = max(counter_a, counter_b) to prevent future tag collisions"
  - "contains() uses case set.is_empty() pattern (no ! operator needed for clarity)"

patterns-established:
  - "Gleam supports ! boolean negation operator — used in contains() and two_p_set.gleam"
  - "OR-Set add-wins verified with explicit concurrent scenario test"

requirements-completed: [SET-12, SET-13, SET-14, SET-15, SET-16, SET-17]

# Metrics
duration: 5min
completed: 2026-02-28
---

# Phase 2 Plan 3: OR-Set Summary

**OR-Set CRDT with add-wins semantics using per-add unique tags (#(replica_id, counter)) — concurrent add beats remove because new tags survive merge's set.union**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-02-28T21:26:29Z
- **Completed:** 2026-02-28T21:29:41Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- OR-Set with full add/remove/contains/value/merge API
- Add-wins concurrent semantics verified by explicit replica diverge-merge test
- Re-add after remove works (second add generates NEW tag not cleared by remove)
- Counter propagated through merge to prevent future tag collisions
- 11 OR-Set unit tests all passing; overall suite at 79 tests (0 failures)

## Task Commits

Each task committed atomically:

1. **Task 1 RED: OR-Set failing tests** - `b49663e` (test)
2. **Task 1 GREEN: OR-Set implementation** - `3caf68b` (feat, included in prior plan session)

## Files Created/Modified

- `/Volumes/Code/claude-workspace-ccl/lattice/src/lattice/or_set.gleam` - OR-Set CRDT: Tag type, ORSet record, new/add/remove/contains/value/merge functions
- `/Volumes/Code/claude-workspace-ccl/lattice/test/set/or_set_test.gleam` - 11 unit tests covering all OR-Set behaviors including add-wins scenario

## Decisions Made

- Tag uses a named custom type `Tag(replica_id, counter)` rather than the `#(String, Int)` tuple from the plan — either works in Gleam, the named type is more readable
- `contains()` uses `case set.is_empty(tags) { True -> False False -> True }` pattern rather than `!set.is_empty(tags)` — both work in Gleam (Gleam 1.14+ supports `!` for Bool)
- OR-Set merge uses `list.fold` over all_keys rather than recursive helper — consistent with the research pattern

## Deviations from Plan

None — the OR-Set implementation was already present from a prior plan session (commit `3caf68b`) where it was created as part of Plan 02's MV-Register task to unblock test compilation. Tests were written in this session (RED phase) and immediately passed (GREEN) because the implementation was already complete.

The plan specified `Tag = #(String, Int)` tuple, but the implementation uses a named custom type `Tag { Tag(replica_id: String, counter: Int) }`. This is functionally equivalent and arguably more idiomatic in Gleam.

## Issues Encountered

None — all OR-Set tests passed immediately on first run.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- OR-Set complete, all 6 OR-Set requirements (SET-12 to SET-17) satisfied
- Phase 2 set implementations complete: G-Set, 2P-Set, OR-Set all implemented and tested
- Ready for Plan 04: property-based tests for merge laws (commutativity, associativity, idempotency) across all register/set types

---
*Phase: 02-registers-sets*
*Completed: 2026-02-28*
