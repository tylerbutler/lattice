---
phase: 03-maps-serialization
verified: 2026-03-01T14:05:00Z
status: human_needed
score: 5/6 must-haves verified
human_verification:
  - test: "Encode a CRDT (e.g., G-Counter) on the Erlang target, save the JSON string, then decode it using the JS target in a separate gleam run (gleam run --target javascript)."
    expected: "from_json on the JS target produces an identical value() output to the original Erlang-encoded CRDT."
    why_human: "Cross-target compatibility requires running two separate Gleam runtimes (BEAM and JS). Cannot be verified with grep/file inspection alone."
---

# Phase 3: Maps & Serialization Verification Report

**Phase Goal:** Deliver map CRDTs and JSON serialization with cross-platform compatibility
**Verified:** 2026-03-01T14:05:00Z
**Status:** human_needed — 5/6 automated truths verified; 1 success criterion (cross-target) requires human testing
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | LWW-Map correctly resolves per-key conflicts: each key's value determined by highest timestamp | VERIFIED | `merge_overlapping_higher_ts_wins_test`, `set_higher_timestamp_wins_test`, `merge_tombstone_higher_ts_removes_test` in `test/map/lww_map_test.gleam`; `merge` fn in `src/lattice/lww_map.gleam` uses `ts_a >= ts_b` logic |
| 2 | OR-Map nested CRDTs merge correctly: updating a key's CRDT value merges with existing | VERIFIED | `merge_nested_values_combined_test` in `test/map/or_map_test.gleam` verifies G-Counter merge (3+7=10); `or_map.merge` calls `crdt.merge(ca, cb)` for per-key merge |
| 3 | OR-Map concurrent update vs remove: update wins (add-wins semantics) | VERIFIED | `concurrent_update_wins_over_remove_test` and `merge_add_wins_keys_in_or_set_test` in `test/map/or_map_test.gleam`; OR-Set key tracking provides add-wins |
| 4 | G-Counter JSON round-trip: `from_json(to_json(counter))` produces identical counter | VERIFIED | `g_counter_to_json_simple_test` and `g_counter_round_trip_multi_replica_test` in `test/serialization/counter_json_test.gleam`; `g_counter_json_round_trip__test` property test passes |
| 5 | All CRDT types serialize/deserialize correctly to/from JSON | VERIFIED | All 11 modules (g_counter, pn_counter, lww_register, mv_register, g_set, two_p_set, or_set, version_vector, lww_map, or_map, crdt) have `to_json`/`from_json`; 187 tests pass including round-trip tests for every type |
| 6 | Cross-target serialization works: state encoded on Erlang decodes identically on JS | UNCERTAIN | Cannot verify programmatically; requires running two separate Gleam runtimes |

