# Feature Research

**Domain:** CRDT (Conflict-free Replicated Data Type) Library for Gleam
**Researched:** 2026-02-28
**Confidence:** HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Core CRDT types that form the foundation. Missing any of these = library feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **G-Counter** | Simplest CRDT; grow-only counting for metrics, likes, votes | LOW | Foundation for understanding CRDTs. Sum of per-replica max values. |
| **PN-Counter** | Allows both increment and decrement; extends G-Counter | LOW | Contains two G-Counters (P and N); value = sum(P) - sum(N). |
| **G-Set** | Grow-only set for tracking unique items that never delete | LOW | Merge = union. Cannot remove elements. Use case: audit logs, login history. |
| **2P-Set** | Two-phase set with add and remove (tombstones) | MEDIUM | Contains add-set and remove-set. Once removed, cannot re-add. |
| **OR-Set** | Observed-Remove Set — allows re-adding after removal | HIGH | THE critical set type. Most CRDT libraries use ORSWOT variant. Uses unique tags per element. Concurrent add+remove = add wins. |
| **LWW-Register** | Last-Writer-Wins single value container | LOW | Timestamp-based. Project reference: lpil's `lww-register-crdt` already exists in Gleam. |
| **MV-Register** | Multi-Value Register — preserves concurrent writes | MEDIUM | Returns array of concurrent values. Enables later semantic resolution. Critical for collaborative editing. |
| **LWW-Map** | Last-Writer-Wins key-value map | MEDIUM | Each key maps to LWW-Register. Merge = per-key LWW. |
| **OR-Map** | Observed-Remove Map with nested CRDT values | HIGH | Values are CRDTs. Allows composing CRDTs (e.g., map of counters). Concurrent update+remove = update wins. |
| **Version Vector** | Tracks causality between replicas | MEDIUM | Essential for OR-Set, OR-Map, and causal context. Provides `compare` (Before/After/Concurrent/Equal). |

### Differentiators (Competitive Advantage)

Features that set the library apart. Valuable but not required for basic CRDT functionality.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Text CRDT (RGA)** | Collaborative text editing | VERY HIGH | Rich text editing requires sequence CRDTs. RGA (Replicated Growable Array) is the standard. Yjs, Loro, Automerge all have this. |
| **Sequence/List CRDT** | Ordered collections beyond text | HIGH | Unlike sets/maps, ordering matters. RGA, WOOT, Logoots are options. |
| **Delta-CRDT Support** | Efficient state transfer for replication | MEDIUM | Instead of sending full state, send only changes. Critical for network efficiency. |
| **Operation-based Variants** | Lower bandwidth for frequent updates | MEDIUM | CmRDTs send ops vs CvRDTs sending state. Trade-off: requires reliable delivery. |
| **JSON Serialization** | Cross-system interoperability | MEDIUM | Enables storage and API communication. Project spec calls this a companion package. |
| **Causal Context Utilities** | Efficient metadata tracking | MEDIUM | For OR-Set/OR-Map to know what they've seen. Must serialize with state. |
| **Property-Based Test Suite** | Verifies CRDT correctness | HIGH | Must verify: commutativity, associativity, idempotency, convergence, inflation. Project's TEST.md has comprehensive test cases. |
| **Erlang Distribution Helpers** | Built-in gossip/anti-entropy for BEAM | MEDIUM | Could use gleam_otp for Erlang-only features. Enables peer discovery and sync. |
| **Typed CRDT Composition** | Type-safe nested CRDTs in maps | MEDIUM | OR-Map with typed values. Gleam's type system can enforce this. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems or are out of scope per PROJECT.md.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Networking/Transport** | CRDTs need to sync between replicas | Lattice's scope is data structures only, not protocols. Users can use any transport (WebSocket, HTTP, gossip, CRDT sync algorithms). | Provide clear examples of how to sync states. |
| **Persistence/Database Integration** | Users need to save CRDT state | Serialization is in scope; database integration is not. Many databases exist. | JSON/binary serialization for users to store. |
| **Conflict Resolution UI** | "Let users choose which value to keep" | MV-Register already provides this. Automatic resolution is CRDT's value proposition. | Let users handle MV-Register output array. |
| **Full Automerge Clone** | Comprehensive document CRDT | Focus on primitives, not document-level framework. Automerge is its own product category. | Provide composable primitives users can assemble. |
| **Consensus/Coordination** | "Make sure all replicas agree" | CRDTs are coordination-free by design. That's the point. | Document that Lattice provides eventual consistency. |
| **Real-time Streaming** | Automatic push on state changes | Depends on transport layer. Can be built on top by users. | Provide hooks/callback pattern if needed later. |

