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
  let local = replica_id.new("node-a")
  let assert Ok(node_a) =
    sequence.insert_many(sequence.new(local), 0, ["hello", "world"])

  let assert Ok(node_b) =
    sequence.new(replica_id.new("node-b"))
    |> sequence.insert(0, "!")

  let merged = sequence.merge(node_a, node_b, local)

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
- Query helpers: `values`, `length`, and the read-only `replica_id`.
- Edits, `anchor_at`, and `resolve` return `Result` with typed errors. Handle errors for untrusted indexes or unknown anchor targets; the example asserts only known-valid operations.
- Delta-state variants (`*_with_delta`) return `Ok(#(updated, delta))`; apply a delta with `merge(state, delta, local_replica)`.
- `merge(a, b, replica)` requires the identity for subsequent local edits. `merge_as` is a forwarding alias. Either operand order produces the same full state for a fixed output identity. Independent writers must use distinct replica IDs.
- Decoded remote snapshots retain their serialized identity. Use `bind(state, local_id)` to adopt a snapshot without rebuilding it, or `merge` to combine it with local history.
- Position anchors: `anchor_at` (and the `start_anchor`/`end_anchor` sentinels) create a stable position that survives concurrent edits and merges, `resolve` maps it back to a current index, and `anchor_to_json`/`anchor_from_json` let anchors travel between replicas (e.g. shared cursors).
- `compact` reclaims space from tombstones and origins once a host-supplied stability frontier confirms no in-flight op can reference them, emitting a `ForwardingMap` so anchors and rebased ops keep resolving after the region shrinks.
- `merge`, `to_json`, and `from_json` round-trip the full CRDT state; convergence holds on both Erlang and JavaScript targets.

## Map composition

`lattice_maps/crdt.SequenceSpec` creates a `Sequence(a)` child in a typed
map. ORMap supports sparse sequence edits through nested ORMaps. Return
the leaf delta from `insert_with_delta`, `delete_with_delta`, or
`move_with_delta`, rather than its full updated state.

Sparse receivers need a baseline or eventual delivery of the required
history. A later edit alone cannot reconstruct earlier items. Map removal
and re-addition starts a fresh generation; superseded generations do not
merge into the new sequence.

Outer map pruning does not establish the stability frontier required by
`sequence.compact`. Keep inner compaction separate. LWWMap can also hold
a Sequence child, but its assignments select one complete snapshot.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_sequence>
- Hex package: <https://hex.pm/packages/lattice_sequence>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
