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
  let assert Ok(counter) =
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

Leaf CRDTs expose `op_with_delta` alongside their state-only operations.
Infallible operations return a state or `#(state, delta)`. Fallible operations
return `Result` around the state or tuple. The delta has the same CRDT type as
the state and uses the same `merge` function.

Sequence and text merges require `merge(a, b, local_id)` to select the identity
for later edits. `merge_as` remains an equivalent alias. Counter, sequence,
and text edits now return `Result` under their plain names; remove the former
`try_` prefix when upgrading, except for the distinct `try_substring` API.

`ORMapDelta(a)` represents changed map keys. `CrdtDelta(a)` keeps nested
ORMap changes separate from leaf state deltas, so a small Text or Sequence
edit need not send the whole child.

Sparse replication requires a baseline or eventual delivery of the required
deltas. Reordered and duplicate messages converge after that history arrives.
One later delta cannot reconstruct an arbitrary empty receiver. See `DEV.md`
and `examples/src/or_map_delta_websocket_example.gleam`.

## Typed map composition

The umbrella exports `Crdt(a)`, `CrdtSpec(a)`, `CrdtDelta(a)`, `ORMap(a)`,
`ORMapDelta(a)`, and `LWWMap(a)`. Both map types support recursive CRDT
children. A map uses one child specification; applications can use a tagged
payload union for mixed data.

ORMap joins concurrent child edits. After removal, a re-add starts a fresh
generation; the newest generation wins over older histories. Concurrent
update/removal within one generation remains add-wins. LWWMap instead
selects one complete child assignment by timestamp and writer.

Use the receiving writer's identity when adopting a snapshot. Map key
pruning does not authorize compaction of child Sequence/Text history.
Upgrading existing maps requires explicit legacy import and a coordinated
switch to the new protocol; see the root README migration guide.

Reference: Almeida, Shoker, Baquero — *Delta State Replicated Data Types*.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_crdt>
- Hex package: <https://hex.pm/packages/lattice_crdt>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