## Feature Dependencies

```
[G-Counter]
    └──requires──> [Version Vector] (optional, for causal tracking)

[PN-Counter]
    └──requires──> [G-Counter] (internal implementation)

[G-Set]
    └──requires──> Nothing (foundation type)

[2P-Set]
    └──requires──> [G-Set] (contains two G-Sets internally)

[OR-Set]
    └──requires──> [Version Vector] (critical for tag tracking)
    └──requires──> [Causal Context] (to know what's been seen)

[LWW-Register]
    └──requires──> Timestamp source (user provides)

[MV-Register]
    └──requires──> [Version Vector] (for causal ordering)

[LWW-Map]
    └──requires──> [LWW-Register] (each key is a register)

[OR-Map]
    └──requires──> [OR-Set] (key operations)
    └──requires──> [CRDT Values] (any CRDT as nested value)

[Text CRDT / RGA]
    └──requires──> [Sequence CRDT] (foundation)
    └──requires──> [Version Vector] (for causal ordering)

[Delta-CRDTs]
    └──enhances──> [All State-based CRDTs]
    └──requires──> [Delta encoding utilities]

[JSON Serialization]
    └──enhances──> [All CRDT types]
```

### Dependency Notes

- **OR-Set requires Version Vector:** The core OR-Set algorithm tracks per-element causal history using dots (replica ID + sequence number). Version vectors provide this tracking.
- **G-Counter is foundation for PN-Counter:** PN-Counter internally maintains two G-Counters (positive and negative). Building G-Counter first makes PN-Counter trivial.
- **OR-Map requires OR-Set semantics:** Key operations use observed-remove semantics to handle concurrent updates and removals correctly.
- **Text CRDT is separate from Sequence:** RGA is a specific sequence algorithm. Don't attempt Text without Sequence CRDT foundation.
- **Delta-CRDTs enhance all types:** Every state-based CRDT can have a delta variant. Build state-based first, add deltas as optimization.

## MVP Definition

### Launch With (v1)

Minimum viable product — essential for validation. Based on TEST.md comprehensive test cases and ecosystem analysis.

- [ ] **G-Counter** — Simplest CRDT, validates library works
- [ ] **PN-Counter** — Common use case (voting, quotas)
- [ ] **G-Set** — Foundation for more complex sets
- [ ] **2P-Set** — Simple removal support
- [ ] **OR-Set** — THE critical set type. Most applications need re-add after remove.
- [ ] **LWW-Register** — Already exists in ecosystem (lpil), but needed for completeness
- [ ] **MV-Register** — Enables semantic conflict resolution
- [ ] **LWW-Map** — Common key-value use case
- [ ] **Version Vector** — Essential infrastructure for OR-Set, OR-Map
- [ ] **Property-based tests** — Critical: verify merge laws (commutativity, associativity, idempotency, convergence)
- [ ] **JSON Serialization** — Essential for interoperability

### Add After Validation (v1.x)

Features to add once core works and user demand is clear.

- [ ] **OR-Map** — Nested CRDT values in maps. High demand for composing counters, sets in maps.
- [ ] **Delta-CRDT Support** — Performance optimization for replication. Users hit network efficiency limits.
- [ ] **Causal Context Utilities** — Efficient metadata handling for OR-Set/OR-Map serialization.
- [ ] **Operation-based Variants** — Lower bandwidth use cases.

### Future Consideration (v2+)

Features to defer until product-market fit is established.

