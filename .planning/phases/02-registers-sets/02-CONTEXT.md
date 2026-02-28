# Phase 2: Registers & Sets - Context

**Gathered:** 2026-02-28
**Status:** Ready for planning
**Source:** Phase 2 research + Phase 1 patterns

<domain>
## Phase Boundary

This phase delivers:
- LWW-Register (REG-01 to REG-04)
- MV-Register (REG-05 to REG-08)
- G-Set (SET-01 to SET-05)
- 2P-Set (SET-06 to SET-11)
- OR-Set (SET-12 to SET-17)
- Property-based tests for merge laws (TEST-01, TEST-02, TEST-03 — register/set portion)

**Implementation Order (by complexity):**
1. LWW-Register — simplest register (value + timestamp)
2. MV-Register — complex register (needs VersionVector for causality)
3. G-Set — simplest set (grow-only, wraps gleam/set)
4. 2P-Set — medium set (added + removed tombstone sets)
5. OR-Set — most complex (tag-based add-wins semantics)
6. Property tests — verifies merge laws for all 5 types

</domain>

<decisions>
## Implementation Decisions

### TDD Approach
- **Locked Decision:** Tests written first (Red), then minimal implementation (Green), then refactor
- Test naming: `<type>_<behavior>_test`
- Use startest/expect for assertions

### Test Structure
- **Locked Decision:** Tests in test/register/ and test/set/ subdirectories
- Property tests in test/property/ (extends existing counter_property_test.gleam pattern)
- One test file per CRDT type

### Implementation Patterns (from Phase 1)
- **Locked Decision:** Follow Phase 1 record-wrapping pattern (GCounter, PNCounter style)
- **Locked Decision:** Use gleam/set for G-Set and 2P-Set internals (not gleam/dict)
- **Locked Decision:** Use gleam/dict for OR-Set entries (element -> tag set mapping)

### LWW-Register
- Simple record: LWWRegister(value: a, timestamp: Int)
- Merge: higher timestamp wins
- Tie-breaking: use `ts_a > ts_b` (favor `b` on tie) — commutative per research analysis

### MV-Register
- Record with replica_id, entries (Dict(Tag, a)), vclock (VersionVector)
- Tag = custom type with replica_id + counter
- set() clears all prior entries, inserts new with fresh tag
- merge() keeps entries not dominated by other's vclock

### G-Set
- Wraps gleam/set.Set
- merge = set.union

### 2P-Set
- Two sets: added + removed (tombstones)
- value = set.difference(added, removed)
- merge = union both added and removed sets

### OR-Set
- Tag = #(String, Int) tuple (replica_id, counter)
- entries: Dict(element, Set(Tag))
- add: generate unique tag, add to element's tag set
- remove: delete element from entries dict
- merge: union tag sets per element, counter = max

### Property Tests (qcheck)
- **Locked Decision:** Use small_test_config (test_count: 10, max_retries: 3, seed: 42) per Phase 1 pattern
- Test merge commutativity, associativity, idempotency for all 5 types

### Claude's Discretion
- MV-Register Tag type: custom type vs tuple (research recommends custom type)
- Whether to add helper functions beyond the required API
- Exact qcheck generator strategies for each type

</decisions>

<specifics>
## Specific Ideas

From research:
- LWW tie-breaking must be deterministic and commutative
- MV-Register set() must clear stale own-replica entries
- OR-Set counter must be propagated through merge (max)
- OR-Set add-wins: concurrent add and remove -> add wins because new tag survives

From Phase 1 established patterns:
- Dict merge helper: list.unique(list.append(dict.keys(a), dict.keys(b)))
- result.unwrap(dict.get(dict, key), default) for safe access
- Recursive helper functions for merging

</specifics>

<deferred>
## Deferred Ideas

None — Phase 2 scope is well-defined by requirements

</deferred>

---

*Phase: 02-registers-sets*
*Context gathered: 2026-02-28 via research synthesis*
