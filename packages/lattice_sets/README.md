# lattice_sets

Grow-only, two-phase, and observed-remove CRDT sets for Gleam.

Use this package when replicas need set membership that can be merged without coordination. Choose the set type based on whether elements can be removed and later re-added.

## Installation

```sh
gleam add lattice_sets
```

## Quick example

```gleam
import lattice_core/replica_id
import lattice_sets/or_set

pub fn main() {
  let node_a =
    or_set.new(replica_id.new("node-a"))
    |> or_set.add("alice")

  let node_b =
    or_set.new(replica_id.new("node-b"))
    |> or_set.add("bob")

  let merged = or_set.merge(node_a, node_b)

  or_set.contains(merged, "alice")
  // -> True
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_sets/g_set` | Grow-only set. Elements can be added but never removed. |
| `lattice_sets/two_p_set` | Two-phase set. Elements can be removed once and cannot be re-added. |
| `lattice_sets/or_set` | Observed-remove set. Elements can be added, removed, and re-added. |

## Notes

- All set modules expose `new`, `add`, `contains`, `value`, `merge`, `to_json`, and `from_json`.
- `two_p_set` and `or_set` also expose remove operations.
- Delta-state operations are available with `add_with_delta` and `remove_with_delta`.
- `or_set` also supports `diff`, `merge_with_diff`, `remove_all`, `remove_where`, `remove_with_bound`, and `prune`.

## Typed serialization

Use `to_json_with` and `from_json_with` with a payload encoder and decoder
to serialize sets of integers, records, or tagged unions. The String
`to_json` and `from_json` entry points retain their existing formats.

The generic ORSet format stores values with their causal tags in entries.
It does not convert arbitrary values into JSON object keys. Serialization
preserves tombstones, allocation state, and pruning metadata as well as
visible members.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_sets>
- Hex package: <https://hex.pm/packages/lattice_sets>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
