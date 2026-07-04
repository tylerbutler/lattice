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
  let node_a =
    text.new(replica_id.new("node-a"))
    |> text.insert(0, "Hello world")

  let node_b =
    text.new(replica_id.new("node-b"))
    |> text.append("!")

  let merged = text.merge(node_a, node_b)

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
- Fallible operations have `try_*` variants returning `Result`; the plain variants assert on invalid indexes. Range operations return `RangeError` when `0 <= start <= end <= length` does not hold.
- Delta-state variants (`*_with_delta`) return the updated text plus a delta that can be merged into other replicas, avoiding full-state sync.
- Cursor anchors: `anchor_at` creates a stable position that survives concurrent edits and merges, `resolve_anchor` maps it back to a current grapheme index, and `anchor_to_json`/`anchor_from_json` let anchors travel between replicas (e.g. shared cursors).
- `merge`, `to_json`, and `from_json` round-trip the full CRDT state using the canonical sequence JSON envelope.
- Backed by `lattice_sequence` stable item IDs, so concurrent edits converge deterministically on both Erlang and JavaScript targets.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_text>
- Hex package: <https://hex.pm/packages/lattice_text>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
