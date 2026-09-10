# lattice_maps

Last-writer-wins and observed-remove CRDT maps for Gleam.

Use this package for typed, recursive CRDT maps. Both `ORMap(a)` and
`LWWMap(a)` store String keys and `Crdt(a)` children. ORMap joins concurrent
child edits within a generation; LWWMap selects one complete assignment.

## Installation

```sh
gleam add lattice_maps
```

## Quick example

```gleam
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map

pub fn main() {
  let documents: or_map.ORMap(String) =
    or_map.new(replica_id.new("node-a"), crdt.TextSpec)

  or_map.keys(documents)
  // -> []
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_maps/lww_map` | Last-writer-wins map of recursive CRDT child snapshots. |
| `lattice_maps/or_map` | Generation-aware observed-remove map of CRDT children. |
| `lattice_maps/crdt` | Generic state, delta, and recursive schema dispatch. |

## Notes

Each map uses one `CrdtSpec(a)`. `SequenceSpec` creates a generic Sequence;
`TextSpec` creates Text. `OrMapSpec(child_spec)` and
`LwwMapSpec(child_spec)` support recursive maps.
`LwwRegisterSpec(initial_value)` supplies the initial generic value.
Use an application tagged union for mixed payloads.

Updates and merges return errors for incompatible child schemas.
Rejected callbacks do not create or reactivate keys. The full-value
`update_with_delta` path sends the callback's complete child value; use
the sparse delta callback API for large Text or Sequence children.
`CrdtDelta(a)` distinguishes `StateDelta` from nested `OrMapChange`.

## Removal and identity

Within one ORMap generation, concurrent update/remove remains add-wins.
Re-adding a removed key starts a fresh default generation. Newer
generations replace older values, including concurrent old-generation
edits; concurrent re-adds choose one deterministic winner.

Bind loaded or received state to the local writer before editing.
Preserve historical IDs and write authors. Generation floors and current
inactive leaf history remain after key pruning; outer clocks do not
authorize inner Sequence/Text compaction.
An ORMap pruning vector must cover its namespaced membership tags, not
the logical writer's unrelated leaf counters.

LWWMap assignments use timestamp, tombstone precedence, and writer
identity for both local writes and merge. Equal timestamps are accepted
only above the prune floor: tombstones win, then the greater writer ID
selects a complete child snapshot. Generic child payloads are not ordered.
Use increasing timestamps for successive writes; reusing one timestamp
and writer for different active children returns `ConflictingWrite`.
Sparse leaf updates require an ORMap-only path.

## Replication and migration

Sparse receivers need a baseline or eventual delivery of required
deltas. Later Sequence edits can show an incomplete view until earlier
origins arrive. Duplicate and reordered complete delivery converges.

Modern maps use versioned schemas and lifecycle metadata. Import an
agreed legacy baseline and switch writers together; do not mix old map
deltas with modern generation resets. Legacy LWW String imports retain
their original tie keys. Existing standalone String leaf codecs keep
their formats.

LWWMap snapshots must contain at most one entry for each exact key.
Modern decoding and legacy import reject duplicate live entries,
tombstones, and live/tombstone pairs instead of resolving them by array
order. Snapshot producers must resolve each key before encoding. Key
identity is exact and is not Unicode-normalized.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_maps>
- Hex package: <https://hex.pm/packages/lattice_maps>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
