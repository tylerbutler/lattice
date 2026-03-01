# Phase 3: Maps & Serialization - Context

**Gathered:** 2026-03-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver LWW-Map and OR-Map CRDT types, plus JSON encode/decode for all 10 CRDT types (8 existing from Phases 1-2, plus the 2 new maps). Cross-platform Erlang/JS round-trip compatibility is a success criterion. Map types and serialization are implemented in the same package (lattice), not a companion package.

</domain>

<decisions>
## Implementation Decisions

### Serialization Packaging
- Same package — to_json/from_json functions live directly on each CRDT module (e.g., g_counter.to_json, g_counter.from_json)
- gleam_json becomes a runtime dependency (acceptable — serialization is a core CRDT library feature)
- Error type: use gleam/json.DecodeError directly (standard, composable, carries path info)

### JSON Format Design
- Self-describing format with type tag and version: `{"type": "g_counter", "v": 1, "state": {...}}`
- Transparent internals — serialize actual internal structure for full fidelity and debuggability
- Generic dispatch decoder: lattice/crdt.gleam provides from_json(json) that reads "type" field and dispatches to the correct type-specific decoder
- Returns tagged union enum: `pub type Crdt { CrdtGCounter(GCounter) | CrdtPnCounter(PnCounter) | ... }`

### OR-Map Nested CRDT Design
- OR-Map stores values as the Crdt union enum (same tagged union from serialization)
- Homogeneous: all keys store the same CRDT type, specified at construction
- Auto-create from type tag: if key doesn't exist on update(), create a default value from the map's CRDT type and replica_id
- The Crdt union type and generic merge/dispatch functions live in `lattice/crdt.gleam` (dedicated module)

### Claude's Discretion
- Exact JSON field names and nesting structure for each CRDT type
- LWW-Map internal representation (Dict of timestamped entries vs separate value/timestamp dicts)
- OR-Map internal causal context tracking approach
- Cross-target test strategy details

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `lattice/version_vector.gleam`: Used by MV-Register, likely needed by OR-Map for causal context
- `lattice/or_set.gleam`: OR-Set's tag-based add-wins pattern is the foundation for OR-Map's key management
- All 8 existing CRDT modules have public constructors (non-opaque types) — to_json can access internals directly
- `gleam_json` already in dependencies (currently dev, will move to runtime)

### Established Patterns
- Record-wrapping pattern: each CRDT is a named record type (GCounter, PnCounter, etc.)
- All types expose: new(), value(), merge() — to_json/from_json follows this convention
- Tests use startest + qcheck with small_test_config (test_count: 10, max_retries: 3, seed: 42)
- TDD approach: tests first, then implementation

### Integration Points
- Each existing module gets 2 new public functions: to_json() and from_json()
- New lattice/crdt.gleam module defines the Crdt union type used by OR-Map and generic decoder
- New lattice/lww_map.gleam and lattice/or_map.gleam follow existing module conventions
- Test files in test/map/ for map types, serialization tests alongside unit tests per module

</code_context>

<specifics>
## Specific Ideas

- The Crdt union enum serves double duty: generic JSON decoding AND OR-Map value storage
- OR-Map's merge dispatches to type-specific merge via the Crdt enum's tag
- Version field in JSON enables future format migration without breaking existing consumers

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-maps-serialization*
*Context gathered: 2026-03-01*
