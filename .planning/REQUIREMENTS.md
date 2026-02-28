# Requirements: Lattice — CRDT Library for Gleam

**Defined:** 2026-02-28
**Core Value:** A comprehensive CRDT library for Gleam with correct merge semantics verified by property-based tests, providing developers with battle-tested data structures for building distributed, collaborative, or offline-first applications.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Counters

- [ ] **COUNTER-01**: G-Counter: new(replica_id) -> t
- [ ] **COUNTER-02**: G-Counter: increment(counter, Int) -> counter
- [ ] **COUNTER-03**: G-Counter: value(counter) -> Int
- [ ] **COUNTER-04**: G-Counter: merge(a, b) -> counter (pairwise max)
- [ ] **COUNTER-05**: PN-Counter: new(replica_id) -> t
- [ ] **COUNTER-06**: PN-Counter: increment(counter, Int) -> counter
- [ ] **COUNTER-07**: PN-Counter: decrement(counter, Int) -> counter
- [ ] **COUNTER-08**: PN-Counter: value(counter) -> Int
- [ ] **COUNTER-09**: PN-Counter: merge(a, b) -> counter

### Registers

- [ ] **REG-01**: LWW-Register: new(value, timestamp) -> t
- [ ] **REG-02**: LWW-Register: set(register, value, timestamp) -> register
- [ ] **REG-03**: LWW-Register: value(register) -> value
- [ ] **REG-04**: LWW-Register: merge(a, b) -> register (higher timestamp wins)
- [ ] **REG-05**: MV-Register: new(replica_id) -> t
- [ ] **REG-06**: MV-Register: set(register, value) -> register
- [ ] **REG-07**: MV-Register: value(register) -> List(value)
- [ ] **REG-08**: MV-Register: merge(a, b) -> register (preserve concurrent values)

### Sets

- [ ] **SET-01**: G-Set: new() -> t
- [ ] **SET-02**: G-Set: add(set, element) -> set
- [ ] **SET-03**: G-Set: contains(set, element) -> Bool
- [ ] **SET-04**: G-Set: value(set) -> Set(element)
- [ ] **SET-05**: G-Set: merge(a, b) -> set (union)
- [ ] **SET-06**: 2P-Set: new() -> t
- [ ] **SET-07**: 2P-Set: add(set, element) -> set
- [ ] **SET-08**: 2P-Set: remove(set, element) -> set
- [ ] **SET-09**: 2P-Set: contains(set, element) -> Bool
- [ ] **SET-10**: 2P-Set: value(set) -> Set(element)
- [ ] **SET-11**: 2P-Set: merge(a, b) -> set (respects tombstones)
- [ ] **SET-12**: OR-Set: new(replica_id) -> t
- [ ] **SET-13**: OR-Set: add(or_set, element) -> or_set
- [ ] **SET-14**: OR-Set: remove(or_set, element) -> or_set
- [ ] **SET-15**: OR-Set: contains(or_set, element) -> Bool
- [ ] **SET-16**: OR-Set: value(or_set) -> Set(element)
- [ ] **SET-17**: OR-Set: merge(a, b) -> or_set (add wins on concurrent)

### Maps

- [ ] **MAP-01**: LWW-Map: new() -> t
- [ ] **MAP-02**: LWW-Map: set(map, key, value, timestamp) -> map
- [ ] **MAP-03**: LWW-Map: get(map, key) -> Result(value, Nil)
- [ ] **MAP-04**: LWW-Map: remove(map, key, timestamp) -> map
- [ ] **MAP-05**: LWW-Map: keys(map) -> List(key)
- [ ] **MAP-06**: LWW-Map: values(map) -> List(value)
- [ ] **MAP-07**: LWW-Map: merge(a, b) -> map (per-key LWW)
- [ ] **MAP-08**: OR-Map: new(replica_id, crdt_spec) -> t
- [ ] **MAP-09**: OR-Map: update(map, key, fn(crdt) -> crdt) -> map
- [ ] **MAP-10**: OR-Map: get(map, key) -> Result(crdt, Nil)
- [ ] **MAP-11**: OR-Map: remove(map, key) -> map
- [ ] **MAP-12**: OR-Map: keys(map) -> List(key)
- [ ] **MAP-13**: OR-Map: values(map) -> List(crdt)
- [ ] **MAP-14**: OR-Map: merge(a, b) -> map (add-wins keys, CRDT-merge values)

### Causal Context

- [ ] **CLOCK-01**: Version Vector: new() -> t
- [ ] **CLOCK-02**: Version Vector: increment(vv, replica_id) -> vv
- [ ] **CLOCK-03**: Version Vector: get(vv, replica_id) -> Int
- [ ] **CLOCK-04**: Version Vector: compare(a, b) -> Order (Before/After/Concurrent/Equal)
- [ ] **CLOCK-05**: Version Vector: merge(a, b) -> vv (pairwise max)
- [ ] **CLOCK-06**: Dot Context: new() -> t
- [ ] **CLOCK-07**: Dot Context: add_dot(context, replica_id, Int) -> context
- [ ] **CLOCK-08**: Dot Context: remove_dots(context, List(Dot)) -> context
- [ ] **CLOCK-09**: Dot Context: contains_dots(context, List(Dot)) -> Bool

