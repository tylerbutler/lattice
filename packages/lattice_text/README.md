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
- Decoded remote snapshots retain their serialized identity. Merge them under your local identity before editing.
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
