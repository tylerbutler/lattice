---
phase: 03-maps-serialization
plan: 02
subsystem: serialization
tags: [gleam_json, json, crdt, serialization, round-trip]

# Dependency graph
requires:
  - phase: 02-registers-sets
    provides: GCounter, PNCounter, VersionVector, LWWRegister, MVRegister, GSet, TwoPSet, ORSet implementations
provides:
  - to_json/from_json for GCounter, PNCounter, VersionVector
  - to_json/from_json for LWWRegister(String), MVRegister(String)
  - to_json/from_json for GSet(String), TwoPSet(String), ORSet(String)
  - Self-describing JSON format with type tag and version field
  - Round-trip test coverage for all 9 types
affects: [03-maps-serialization-03, 03-maps-serialization-04]

# Tech tracking
tech-stack:
  added: [gleam_json (already in deps), gleam/dynamic/decode]
  patterns:
    - "Self-describing JSON format: {type: string, v: int, state: {...}}"
    - "Decoder pattern using decode.field chaining with use syntax"
    - "Custom-type dict keys encoded as array of {tag, value} objects"
    - "Set serialization via set.to_list -> json.array / decode.list -> set.from_list"

key-files:
  created:
    - test/serialization/counter_json_test.gleam
    - test/serialization/version_vector_json_test.gleam
    - test/serialization/register_json_test.gleam
    - test/serialization/set_json_test.gleam
  modified:
    - src/lattice/g_counter.gleam
    - src/lattice/pn_counter.gleam
    - src/lattice/version_vector.gleam
    - src/lattice/lww_register.gleam
    - src/lattice/mv_register.gleam
    - src/lattice/g_set.gleam
    - src/lattice/two_p_set.gleam
    - src/lattice/or_set.gleam

key-decisions:
  - "LWWRegister, GSet, TwoPSet, ORSet, MVRegister serialization constrained to String values (v1 simplification)"
  - "MV-Register entries (Dict(Tag, String)) encoded as JSON array of {tag, value} objects — Tag cannot be a JSON dict key"
  - "OR-Set entries (Dict(String, set.Set(Tag))) encoded as JSON dict mapping element -> array of tag objects"
  - "Round-trip tests for MV-Register and OR-Set compare value() output (sorted lists/sets), not structural equality, due to internal ordering non-determinism"

patterns-established:
  - "Self-describing JSON: always include type and v (version) fields at top level"
  - "Nested decoder: use state <- decode.field('state', { ... }) then decode.success(state)"
  - "Dict encoding: json.dict(d, fn(k) { k }, encoder_fn) for String-keyed dicts"
  - "Set encoding: json.array(set.to_list(s), element_encoder)"
  - "Set decoding: decode.map(decode.list(element_decoder), set.from_list)"

requirements-completed: [JSON-01, JSON-02, JSON-03, JSON-04, JSON-05, JSON-06, JSON-07, JSON-08, JSON-09, JSON-10, JSON-11, JSON-12, JSON-13, JSON-14, JSON-19, JSON-20]

# Metrics
duration: 4min
completed: 2026-03-01
---

# Phase 3 Plan 02: JSON Serialization for All Leaf CRDT Types Summary

**Self-describing JSON to_json/from_json added to all 8 CRDT types plus VersionVector using gleam_json, with 15 round-trip tests covering simple and complex cases**

## Performance

- **Duration:** ~4 min
- **Started:** 2026-03-01T13:36:11Z
- **Completed:** 2026-03-01T13:39:11Z
- **Tasks:** 2 (TDD: 2 RED + 2 GREEN)
- **Files modified:** 12 (8 source, 4 test)

## Accomplishments
- Added to_json/from_json to GCounter, PNCounter, VersionVector, LWWRegister(String), MVRegister(String)
- Added to_json/from_json to GSet(String), TwoPSet(String), ORSet(String)
- All JSON uses self-describing format: `{"type": "...", "v": 1, "state": {...}}`
- 15 round-trip tests across 4 test files, all passing (128 total tests pass)

## Task Commits

Each task was committed atomically:

1. **Task 1: JSON for counters, clock, and registers** - `67fed04` (feat)
2. **Task 2: JSON for sets** - `04f308a` (feat)

_Note: TDD tasks had RED tests written first, then GREEN implementation in the same commit._

## Files Created/Modified
- `src/lattice/g_counter.gleam` - Added to_json/from_json; added gleam/json, gleam/dynamic/decode imports
- `src/lattice/pn_counter.gleam` - Added to_json/from_json; encodes both G-Counter states inline
- `src/lattice/version_vector.gleam` - Added to_json/from_json; encodes clocks dict
- `src/lattice/lww_register.gleam` - Added to_json/from_json; constrained to LWWRegister(String)
- `src/lattice/mv_register.gleam` - Added to_json/from_json; entries as array of {tag, value} objects
- `src/lattice/g_set.gleam` - Added to_json/from_json; elements as JSON array
- `src/lattice/two_p_set.gleam` - Added to_json/from_json; added and removed as separate arrays
- `src/lattice/or_set.gleam` - Added to_json/from_json; entries as JSON dict with tag arrays
- `test/serialization/counter_json_test.gleam` - Round-trip tests for GCounter and PNCounter
- `test/serialization/version_vector_json_test.gleam` - Round-trip tests for VersionVector
- `test/serialization/register_json_test.gleam` - Round-trip tests for LWWRegister and MVRegister
- `test/serialization/set_json_test.gleam` - Round-trip tests for GSet, TwoPSet, ORSet

## Decisions Made
- **String-only constraint for parameterized types**: LWWRegister(String), GSet(String), etc. — v1 simplification; adding type class constraints in Gleam would require protocol-style abstractions
- **MV-Register entry encoding**: Dict(Tag, String) can't use json.dict because Tag is a custom type not a String. Encoded as JSON array of `{tag: {r, c}, value: string}` objects
- **OR-Set entry encoding**: Dict(String, set.Set(Tag)) encoded as JSON dict with String keys mapping to arrays of tag objects
- **Round-trip equality strategy**: MVRegister and ORSet compare value() output (sorted lists/sets) rather than structural equality, since internal dict/tag ordering is non-deterministic

## Deviations from Plan

None - plan executed exactly as written. The decoder pattern in the plan's action section worked correctly on first try.

## Issues Encountered
- None during implementation.
- Note: During test run, gleam stash operation temporarily caused "lww_map module not found" error. This was a transient artifact of stashing our changes; restoring the stash resolved the issue immediately. The lww_map module already exists in src/lattice/lww_map.gleam (created by Plan 03-01).

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All 8 leaf CRDT types + VersionVector now have JSON serialization
- JSON format established: `{"type": "...", "v": 1, "state": {...}}`
- Pattern is ready for Plan 03-03 (LWW-Map JSON serialization) and Plan 03-04 (LWW-Map implementation if not done in 03-01)
- 128 tests passing, 0 failures

---
*Phase: 03-maps-serialization*
*Completed: 2026-03-01*