### Serialization (Companion Package)

- [ ] **JSON-01**: JSON encoder for G-Counter
- [ ] **JSON-02**: JSON decoder for G-Counter
- [ ] **JSON-03**: JSON encoder for PN-Counter
- [ ] **JSON-04**: JSON decoder for PN-Counter
- [ ] **JSON-05**: JSON encoder for LWW-Register
- [ ] **JSON-06**: JSON decoder for LWW-Register
- [ ] **JSON-07**: JSON encoder for MV-Register
- [ ] **JSON-08**: JSON decoder for MV-Register
- [ ] **JSON-09**: JSON encoder for G-Set
- [ ] **JSON-10**: JSON decoder for G-Set
- [ ] **JSON-11**: JSON encoder for 2P-Set
- [ ] **JSON-12**: JSON decoder for 2P-Set
- [ ] **JSON-13**: JSON encoder for OR-Set
- [ ] **JSON-14**: JSON decoder for OR-Set
- [ ] **JSON-15**: JSON encoder for LWW-Map
- [ ] **JSON-16**: JSON decoder for LWW-Map
- [ ] **JSON-17**: JSON encoder for OR-Map
- [ ] **JSON-18**: JSON decoder for OR-Map
- [ ] **JSON-19**: JSON encoder for Version Vector
- [ ] **JSON-20**: JSON decoder for Version Vector

### Testing (Property-Based)

- [ ] **TEST-01**: Merge commutativity tests for all CRDT types
- [ ] **TEST-02**: Merge associativity tests for all CRDT types
- [ ] **TEST-03**: Merge idempotency tests for all CRDT types
- [ ] **TEST-04**: Convergence tests (all-to-all exchange)
- [ ] **TEST-05**: Bottom identity tests
- [ ] **TEST-06**: Inflation/monotonicity tests
- [ ] **TEST-07**: Serialization round-trip tests
- [ ] **TEST-08**: Cross-target serialization tests (Erlang <-> JS)
- [ ] **TEST-09**: OR-Set concurrent add-wins tests
- [ ] **TEST-10**: 2P-Set tombstone permanence tests

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Advanced Types

- **DELTA-01**: Delta-CRDT support for G-Counter
- **DELTA-02**: Delta-CRDT support for PN-Counter
- **DELTA-03**: Delta-CRDT support for OR-Set
- **DELTA-04**: Delta-CRDT support for OR-Map

### Sequence Types

- **SEQ-01**: RGA (Replicated Growable Array) implementation
- **SEQ-02**: RGA: insert(element, position) -> rga
- **SEQ-03**: RGA: remove(position) -> rga
- **SEQ-04**: RGA: value(rga) -> List(element)
- **SEQ-05**: RGA: merge(a, b) -> rga

### Text CRDT

- **TEXT-01**: Text CRDT for collaborative editing
- **TEXT-02**: Text CRDT: insert(text, position, String) -> text
- **TEXT-03**: Text CRDT: delete(text, position, length) -> text
- **TEXT-04**: Text CRDT: value(text) -> String
- **TEXT-05**: Text CRDT: merge(a, b) -> text

### Distribution Helpers

- **DIST-01**: Erlang gossip protocol utilities
- **DIST-02**: Anti-entropy state synchronization helpers

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Networking/transport | Lattice provides data structures, not replication protocols |
| Persistence/storage | Serialization is in scope; database integration is not |
| Conflict resolution UI | Lattice resolves conflicts automatically |
| Full Automerge clone | Focus on individual CRDT primitives, not document-level framework |
| Consensus/coordination | CRDTs are coordination-free by design |
| Binary serialization | JSON sufficient for v1; binary format defer to v2+ |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| COUNTER-01 to COUNTER-04 | Phase 1 | Pending |
| CLOCK-01 to CLOCK-05 | Phase 1 | Pending |
| TEST-01 to TEST-08 | Phase 1 | Pending |
| REG-01 to REG-04 | Phase 2 | Pending |
| SET-01 to SET-05 | Phase 2 | Pending |
| SET-06 to SET-11 | Phase 2 | Pending |
| SET-12 to SET-17 | Phase 3 | Pending |
| CLOCK-06 to CLOCK-09 | Phase 3 | Pending |
| TEST-09 to TEST-10 | Phase 3 | Pending |
| MAP-01 to MAP-07 | Phase 4 | Pending |
| MAP-08 to MAP-14 | Phase 4 | Pending |
| JSON-01 to JSON-20 | Phase 4 | Pending |
| DELTA-01 to DELTA-04 | Phase 5 | Pending |
| SEQ-01 to SEQ-05 | Phase 5 | Pending |
| TEXT-01 to TEXT-05 | Phase 5 | Pending |
| DIST-01 to DIST-02 | Phase 5 | Pending |

**Coverage:**
- v1 requirements: 75 total
- Mapped to phases: 75
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-28*
*Last updated: 2026-02-28 after research synthesis*
