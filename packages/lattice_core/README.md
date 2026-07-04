# lattice_core

Core causal infrastructure for Lattice CRDT packages: replica IDs, version vectors, and dot contexts.

Use this package when you are building CRDTs directly or need to track causality for a custom replicated data type. Most application code can install higher-level packages such as `lattice_counters`, `lattice_sets`, or the umbrella `lattice_crdt` package instead.

## Installation

```sh
gleam add lattice_core
```

## Quick example

```gleam
import lattice_core/replica_id
import lattice_core/version_vector

pub fn main() {
  let node_a = replica_id.new("node-a")
  let node_b = replica_id.new("node-b")

  let local =
    version_vector.new()
    |> version_vector.increment(node_a)

  let remote =
    version_vector.new()
    |> version_vector.increment(node_b)

  version_vector.compare(local, remote)
  // -> version_vector.Concurrent
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_core/replica_id` | Opaque replica identifiers with ordering and JSON helpers. |
| `lattice_core/version_vector` | Logical clocks for comparing, merging, and serializing causal state. |
| `lattice_core/dot_context` | Dot sets for observed-remove data structures. |

## Notes

- `VersionVector` supports `increment`, `get`, `compare`, `dominates`, `set_max`, `merge`, `to_json`, and `from_json`.
- `DotContext` tracks observed dots and supports add, remove, and containment checks.
- Replica IDs are opaque; create them with `replica_id.new("node-a")`.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_core>
- Hex package: <https://hex.pm/packages/lattice_core>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
