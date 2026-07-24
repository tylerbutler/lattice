//// lattice_crdt is an umbrella package that re-exports the core lattice
//// CRDT sub-packages for convenient dependency management. Not every
//// lattice package is included: `lattice_fugue`, `lattice_text_fugue`,
//// `lattice_text_core`, and `lattice_presence` are separate dependencies.
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
//// sub-packages for minimal dependencies. This module re-exports the primary
//// type from each sub-package so a single `import lattice_crdt` gives access
//// to the full family of CRDT types; use the sub-package modules directly for
//// their constructors and operations.
////
//// ```gleam
//// // Import from individual sub-packages for constructors and operations:
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

import lattice_core/dot_context
import lattice_core/replica_id
import lattice_core/version_vector
import lattice_counters/g_counter
import lattice_counters/pn_counter
import lattice_maps/crdt
import lattice_maps/lww_map
import lattice_maps/or_map
import lattice_registers/lww_register
import lattice_registers/mv_register
import lattice_sequence/sequence
import lattice_sets/g_set
import lattice_sets/or_set
import lattice_sets/two_p_set
import lattice_text/text

/// A version vector for tracking causal history across replicas.
pub type VersionVector =
  version_vector.VersionVector

/// A causal context of observed dots, used by observed-remove CRDTs.
pub type DotContext =
  dot_context.DotContext

/// A stable identifier for a replica.
pub type ReplicaId =
  replica_id.ReplicaId

/// A grow-only counter.
pub type GCounter =
  g_counter.GCounter

/// A positive-negative counter composed of two grow-only counters.
pub type PNCounter =
  pn_counter.PNCounter

/// A last-writer-wins register.
pub type LWWRegister(a) =
  lww_register.LWWRegister(a)

/// A multi-value register that preserves concurrent writes.
pub type MVRegister(a) =
  mv_register.MVRegister(a)

/// A grow-only set.
pub type GSet(a) =
  g_set.GSet(a)

/// A two-phase set supporting removal via a tombstone set.
pub type TwoPSet(a) =
  two_p_set.TwoPSet(a)

/// An observed-remove set.
pub type ORSet(a) =
  or_set.ORSet(a)

/// A last-writer-wins map.
pub type LWWMap =
  lww_map.LWWMap

/// An observed-remove map holding heterogeneous CRDT values.
pub type ORMap =
  or_map.ORMap

/// A tagged union over the leaf CRDT types, used for uniform merging.
pub type Crdt =
  crdt.Crdt

/// A specification used to auto-create default CRDT values for new keys.
pub type CrdtSpec =
  crdt.CrdtSpec

/// A generic sequence CRDT.
pub type Sequence(a) =
  sequence.Sequence(a)

/// A plain-text CRDT backed by a sequence.
pub type Text =
  text.Text
