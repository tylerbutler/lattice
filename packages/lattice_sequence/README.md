# lattice_sequence

Generic sequence CRDT for Gleam using YATA-style left/right origins.

Use this package when replicas need to edit a shared ordered list concurrently and converge without coordination. `lattice_sequence` handles arbitrary element types with index-based insert, delete, and move operations; for a text-specific API with grapheme handling, use `lattice_text` instead.

## Installation

```sh
gleam add lattice_sequence
```

## Quick example

```gleam
import lattice_core/replica_id
import lattice_sequence/sequence

pub fn main() {
  let node_a =
    sequence.new(replica_id.new("node-a"))
    |> sequence.insert(0, "hello")
    |> sequence.insert(1, "world")

  let node_b =
    sequence.new(replica_id.new("node-b"))
    |> sequence.insert(0, "!")

  let merged = sequence.merge(node_a, node_b)

  sequence.values(merged)
  // -> ["hello", "world", "!"]
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_sequence/sequence` | Generic list CRDT with stable item IDs, index-based editing, and single-winner move semantics. |

## Notes

- Editing operations: `insert`, `delete`, and `move`.
- Query helpers: `values` and `length`.
- Fallible operations have `try_*_with_delta` variants returning `Result`; the plain variants assert on invalid indexes.
- Delta-state variants (`*_with_delta`) return the updated sequence plus a delta that can be merged into other replicas, avoiding full-state sync.
- Position anchors: `anchor_at` (and the `start_anchor`/`end_anchor` sentinels) create a stable position that survives concurrent edits and merges, `resolve` maps it back to a current index, and `anchor_to_json`/`anchor_from_json` let anchors travel between replicas (e.g. shared cursors).
- `compact` reclaims space from tombstones and origins once a host-supplied stability frontier confirms no in-flight op can reference them, emitting a `ForwardingMap` so anchors and rebased ops keep resolving after the region shrinks.
- `merge`, `to_json`, and `from_json` round-trip the full CRDT state; convergence holds on both Erlang and JavaScript targets.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_sequence>
- Hex package: <https://hex.pm/packages/lattice_sequence>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
