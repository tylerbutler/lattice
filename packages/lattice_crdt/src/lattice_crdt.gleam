//// lattice_crdt is an umbrella package that re-exports all lattice CRDT
//// sub-packages for convenient dependency management.
////
//// ## Sub-packages
////
//// - `lattice_core` — Version vectors, dot contexts, and causal infrastructure
//// - `lattice_counters` — Grow-only counters (GCounter) and positive-negative counters (PNCounter)
//// - `lattice_registers` — Last-writer-wins registers (LWWRegister) and multi-value registers (MVRegister)
//// - `lattice_sets` — Grow-only sets (GSet), two-phase sets (TwoPSet), and observed-remove sets (ORSet)
//// - `lattice_maps` — Last-writer-wins maps (LWWMap), observed-remove maps (ORMap), and CRDT dispatch
//// - `lattice_text` — Plain-text CRDT using YATA-style left/right origins
////
//// ## Usage
////
//// Depend on `lattice_crdt` to get all sub-packages, or depend on individual
//// sub-packages for minimal dependencies.
////
//// ```gleam
//// // Import from individual sub-packages:
//// import lattice_counters/g_counter
//// import lattice_sets/or_set
//// import lattice_maps/or_map
//// import lattice_text/text
//// ```

pub const version = "2.0.0"
