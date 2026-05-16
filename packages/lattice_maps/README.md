# lattice_maps

Last-writer-wins and observed-remove CRDT maps for Gleam.

Use this package when replicas need key/value data that can be merged without coordination. `lww_map` stores string values with timestamp conflict resolution; `or_map` stores nested CRDT values with observed-remove key semantics.

## Installation

```sh
gleam add lattice_maps
```

## Quick example

```gleam
import lattice_maps/lww_map

pub fn main() {
  let map =
    lww_map.new()
    |> lww_map.set("status", "draft", 1)
    |> lww_map.set("status", "published", 2)

  lww_map.get(map, "status")
  // -> Ok("published")
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_maps/lww_map` | Last-writer-wins map for string keys and string values. |
| `lattice_maps/or_map` | Observed-remove map whose values are nested CRDTs. |
| `lattice_maps/crdt` | Tagged union and specs used by `or_map` to store heterogeneous CRDT values. |

## Notes

- `lww_map` exposes `new`, `set`, `get`, `remove`, `keys`, `values`, `merge`, `prune`, `to_json`, and `from_json`.
- `or_map` exposes `new`, `update`, `get`, `remove`, `keys`, `values`, `merge`, `prune`, `to_json`, and `from_json`.
- `or_map.merge` returns a `Result` because maps with incompatible nested CRDT specs cannot be merged.
- `or_map` supports delta-state replication with `update_with_delta`, `remove_with_delta`, `apply_delta`, `merge_deltas`, `delta_to_json`, and `delta_from_json`.
- `crdt.CrdtSpec` controls the default nested CRDT created for new keys.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_maps>
- Hex package: <https://hex.pm/packages/lattice_maps>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
