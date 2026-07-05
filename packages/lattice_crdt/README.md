# lattice_crdt

Umbrella package for Lattice CRDTs: counters, registers, sets, maps, and causal core types.

Install this package when you want the full Lattice CRDT toolkit. For smaller dependency graphs, install the individual packages directly.

## Installation

```sh
gleam add lattice_crdt
```

## Packages included

| Package | Provides |
|---------|----------|
| `lattice_core` | Replica IDs, version vectors, and dot contexts. |
| `lattice_counters` | Grow-only and positive-negative counters. |
| `lattice_registers` | Last-writer-wins and multi-value registers. |
| `lattice_sets` | Grow-only, two-phase, and observed-remove sets. |
| `lattice_maps` | Last-writer-wins maps, observed-remove maps, and CRDT dispatch. |
| `lattice_sequence` | Generic sequence CRDT using YATA-style left/right origins. |
| `lattice_text` | Plain-text CRDT backed by `lattice_sequence`. |

## Quick example

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let counter =
    g_counter.new(replica_id.new("node-a"))
    |> g_counter.increment(1)

  g_counter.value(counter)
  // -> 1
}
```

## Notes

- This package reuses the public modules from the individual Lattice packages.
- Import modules from their package-specific paths, such as `lattice_counters/g_counter` or `lattice_sets/or_set`.
- All CRDT packages support deterministic merge semantics and JSON serialization.
- Many mutators also expose delta-state variants for efficient incremental replication.

## Delta-state replication

Every leaf CRDT exposes a delta-state mutator alongside its state-based API. Each `op` of type `T -> args -> T` has a companion `op_with_delta` of type `T -> args -> #(T, T)` that returns both the new state and a small delta. The delta is itself a value of type `T` and merges into remote replicas via the existing `merge` function — there is no separate "apply delta" code path for leaf CRDTs.

`ORMap` exposes `update_with_delta`, `remove_with_delta`, `apply_delta`, and `merge_deltas` for the composite case, with a dedicated `ORMapDelta` type for type safety.

Delta merge is idempotent, commutative, and associative — safe under at-least-once delivery, reconnects, and out-of-order arrival. This makes delta-state CRDTs the natural foundation for websocket-based replication. See `DEV.md` for the full convention and usage notes, and the `examples/or_map_delta_websocket_example.gleam` example for a runnable demo of two replicas exchanging deltas.

Reference: Almeida, Shoker, Baquero — *Delta State Replicated Data Types*.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_crdt>
- Hex package: <https://hex.pm/packages/lattice_crdt>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