**Score: 5/6 automated truths verified**

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gleam.toml` | gleam_json in [dependencies] | VERIFIED | Line 13: `gleam_json = ">= 3.1.0 and < 4.0.0"` under `[dependencies]` |
| `src/lattice/lww_map.gleam` | LWW-Map CRDT + to_json/from_json | VERIFIED | 156 lines; new, set, get, remove, keys, values, merge, to_json, from_json all present and substantive |
| `test/map/lww_map_test.gleam` | LWW-Map unit tests | VERIFIED | 20 test functions covering all operations and edge cases |
| `src/lattice/crdt.gleam` | Crdt union type, CrdtSpec, dispatch functions | VERIFIED | Crdt (8 variants), CrdtSpec (7 variants), default_crdt, merge, to_json, from_json all present |
| `src/lattice/or_map.gleam` | OR-Map CRDT + to_json/from_json | VERIFIED | 221 lines; new, update, get, remove, keys, values, merge, to_json, from_json all present |
| `test/map/or_map_test.gleam` | OR-Map unit tests | VERIFIED | 20 test functions including add-wins and nested CRDT scenarios |
| `test/map/crdt_dispatch_test.gleam` | Crdt dispatch tests | VERIFIED | 21 test functions covering default_crdt, merge dispatch, and to_json/from_json round-trips |
| `src/lattice/g_counter.gleam` | to_json/from_json added | VERIFIED | Lines 46-70 substantive implementation |
| `src/lattice/pn_counter.gleam` | to_json/from_json added | VERIFIED | 2 serialization functions present |
| `src/lattice/version_vector.gleam` | to_json/from_json added | VERIFIED | 2 serialization functions present |
| `src/lattice/lww_register.gleam` | to_json/from_json added | VERIFIED | 2 serialization functions present |
| `src/lattice/mv_register.gleam` | to_json/from_json added | VERIFIED | 2 serialization functions present |
| `src/lattice/g_set.gleam` | to_json/from_json added | VERIFIED | 2 serialization functions present |
| `src/lattice/two_p_set.gleam` | to_json/from_json added | VERIFIED | 2 serialization functions present |
| `src/lattice/or_set.gleam` | to_json/from_json added | VERIFIED | 2 serialization functions present |
| `test/serialization/counter_json_test.gleam` | G-Counter and PN-Counter round-trip tests | VERIFIED | 4 test functions |
| `test/serialization/register_json_test.gleam` | LWW-Register and MV-Register round-trip tests | VERIFIED | 4 test functions |
| `test/serialization/set_json_test.gleam` | G-Set, 2P-Set, OR-Set round-trip tests | VERIFIED | 6 test functions |
| `test/serialization/version_vector_json_test.gleam` | Version Vector round-trip tests | VERIFIED | 2 test functions |
| `test/serialization/lww_map_json_test.gleam` | LWW-Map JSON round-trip tests | VERIFIED | 5 test functions including tombstone round-trip |
| `test/serialization/or_map_json_test.gleam` | OR-Map JSON round-trip tests | VERIFIED | 5 test functions including nested CRDT values |
| `test/property/serialization_property_test.gleam` | Property-based round-trip tests | VERIFIED | 8 qcheck property tests; uses small_test_config (count:10, seed:42) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|----|--------|---------|
| `src/lattice/lww_map.gleam` | `gleam/dict` | `dict.Dict(String, #(Option(String), Int))` | WIRED | `import gleam/dict` present; entries stored as Dict |
| `src/lattice/lww_map.gleam` | `gleam/json` | `to_json`/`from_json` | WIRED | `import gleam/json` + `import gleam/dynamic/decode` present; both functions substantive |
| `test/map/lww_map_test.gleam` | `src/lattice/lww_map.gleam` | `import lattice/lww_map` | WIRED | Import present; 20 test functions call lww_map.* |
| `src/lattice/crdt.gleam` | `src/lattice/g_counter.gleam` | `CrdtGCounter` variant | WIRED | `import lattice/g_counter.{type GCounter}` present; CrdtGCounter wraps GCounter |
| `src/lattice/crdt.gleam` | all 7 other leaf modules | 8-variant dispatch | WIRED | All 8 leaf module imports present; merge/to_json/from_json dispatch to each |
| `src/lattice/or_map.gleam` | `src/lattice/crdt.gleam` | `Crdt`/`CrdtSpec` types | WIRED | `import lattice/crdt.{type Crdt, type CrdtSpec}` present; update/merge/get all use Crdt |
| `src/lattice/or_map.gleam` | `src/lattice/or_set.gleam` | OR-Set for key tracking | WIRED | `import lattice/or_set.{type ORSet}` present; key_set field is ORSet(String) |
| `src/lattice/or_map.gleam` | `gleam/json` | OR-Map to_json/from_json | WIRED | Double-encoding pattern: nested CRDTs serialized as JSON strings via crdt.to_json |
| NO circular import | `crdt.gleam` does NOT import `lww_map` or `or_map` | | WIRED | Grep confirms crdt.gleam has no import of lww_map or or_map |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| MAP-01 | Plan 01 | LWW-Map: new() | SATISFIED | `pub fn new() -> LWWMap` in lww_map.gleam; `new_keys_empty_test` passes |
| MAP-02 | Plan 01 | LWW-Map: set(map, key, value, timestamp) | SATISFIED | `pub fn set(...)` present; `set_get_single_key_test` passes |
| MAP-03 | Plan 01 | LWW-Map: get(map, key) -> Result(value, Nil) | SATISFIED | `pub fn get(...)` returns Ok/Error; tests verify both |
| MAP-04 | Plan 01 | LWW-Map: remove(map, key, timestamp) | SATISFIED | `pub fn remove(...)` tombstone semantics; `remove_makes_key_missing_test` passes |
| MAP-05 | Plan 01 | LWW-Map: keys(map) | SATISFIED | `pub fn keys(...)` filters tombstones; `keys_returns_all_active_test` passes |
| MAP-06 | Plan 01 | LWW-Map: values(map) | SATISFIED | `pub fn values(...)` filters tombstones; `values_returns_all_active_test` passes |
| MAP-07 | Plan 01 | LWW-Map: merge(a, b) (per-key LWW) | SATISFIED | `pub fn merge(...)` uses pairwise max-timestamp; `merge_overlapping_higher_ts_wins_test` passes |
| MAP-08 | Plan 03 | OR-Map: new(replica_id, crdt_spec) | SATISFIED | `pub fn new(replica_id, crdt_spec)` in or_map.gleam; `new_get_missing_key_test` passes |
| MAP-09 | Plan 03 | OR-Map: update(map, key, fn(crdt) -> crdt) | SATISFIED | `pub fn update(map, key, f)` auto-creates + applies fn; `update_auto_creates_crdt_test` passes |
| MAP-10 | Plan 03 | OR-Map: get(map, key) -> Result(crdt, Nil) | SATISFIED | `pub fn get(...)` checks OR-Set active status; `get_returns_ok_for_active_key_test` passes |
| MAP-11 | Plan 03 | OR-Map: remove(map, key) | SATISFIED | `pub fn remove(...)` removes from key_set only; `remove_makes_key_invisible_test` passes |
| MAP-12 | Plan 03 | OR-Map: keys(map) | SATISFIED | `pub fn keys(...)` returns active OR-Set elements; `keys_returns_only_active_keys_test` passes |
| MAP-13 | Plan 03 | OR-Map: values(map) | SATISFIED | `pub fn values(...)` filters to active keys; `values_returns_only_active_values_test` passes |
| MAP-14 | Plan 03 | OR-Map: merge(a, b) (add-wins keys, CRDT-merge values) | SATISFIED | `pub fn merge(...)` merges OR-Sets + per-key crdt.merge; `concurrent_update_wins_over_remove_test` passes |
| JSON-01 | Plan 02 | JSON encoder for G-Counter | SATISFIED | `g_counter.to_json` present; `g_counter_to_json_simple_test` passes |
| JSON-02 | Plan 02 | JSON decoder for G-Counter | SATISFIED | `g_counter.from_json` present; round-trip test passes |
| JSON-03 | Plan 02 | JSON encoder for PN-Counter | SATISFIED | `pn_counter.to_json` present; `pn_counter_to_json_simple_test` passes |
| JSON-04 | Plan 02 | JSON decoder for PN-Counter | SATISFIED | `pn_counter.from_json` present; round-trip test passes |
| JSON-05 | Plan 02 | JSON encoder for LWW-Register | SATISFIED | `lww_register.to_json` present; register_json_test.gleam passes |
| JSON-06 | Plan 02 | JSON decoder for LWW-Register | SATISFIED | `lww_register.from_json` present; round-trip test passes |
| JSON-07 | Plan 02 | JSON encoder for MV-Register | SATISFIED | `mv_register.to_json` present; entries encoded as array of tag+value objects |
| JSON-08 | Plan 02 | JSON decoder for MV-Register | SATISFIED | `mv_register.from_json` present; round-trip test passes |
| JSON-09 | Plan 02 | JSON encoder for G-Set | SATISFIED | `g_set.to_json` present; `g_set_round_trip_test` passes |
| JSON-10 | Plan 02 | JSON decoder for G-Set | SATISFIED | `g_set.from_json` present; round-trip test passes |
| JSON-11 | Plan 02 | JSON encoder for 2P-Set | SATISFIED | `two_p_set.to_json` present; set_json_test.gleam passes |
| JSON-12 | Plan 02 | JSON decoder for 2P-Set | SATISFIED | `two_p_set.from_json` present; round-trip test passes |
| JSON-13 | Plan 02 | JSON encoder for OR-Set | SATISFIED | `or_set.to_json` encodes entries as dict of element -> tag arrays |
| JSON-14 | Plan 02 | JSON decoder for OR-Set | SATISFIED | `or_set.from_json` present; round-trip test passes |
| JSON-15 | Plan 04 | JSON encoder for LWW-Map | SATISFIED | `lww_map.to_json` encodes entries as JSON array with nullable value; `lww_map_round_trip_active_test` passes |
| JSON-16 | Plan 04 | JSON decoder for LWW-Map | SATISFIED | `lww_map.from_json` reconstructs Dict with tombstones; `lww_map_round_trip_tombstone_test` passes |
| JSON-17 | Plan 04 | JSON encoder for OR-Map | SATISFIED | `or_map.to_json` double-encodes nested CRDTs as JSON strings; `or_map_round_trip_single_key_test` passes |
| JSON-18 | Plan 04 | JSON decoder for OR-Map | SATISFIED | `or_map.from_json` decodes crdt_spec, key_set (via or_set.from_json), and CRDT values (via crdt.from_json); round-trip tests pass |
| JSON-19 | Plan 02 | JSON encoder for Version Vector | SATISFIED | `version_vector.to_json` present; version_vector_json_test.gleam passes |
| JSON-20 | Plan 02 | JSON decoder for Version Vector | SATISFIED | `version_vector.from_json` present; round-trip test passes |

**Note on REQUIREMENTS.md checkboxes:** MAP-08 to MAP-14 and JSON-01 to JSON-14, JSON-19, JSON-20 show as unchecked (`[ ]`) in REQUIREMENTS.md, but the implementations are present and verified in the codebase. The REQUIREMENTS.md file was not updated after phase completion — this is a documentation debt, not an implementation gap.

### Anti-Patterns Found

No anti-patterns found in phase 3 files. All source files are substantive:
- No TODO/FIXME/placeholder comments in any src or test file
- No stub implementations (all functions have real logic)
- No orphaned modules (all new modules are imported and tested)
- No circular imports (crdt.gleam does not import lww_map or or_map)

### Human Verification Required

#### 1. Cross-Target JSON Serialization

**Test:** Compile and run a small Gleam program on the Erlang target that encodes a G-Counter or OR-Map to JSON and prints the string. Then compile and run the same JSON decode on the JavaScript target (`gleam run --target javascript`). Verify the `value()` output matches.

**Expected:** `from_json(json_string)` on the JavaScript target reconstructs a CRDT with the same observable state as the original Erlang-encoded CRDT (same `value()` return).

**Why human:** Cross-target compatibility requires executing two separate Gleam runtimes. Cannot be verified by static code inspection. Success Criterion 6 from ROADMAP.md explicitly states: "Cross-target serialization works: state encoded on Erlang decodes identically on JS."

### Gaps Summary

No gaps were found in the implementation. All 34 requirements (MAP-01 through MAP-14, JSON-01 through JSON-20) are satisfied by substantive code that passes 187 tests (up from 169 at start of phase). The single outstanding item is cross-target serialization verification, which is an inherently runtime/human-testable concern.

The only discrepancy found is that REQUIREMENTS.md checkbox status is not updated for MAP-08 to MAP-14 and most JSON requirements — this is documentation debt, not an implementation gap.

---

_Verified: 2026-03-01T14:05:00Z_
_Verifier: Claude (gsd-verifier)_
