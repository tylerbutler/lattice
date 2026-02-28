# Architecture Research: CRDT Library in Gleam

**Domain:** CRDT (Conflict-free Replicated Data Type) Library
**Researched:** 2026-02-28
**Confidence:** HIGH

## Standard Architecture

### System Overview

Based on analysis of established CRDT implementations (riak_dt, delta_crdt, Automerge, Yjs), CRDT libraries follow a layered architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                     User API Layer                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │ Counters │  │ Registers│  │   Sets   │  │   Maps   │   │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │
├───────┴─────────────┴─────────────┴─────────────┴──────────┤
│                   Composite Types Layer                      │
│  ┌──────────────────────────────────────────────────────┐   │
│  │            CRDT Map (Nested CRDT Values)              │   │
│  │         Sequence/List CRDTs (RGA, Logoot)            │   │
│  └──────────────────────────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                    Core Merge Engine                         │
│  ┌────────────────┐  ┌─────────────────────────────────┐   │
│  │ Version Vectors│  │  Merge Logic (C-A)              │   │
│  │ Causal Context │  │  (Idempotent, Commutative,      │   │
│  │                │  │   Associative)                    │   │
│  └────────────────┘  └─────────────────────────────────┘   │
├─────────────────────────────────────────────────────────────┤
│                  Serialization Layer                         │
│  ┌────────────────┐  ┌─────────────────────────────────┐   │
│  │ JSON Encoder   │  │ Binary Format (Optional)        │   │
│  └────────────────┘  └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation Pattern |
|-----------|----------------|----------------------|
| **Primitive CRDTs** | Individual data types (Counter, Register, Set) | Each type in its own module; `new()`, `update()`, `merge()`, `value()` functions |
| **Composite Map** | Container for nested CRDTs; composes primitives | Riak DT Map pattern — values must be CRDTs; merge propagates lattice inflation |
| **Sequence/List CRDT** | Ordered sequences (RGA, Logoot) | Complex; often deferred as advanced feature |
| **Version Vector** | Tracks causal history per replica | Foundation component; required for most sets/maps |
| **Merge Engine** | Core convergence logic | Pure functions; must verify C-A properties |
| **Serialization** | JSON encoding/decoding | Often companion package (keeps core dependency-free) |

## Recommended Project Structure

```
src/
├── lattice.gleam              # Main public API (re-exports)
├── lattice/
│   ├── counter.gleam         # G-Counter, PN-Counter
│   ├── register.gleam        # LWW-Register (Last-Writer-Wins)
│   ├── set/
│   │   ├── or_set.gleam     # OR-Set (Observed-Remove Set)
│   │   └── g_set.gleam      # G-Set (Grow-only Set)
│   ├── map/
│   │   └── crdt_map.gleam   # CRDT Map (composable)
│   ├── sequence/
│   │   └── rga.gleam        # RGA (Replicated Growable Array) - advanced
│   ├── version_vector.gleam # Causal tracking
│   └── internal/
│       ├── merge.gleam      # Shared merge logic
│       └── types.gleam      # Shared types (Tag, Epoch, etc.)
test/
├── lattice_test.gleam
├── property/
│   ├── counter_properties.gleam  # Verify merge laws
│   ├── register_properties.gleam
│   └── set_properties.gleam
└── test_helpers.gleam
```

### Structure Rationale

- **`lattice/` root:** Follows Gleam convention for submodules
- **`set/`, `map/`, `sequence/` folders:** Groups related CRDT types
- **`counter.gleam`:** Contains both G-Counter and PN-Counter (similar complexity)
- **`internal/merge.gleam:** DRY principle — shared merge utilities
- **Property tests in `property/`:** Distinguishes unit tests from property-based verification

## Architectural Patterns

### Pattern 1: State-Based (CvRDT) CRDTs

**What:** Each CRDT carries its full state; merge is a binary operation on states.
**When to use:** Default for Lattice — simpler to reason about, works well for small-medium states.
**Trade-offs:** + Simple to implement; + Easy to verify; - Full state transfer on every sync

```gleam
// Counter state is just an integer
type GCounter {
  GCounter(count: Int)
}

// Merge is max (join-semilattice)
pub fn merge(a: GCounter, b: GCounter) -> GCounter {
  GCounter(count: int.max(a.count, b.count))
}
```

### Pattern 2: Delta-State CRDTs

**What:** Send only the "delta" (changes) rather than full state.
**When to use:** Large CRDTs; frequent synchronization.
**Trade-offs:** + More efficient sync; + Better for distributed systems; - More complex implementation (see delta_crdt_ex)

### Pattern 3: Composable CRDTs via Lattice Inflation

**What:** Map values are themselves CRDTs; map merge propagates to nested values.
**When to use:** When users need nested/composite data structures.
**Trade-offs:** + Powerful composability; + Matches JSON structure; - Requires all values be CRDTs

```gleam
// From riak_dt_map paper: "values in the Map data structure are also 
// state-based CRDTs and updates to embedded values preserve their 
// convergence semantics via lattice inflations"
```

### Pattern 4: Observed-Remove Set (OR-Set)

**What:** Each element has unique tags; remove marks elements as tombstoned.
**When to use:** Sets where elements can be added and removed.
**Trade-offs:** + Handles concurrent add/remove; - More complex than G-Set

## Data Flow

### Local Update Flow

```
[User calls: counter.increment(crdt)]
    ↓
