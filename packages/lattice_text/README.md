# lattice_text

Plain-text CRDT for Gleam using YATA-style left/right origins.

Use this package when replicas need to edit shared text concurrently and converge without coordination. All operations are grapheme-based, so emoji and combining sequences count as one unit. For a generic list CRDT, use `lattice_sequence` directly.

## Installation

```sh
gleam add lattice_text
```

## Quick example

```gleam
import lattice_core/replica_id
import lattice_text/text

pub fn main() {
  let local = replica_id.new("node-a")
  let assert Ok(node_a) =
    text.new(local)
    |> text.insert(0, "Hello world")

  let assert Ok(node_b) =
    text.new(replica_id.new("node-b"))
    |> text.append("!")

  let merged = text.merge(node_a, node_b, local)

  text.value(merged)
  // -> "Hello world!"
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_text/text` | Grapheme-based text CRDT with editing, range, and delta operations. |

## Notes

- Editing operations: `insert`, `delete`, `delete_range`, `replace_range`, `move`, and `append`.
- Query helpers: `value`, `values`, `length`, `substring`, and `try_substring`.
- Edits (including `append`), `anchor_at`, and `resolve_anchor` return `Result`. Range operations return `RangeError` when `0 <= start <= end <= length` does not hold. Handle errors for untrusted inputs; the example asserts only known-valid operations.
- `substring` still clamps bounds; `try_substring` retains its strict `Result` contract.
- Delta-state variants (`*_with_delta`) return `Ok(#(updated, delta))`; apply a delta with `merge(state, delta, local_replica)`.
- `merge(a, b, replica)` requires the identity for subsequent local edits. `merge_as` is a forwarding alias. Either operand order produces the same full state for a fixed output identity. Independent writers must use distinct replica IDs.
- Decoded remote snapshots retain their serialized identity. Use `bind(state, local_id)` to adopt a snapshot without rebuilding it, or `merge` to combine it with local history.
- Cursor anchors: `anchor_at` creates a stable position that survives concurrent edits and merges, `resolve_anchor` maps it back to a current grapheme index, and `anchor_to_json`/`anchor_from_json` let anchors travel between replicas (e.g. shared cursors).
- `merge`, `to_json`, and `from_json` round-trip the full CRDT state using the canonical sequence JSON envelope.
- Backed by `lattice_sequence` stable item IDs, so concurrent edits converge deterministically on both Erlang and JavaScript targets.

## Compacted edits and migration

Deletes and moves of compacted graphemes with unknown insertion origins return
the complete updated snapshot as their delta. Range deletes and replacements
can also take this path. These deltas can cost O(document size); keep their
frontier, covered membership, and forwardings intact.

Text now writes the sequence **v3** envelope with explicit origin provenance.
Upgrade all readers before enabling v3 writers, pause legacy delta delivery,
and resync replicas from one trusted baseline. Legacy extracted origins are
ambiguous and cannot be repaired by decoding and re-encoding a snapshot.
See [the sequence migration notes](../lattice_sequence/README.md#compacted-edits-and-wire-migration)
for the full migration contract, including map-wrapped values.

## Map composition

`lattice_maps/crdt.TextSpec` creates an empty Text child. Use ORMap when
concurrent child edits must merge; use its sparse callback with the delta
from a Text `*_with_delta` operation. Ordinary deltas remain sparse through
nested ORMap paths; edits of unknown-origin compacted graphemes carry the full
inner snapshot.

Map re-addition creates a fresh generation with a new editing namespace.
Newer generations replace older content. A LWWMap Text assignment instead
replaces a whole snapshot and does not merge losing concurrent edits.

Text dispatch uses a distinct wrapper around this package's sequence v3
JSON envelope. Do not infer Text from a bare Sequence envelope.
Outer map clocks do not authorize inner sequence compaction.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_text>
- Hex package: <https://hex.pm/packages/lattice_text>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
