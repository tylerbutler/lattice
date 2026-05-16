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

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_crdt>
- Hex package: <https://hex.pm/packages/lattice_crdt>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
