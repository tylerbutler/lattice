# lattice_registers

Last-writer-wins and multi-value CRDT registers for Gleam.

Use this package when replicas need to store a single logical value and resolve concurrent writes deterministically or explicitly expose conflicts.

## Installation

```sh
gleam add lattice_registers
```

## Quick example

```gleam
import lattice_core/replica_id
import lattice_registers/lww_register

pub fn main() {
  let node_a = replica_id.new("node-a")

  let register =
    lww_register.new("draft", 1, node_a)
    |> lww_register.set("published", 2)

  lww_register.value(register)
  // -> "published"
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_registers/lww_register` | Last-writer-wins register. Higher timestamps win; equal timestamps use replica ID tie-breaking. |
| `lattice_registers/mv_register` | Multi-value register. Concurrent writes are preserved as multiple values. |

## Notes

- `LWWRegister` exposes `new`, `set`, `set_with_delta`, `merge`, `value`, `to_json`, and `from_json`.
- `MVRegister` exposes `new`, `set`, `set_with_delta`, `merge`, `value`, `to_json`, and `from_json`.
- Use `LWWRegister` when a deterministic winner is acceptable.
- Use `MVRegister` when application code should resolve concurrent writes.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_registers>
- Hex package: <https://hex.pm/packages/lattice_registers>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
