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
- `compact` reclaims space from tombstones and origins once a host-supplied stability frontier confirms no in-flight op can reference them, emitting a `ForwardingMap` so anchors and rebased ops keep resolving after the region shrinks. It retains move records, including deleted movers and initial placements for inserts after moves, as replay-gap anchors.
- `merge`, `to_json`, and `from_json` round-trip the full CRDT state; convergence holds on both Erlang and JavaScript targets.

## Compacted edits and wire migration

Deleting or moving a block member does not recreate its discarded insertion
origins from its current neighbors. The item keeps unknown origins and its
position comes from the covered base order. Its delta is the **complete updated
snapshot**, including the frontier, covered membership, and forwardings.
This path can send O(document size) data. Edits whose insertion origins are
known still produce sparse deltas.

Do not strip this context or attach a frontier to a sparse delta. Merge treats
an absent ID covered by either input's frontier as reclaimed. A sparse edit
with a snapshot frontier could therefore remove unrelated items.

Merge preserves genuine origins supplied by older item copies, even when
another copy is a block. This can expand blocks back into full items; it does
not change the covered base order. A later compaction at an advancing frontier
can discard those origins again.

Sequence JSON now uses **v3**. Each full item requires `origin_provenance`:
`"known"` for genuine insertion origins or `"unknown"` for discarded origins.
Unknown origins must both be null, and the item's ID must be covered by the
snapshot frontier. Block and move encodings are unchanged. Older readers reject
v3. Text and map-wrapped sequence values also require v3-capable readers.

Use a coordinated, readers-first migration: pause old writers and queued delta
delivery, deploy v3-capable readers to every consumer, then resync every replica
from the same trusted history or snapshot before enabling v3 writers. Replace
old queued deltas with that baseline; do not mix old and new writers.

The decoder still accepts v1/v2 input under its existing base-order rules, but
must assume that a legacy full item's origins are genuine. Old extracted items
have no provenance marker and **cannot be repaired automatically**. If the
baseline might contain such edits, rebuild it from an uncompacted operation
history, or start a new document generation from agreed content. Loading and
re-encoding an ambiguous legacy snapshot is not a repair.

## Map composition

`lattice_maps/crdt.SequenceSpec` creates a `Sequence(a)` child in a typed
map. ORMap supports sparse sequence edits through nested ORMaps. Return
the leaf delta from `insert_with_delta`, `delete_with_delta`, or
`move_with_delta`, rather than its full updated state.

Receivers need a baseline or eventual delivery of the required
history. A later edit alone cannot reconstruct earlier items. Map removal
and re-addition starts a fresh generation; superseded generations do not
merge into the new sequence.

Outer map pruning does not establish the stability frontier required by
`sequence.compact`. Keep inner compaction separate, and retain full snapshot
deltas when editing unknown-origin compacted members. LWWMap can also hold
a Sequence child, but its assignments select one complete snapshot.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_sequence>
- Hex package: <https://hex.pm/packages/lattice_sequence>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
