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
//// - `lattice_sequence` — Generic sequence CRDT using YATA-style left/right origins
//// - `lattice_text` — Plain-text CRDT backed by `lattice_sequence`
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
//// import lattice_sequence/sequence
//// import lattice_text/text
//// ```
////
//// ## Delta-state replication
////
//// Every leaf CRDT exposes a delta-state mutator alongside its state-based
//// API. Each `op` of type `T -> args -> T` has a companion `op_with_delta`
//// of type `T -> args -> #(T, T)` that returns both the new state and a
//// small delta. The delta is itself a value of type `T` and merges into
//// remote replicas via the existing `merge` function — there is no separate
//// "apply delta" code path for leaf CRDTs.
////
//// `ORMap` exposes `update_with_delta`, `remove_with_delta`, `apply_delta`,
//// and `merge_deltas` for the composite case, with a dedicated `ORMapDelta`
//// type for type safety.
////
//// Delta merge is idempotent, commutative, and associative — safe under
//// at-least-once delivery, reconnects, and out-of-order arrival. This makes
//// delta-state CRDTs the natural foundation for websocket-based replication.
//// See `DEV.md` for the full convention and usage notes, and the
//// `examples/or_map_delta_websocket_example.gleam` example for a runnable
//// demo of two replicas exchanging deltas.
////
//// Reference: Almeida, Shoker, Baquero — *Delta State Replicated Data Types*.

pub const version = "2.0.0"
