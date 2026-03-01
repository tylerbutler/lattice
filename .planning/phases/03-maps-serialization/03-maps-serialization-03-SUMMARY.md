---
phase: 03-maps-serialization
plan: 03
subsystem: crdt
tags: [gleam, crdt, or-map, tagged-union, dispatch, json-serialization]

# Dependency graph
requires:
  - phase: 03-maps-serialization-01
    provides: LWW-Map implementation and gleam_json dependency
  - phase: 03-maps-serialization-02
    provides: to_json/from_json on all 8 leaf CRDT types + VersionVector
provides:
  - Crdt tagged union wrapping all 8 leaf CRDT types
  - CrdtSpec enum for OR-Map auto-creation (7 variants)
  - default_crdt(spec, replica_id) factory
  - crdt.merge dispatch function (type-safe, mismatch returns first arg)
  - crdt.to_json/from_json generic dispatchers
  - OR-Map CRDT with add-wins key semantics (OR-Set tracking)
  - OR-Map update/get/remove/keys/values/merge operations
affects:
  - 03-maps-serialization-04 (final phase, will use OR-Map)
  - Any future composite CRDT types building on Crdt union

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Tagged union dispatch: central Crdt type routes to type-specific functions"
    - "Circular import avoidance: crdt.gleam imports leaves only; or_map.gleam imports crdt.gleam"
    - "OR-Map key tracking: OR-Set(String) for add-wins semantics on concurrent update vs remove"
    - "Auto-creation: update() uses CrdtSpec + default_crdt for new keys"
    - "Value preservation on remove: remove() only affects key_set, values dict retained for merge"

key-files:
  created:
    - src/lattice/crdt.gleam
    - src/lattice/or_map.gleam
    - test/map/crdt_dispatch_test.gleam
    - test/map/or_map_test.gleam
  modified: []

key-decisions:
  - "Crdt union covers only 8 leaf types (no CrdtOrMap/CrdtLwwMap) to prevent circular imports between or_map.gleam and crdt.gleam"
  - "All parameterized Crdt types fixed to String in v1 (CrdtLwwRegister(LWWRegister(String)), etc.)"
  - "CrdtSpec has 7 variants (no VersionVectorSpec — VersionVector is infrastructure, not an OR-Map value type)"
  - "crdt.merge returns first argument on type mismatch (safe degradation, not panic)"
  - "from_json dispatches via json.UnableToDecode on unknown type tag"
  - "ORMap is non-opaque: key_set field accessible directly for advanced test scenarios"
  - "remove() preserves values dict entry — only removes from key_set (OR-Set) to support add-wins merge"

patterns-established:
  - "Central dispatch pattern: typed union + case statement routes to leaf implementations"
  - "OR-Set key tracking: use or_set for any map CRDT needing add-wins conflict resolution"
  - "TDD: tests written before implementation; RED confirmed by compile errors, GREEN by 169/169 passing"

requirements-completed: [MAP-08, MAP-09, MAP-10, MAP-11, MAP-12, MAP-13, MAP-14]

# Metrics
duration: 3min
completed: 2026-03-01
---

# Phase 3 Plan 3: Crdt Union + OR-Map Summary

**Crdt tagged union dispatching to all 8 leaf types, plus OR-Map CRDT with OR-Set key tracking providing add-wins conflict resolution for concurrent update-vs-remove**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-01T13:42:33Z
- **Completed:** 2026-03-01T13:45:31Z
- **Tasks:** 2 (both TDD)
- **Files modified:** 4 created, 0 modified

## Accomplishments
- Crdt union type with 8 leaf variants + CrdtSpec enum with 7 variants for OR-Map auto-creation
- Generic merge dispatch routing to type-specific merge (mismatch returns first arg safely)
- Generic to_json/from_json dispatching via "type" field with unknown-type error handling
- OR-Map CRDT: new/update/get/remove/keys/values/merge all working with correct OR-Set semantics
- Add-wins verified: concurrent update beats remove (OR-Set tag mechanism preserves concurrent adds)
- No circular imports: crdt.gleam only imports leaf modules; or_map.gleam imports crdt.gleam

## Task Commits

Each task was committed atomically:

1. **Task 1: Crdt union type + dispatch functions** - `f9eb4d2` (feat)
2. **Task 2: OR-Map implementation with TDD** - `c546f76` (feat)

_Note: Both tasks used TDD — tests written first, compile errors confirmed RED, all tests passing confirmed GREEN_

## Files Created/Modified
- `src/lattice/crdt.gleam` - Crdt union, CrdtSpec, default_crdt, merge dispatch, to_json/from_json
- `src/lattice/or_map.gleam` - ORMap type with OR-Set key tracking and Crdt value storage
- `test/map/crdt_dispatch_test.gleam` - 21 tests for crdt dispatch module
- `test/map/or_map_test.gleam` - 20 tests for OR-Map including add-wins concurrent scenario

## Decisions Made
- **Crdt union excludes map types**: or_map.gleam and lww_map.gleam would cause circular imports if included in Crdt union; maps are composite containers not leaf CRDTs
- **VersionVector excluded from CrdtSpec**: VersionVector is internal CRDT infrastructure (used inside MVRegister, OR-Set), not a value type stored in OR-Map entries
- **crdt.merge type mismatch**: Returns first argument silently rather than panicking — safe degradation in distributed systems where type information may be lost
- **from_json uses json.UnableToDecode**: The gleam_json error constructor is `UnableToDecode(List(decode.DecodeError))`, not `UnexpectedFormat`
- **ORMap non-opaque**: Exposed key_set field directly (no `opaque` keyword) to allow advanced test scenarios and potential future inspection

## Deviations from Plan

None - plan executed exactly as written. The one implementation note was the json.DecodeError constructor: the plan mentioned `json.UnexpectedFormat` but the actual gleam_json type uses `json.UnableToDecode` — this was noted as a potential pitfall in the plan itself and handled correctly.

## Issues Encountered

None - both modules compiled and all tests passed on first attempt.

## Next Phase Readiness
- OR-Map complete with full test coverage (add-wins, nested CRDT merge, concurrent scenarios)
- Crdt union ready for use in any future composite CRDT types
- Phase 3 Plan 4 (LWW-Map serialization or remaining work) can proceed

---
*Phase: 03-maps-serialization*
*Completed: 2026-03-01*
