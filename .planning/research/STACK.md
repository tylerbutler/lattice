# Technology Stack

**Project:** Lattice — CRDT Library for Gleam
**Researched:** 2026-02-28
**Confidence:** HIGH

## Recommended Stack

### Core Language
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Gleam | 1.14.0 | Language | Project's pinned version. Strong static typing, compiles to Erlang and JavaScript natively. Zero-cost abstractions and expressive ADTs ideal for CRDTs. |
| gleam_stdlib | >= 0.69.0 | Standard library | Provides Dict, List, Set, Result, Option types needed for CRDT implementations. No runtime dependencies per project requirement. |

### Serialization (Companion Package)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| gleam_json | >= 3.0.2 | JSON encoding/decoding | Official Gleam JSON library (Apache-2.0). Most downloaded (299K all-time). Used in companion package per project requirement to keep core dependency-free. |

### Testing (Dev Dependencies)
| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| gleeunit | >= 1.9.0 | Unit testing framework | Standard Gleam testing framework. Uses EUnit on Erlang, custom runner on JS. 1.25M+ downloads. Required for basic test coverage. |
| qcheck | >= 1.0.4 | Property-based testing | QuickCheck-inspired property testing with integrated shrinking. CRITICAL for verifying CRDT laws (commutativity, associativity, idempotency, convergence). Supports cross-target testing. |

### Cross-Target Utilities
| Technology | Purpose | When to Use |
|------------|---------|-------------|
| @external attribute | Target-specific implementations | For any performance-critical code needing different implementations per target |
| gleam_otp | OTP abstractions | Only if adding Erlang distribution helpers (gossip, anti-entropy) — then must be Erlang-only |

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| JSON library | gleam_json | gserde (codegen) | gserde is alpha quality with "poor code hygiene" (assert/panic statements). gleam_json is stable, official, and well-maintained. |
| Testing | gleeunit + qcheck | showtime | Showtime offers parallel execution and diffs but adds complexity. gleeunit + qcheck is the established standard with better ecosystem support. |
| Property testing | qcheck | Manual random testing | qcheck provides shrinking, which is essential for debugging CRDT property failures. |
| Core stdlib | gleam_stdlib | bar_solver | Not needed — CRDTs are implemented with standard collection types. |

## Installation

```bash
# Core dependencies (matches project requirement: zero runtime deps beyond stdlib)
gleam add gleam_stdlib

# JSON support (companion package)
gleam add gleam_json

# Dev dependencies
gleam add gleeunit --dev
gleam add qcheck --dev
```

## Cross-Target Strategy

### What Works on Both Targets
- **Pure Gleam code**: All CRDT implementations (G-Counter, PN-Counter, G-Set, 2P-Set, OR-Set, LWW-Register, MV-Register, LWW-Map, OR-Map, Version Vectors)
- **Immutable data structures**: Dict, List, Set from gleam_stdlib
- **Property tests**: qcheck runs on both targets

### What Requires Target-Specific Code
- **Erlang distribution** (gossip protocols): Would require `@external(erlang, ...)`
- **Timer/clock functions**: If using wall-clock timestamps, might need externals
- **Performance optimizations**: Dictionary/Set internals could benefit from target-specific implementations

### Recommended Pattern
```gleam
// For pure cross-target CRDTs, no externals needed:
pub fn merge(a: CRDT, b: CRDT) -> CRDT {
  // Pure Gleam — works on both targets
}

// For Erlang-only features:
@external(erlang, "lattice_erlang", "gossip_broadcast")
pub fn gossip_broadcast(state: CRDT) -> Nil

// For JS-only features (if needed):
@external(javascript, "./lattice_jsffi.mjs", "some_js_function")
pub fn some_js_function() -> Value
```

## Sources

- **gleam_stdlib**: Hex.pm (v0.69.0, Feb 2026) — https://hex.pm/packages/gleam_stdlib
- **gleam_json**: Hex.pm (v3.0.2, Jul 2025) — https://hex.pm/packages/gleam_json
- **gleeunit**: Hex.pm (v1.9.0, Nov 2025) — https://hex.pm/packages/gleeunit
- **qcheck**: Hex.pm (v1.0.4, Feb 2026) — https://hex.pm/packages/qcheck
- **Gleam language tour — multi-target externals**: https://tour.gleam.run/advanced-features/multi-target-externals/
- **Existing CRDT library**: lpil/lww-register-crdt — https://github.com/lpil/lww-register-crdt
- **Gleam cross-target compatibility**: WebSearch verified via official docs

## Confidence Assessment

| Area | Level | Reason |
|------|-------|--------|
| Core language | HIGH | Gleam 1.14.0 is project-pinned version |
| Testing frameworks | HIGH | gleeunit and qcheck are the established standard in Gleam ecosystem |
| JSON library | HIGH | gleam_json is the official, most-used JSON library |
| Cross-target approach | HIGH | Verified via official Gleam documentation |
| Property-based testing for CRDTs | MEDIUM | qcheck supports the required generators; CRDT-specific patterns need validation |
