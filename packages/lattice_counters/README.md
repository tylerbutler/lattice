# lattice_counters

Grow-only and positive-negative CRDT counters for Gleam.

Use this package when replicas need to count events independently and merge without coordination. Choose `g_counter` for counters that only increase, or `pn_counter` when values can increase and decrease.

## Installation

```sh
gleam add lattice_counters
```

## Quick example

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let node_a =
    g_counter.new(replica_id.new("node-a"))
    |> g_counter.increment(2)

  let node_b =
    g_counter.new(replica_id.new("node-b"))
    |> g_counter.increment(3)

  let merged = g_counter.merge(node_a, node_b)

  g_counter.value(merged)
  // -> 5
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_counters/g_counter` | Grow-only counter. Merges by taking the maximum count per replica. |
| `lattice_counters/pn_counter` | Positive-negative counter built from two grow-only counters. |

## Notes

- Both counters expose `new`, `merge`, `value`, `to_json`, and `from_json`.
- Use `increment_with_delta` and `decrement_with_delta` when you want to replicate only the delta from an operation.
- Deltas must be non-negative. The `try_*` functions return an error for negative deltas; the asserting functions panic if given invalid input.
- `PNCounter` computes its value as positive counts minus negative counts.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_counters>
- Hex package: <https://hex.pm/packages/lattice_counters>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
