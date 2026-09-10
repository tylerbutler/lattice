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
    |> lww_register.set("published", 2, node_a)

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

- `LWWRegister` exposes `new`, `set`, `set_with_delta`, `merge`, `value`, `timestamp`, `replica_id`, `to_json`, and `from_json`.
- `MVRegister` exposes `new`, `set`, `set_with_delta`, `merge`, `value`, `to_json`, and `from_json`.
- Labeled calls to LWW-register `new`, `set`, and `set_with_delta` use `value:` instead of the former `val:` label. Positional calls are unchanged.
- Use `LWWRegister` when a deterministic winner is acceptable.
- Use `MVRegister` when application code should resolve concurrent writes.

## Typed payloads and local authors

Both register types accept generic payloads. Use `to_json_with` and
`from_json_with` with your payload encoder and decoder for integers,
records, or tagged unions. The existing `to_json` and `from_json` entry
points retain their String formats.

An LWWRegister stores the author of its winning write. Loading or merging a
register on another replica does not change that author. Every `set` and
`set_with_delta` call requires the local writer ID so a new write cannot inherit
the remote winner's identity.

Do not reuse the same timestamp and replica ID for different values. After a
restart, generate a fresh replica ID or restore a durable logical clock that
advances beyond every prior write from that ID.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_registers>
- Hex package: <https://hex.pm/packages/lattice_registers>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