[CRDT module: new_state = apply_operation(old_state, op)]
    ↓
[Return updated CRDT]
```

### Merge Flow

```
[Two CRDTs need to merge: crdt_a, crdt_b]
    ↓
[Call merge(crdt_a, crdt_b)]
    ↓
[Compute join-semilattice: result = merge_impl(state_a, state_b)]
    ↓
[Return merged CRDT with causal context updated]
```

### Sync Flow (Out of Scope for Core Library)

```
[External sync protocol delivers CRDT payload]
    ↓
[Library user calls: merge(local_crdt, remote_crdt)]
    ↓
[Returns converged CRDT]
```
**Note:** Lattice explicitly outsources networking. The library provides the merge function; transport/gossip is user-provided.

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single user, local | Simple in-memory CRDTs sufficient |
| Multiple devices, same user | Version vectors required for causal ordering |
| Multiple users, same document | CRDT Map composition; consider delta-state for large states |
| High-frequency updates | Delta CRDTs become valuable; batching strategies |

### Scaling Priorities

1. **First bottleneck: State size.** Full state transfer becomes expensive.
   - **Mitigation:** Implement delta-state variant when needed
   
2. **Second bottleneck: Causal context growth.** Version vectors grow with replica count.
   - **Mitigation:** GC/compact mechanisms; consider Dotted Version Vectors

3. **Third bottleneck: Merge computation.** Complex nested CRDTs take time to merge.
   - **Mitigation:** Optimize hot paths; lazy evaluation for deep structures

## Anti-Patterns

### Anti-Pattern 1: Mutable State in Merge

**What people do:** Store CRDT state in a process/agent and mutate during merge.
**Why it's wrong:** Merge must be pure and idempotent; mutable state breaks this.
**Do this instead:** Treat CRDTs as immutable values; `merge(a, b)` returns new value.

### Anti-Pattern 2: Using Wall-Clock Timestamps for Ordering

**What people do:** Use `Date.now()` for LWW-Register timestamps.
**Why it's wrong:** Clocks drift; NTP can cause jumps; breaks commutativity guarantees.
**Do this instead:** Require explicit timestamp/epoch from caller (as Lattice project specifies).

### Anti-Pattern 3: Missing Merge Law Verification

**What people do:** Implement merge without testing C-A properties.
**Why it's wrong:** CRDTs only guarantee convergence if merge is C-A-I (Commutative, Associative, Idempotent).
**Do this instead:** Property-based tests that verify merge laws for all types.

### Anti-Pattern 4: Cramming Everything into One Module

**What people do:** Put all CRDT types in a single file.
**Why it's wrong:** Hard to maintain; impossible to verify individually; hurts compilation.
**Do this instead:** One module per CRDT type or family.

## Integration Points

### External Services (Out of Scope)

| Service | Integration Pattern | Notes |
|---------|--------------------|-------|
| **Erlang Distribution** | Gossip protocol for anti-entropy | Not included; user implements |
| **WebSocket/Network** | Sync protocol | Not included; user implements |
| **Database** | Serialization for persistence | JSON encoder in companion package |
| **UI Frameworks** | State subscription | Not included; consumer implements |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Primitive → Composite | Composite passes merge to nested values | Map merge calls `merge(value_a, value_b)` |
| Version Vector → CRDTs | Passed as implicit context | Every merge needs to update causal history |
| Serialization → Core | Encoder/decoder return CRDT values | Must handle all type variants |

## Build Order (Dependencies)

Based on component dependencies, recommended implementation order:

```
1. version_vector.gleam        ← Foundation (no dependencies)
2. counter.gleam               ← Simplest CRDT; verifies merge works
3. register.gleam              ← Adds timestamp handling
4. g_set.gleam                 ← Simple set; no tombstones needed
5. or_set.gleam                ← Complex set; requires tags + tombstones
6. crdt_map.gleam              ← Composes primitives; validates pattern
7. serialization (optional)    ← Depends on all types being stable
8. rga.gleam (advanced)        ← Most complex; defer until core stable
```

### Rationale

- **Version vector first:** Every other CRDT needs it for causal ordering
- **Counter first:** Simplest to implement and test; validates the build system
- **Counter → Register:** Register adds timestamp handling
- **Simple sets → Complex sets:** G-Set is trivial; OR-Set adds significant complexity
- **Map late:** Needs all primitives to be composable
- **RGA last:** Most complex; requires everything else to work first

## Sources

- **delta_crdt_ex** (HexDocs): Delta CRDT implementation in Elixir — inspiration for structure
  - https://hexdocs.pm/delta_crdt/DeltaCrdt.html
  
- **riak_dt** (GitHub): Original Erlang CRDT library; source of composable Map pattern
  - https://github.com/basho/riak_dt
  - Paper: "Riak DT Map: A Composable, Convergent Replicated Dictionary"

- **Automerge** (automerge.org): Modern Rust CRDT with clear separation of concerns
  - https://automerge.org/docs/quickstart/
  - https://github.com/automerge/automerge

- **crdt.tech Implementations Page**: Comprehensive list of CRDT libraries
  - https://crdt.tech/implementations

- **"A Comprehensive Study of Convergent and Commutative Replicated Data Types"** (Shapiro et al.): Foundational paper

---

*Architecture research for: CRDT Library in Gleam*
*Researched: 2026-02-28*