- [ ] **Text CRDT (RGA)** — Collaborative text is complex. Only add when clear user need.
- [ ] **Sequence/List CRDT** — Foundation for text, but complex to get right.
- [ ] **Erlang Distribution Helpers** — Only if significant Erlang/OTP user demand.
- [ ] **Advanced Types** (Merkle-DAG Register, specialized counters) — Niche use cases.

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| G-Counter | HIGH | LOW | P1 |
| PN-Counter | HIGH | LOW | P1 |
| G-Set | HIGH | LOW | P1 |
| 2P-Set | MEDIUM | MEDIUM | P1 |
| OR-Set | VERY HIGH | HIGH | P1 |
| LWW-Register | HIGH | LOW | P1 |
| MV-Register | HIGH | MEDIUM | P1 |
| LWW-Map | HIGH | MEDIUM | P1 |
| OR-Map | HIGH | HIGH | P2 |
| Version Vector | HIGH | MEDIUM | P1 |
| JSON Serialization | HIGH | MEDIUM | P1 |
| Property-based Tests | VERY HIGH | HIGH | P1 |
| Delta-CRDT Support | MEDIUM | MEDIUM | P2 |
| Causal Context | MEDIUM | MEDIUM | P2 |
| Op-based Variants | MEDIUM | MEDIUM | P2 |
| Text CRDT | MEDIUM | VERY HIGH | P3 |
| Sequence CRDT | MEDIUM | HIGH | P3 |
| Erlang Distribution | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch (table stakes)
- P2: Should have, add when possible (differentiators)
- P3: Nice to have, future consideration (advanced)

## Competitor Feature Analysis

| Feature | rust-crdt (Rust) | Yjs (JS) | Loro (Rust/JS) | lpil/lww-register (Gleam) | Our Approach |
|---------|------------------|----------|----------------|---------------------------|--------------|
| G-Counter | ✅ | ✅ | ✅ | ❌ | P1 — implement |
| PN-Counter | ✅ | ✅ | ✅ | ❌ | P1 — implement |
| G-Set | ✅ | ✅ | ✅ | ❌ | P1 — implement |
| 2P-Set | ✅ | ✅ | ❌ | ❌ | P1 — implement |
| OR-Set | ✅ | ✅ (ORSet) | ✅ | ❌ | P1 — CRITICAL |
| LWW-Register | ✅ | ✅ | ✅ | ✅ EXISTING | P1 — already available |
| MV-Register | ✅ | ✅ | ✅ | ❌ | P1 — implement |
| LWW-Map | ✅ | ✅ (Y.Map) | ✅ | ❌ | P1 — implement |
| OR-Map | ✅ | ✅ (Y.Map nested) | ✅ | ❌ | P2 — implement |
| Version Vector | ✅ | ✅ | ✅ | ❌ | P1 — implement |
| Text/RGA | ❌ | ✅ | ✅ | ❌ | P3 — defer |
| Delta-CRDT | ✅ | ✅ | ✅ | ❌ | P2 — implement |
| JSON Serialization | ✅ (serde) | ✅ | ✅ | ❌ | P1 — companion package |
| Property Tests | ✅ (quickcheck) | ❌ | ❌ | ❌ | P1 — qcheck |

**Key insight:** No Gleam library provides comprehensive CRDTs. lpil's library only has LWW-Register. This is a genuine gap in the Gleam ecosystem.

## Sources

- **rust-crdt (crdts crate):** Apache-2.0 licensed, most downloaded Rust CRDT library (docs.rs, ~7.3.2)
- **Yjs:** 21k+ stars, de facto JS standard (GitHub, latest v14)
- **Loro:** High-performance Rust/JS CRDT, focus on text (loro.dev)
- **crdt-kit:** Edge-optimized CRDTs, no_std support (docs.rs)
- **diamond-types:** High-performance fork with Text CRDT (crates.io)
- **lpil/lww-register-crdt:** Only existing Gleam CRDT (Hex.pm)
- **organicdesign/crdts:** JavaScript CRDTs (GitHub)
- **CRDT Dictionary (2025):** Comprehensive field guide (iankduncan.com)
- **Project TEST.md:** Comprehensive test cases from rust-crdt, lasp-lang, riak_dt sources

---
*Feature research for: Lattice — CRDT Library for Gleam*
*Researched: 2026-02-28*
