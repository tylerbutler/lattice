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
records, or tagged unions. The `to_json` and `from_json` entry points
use String payloads.

An LWWRegister stores the author of its winning write. Loading or merging a
register on another replica does not change that author. Every `set` and
`set_with_delta` call requires the local writer ID so a new write cannot inherit
the remote winner's identity.

### LWWRegister snapshot migration

LWWRegister encoders now emit version 3. Its state contains `value`, `timestamp`,
`replica_id`, and `provenance`: `{"kind":"modern"}` for authored writes, or
`{"kind":"legacy","tie_key":"..."}` for imported v1 writes. Upgrade every
reader before enabling v3 output; older readers reject it. This also applies
to register snapshots carried inside map snapshots or dispatch deltas.

The String `from_json` imports v1 using the original String value as its tie
key. Higher timestamps win first. At equal timestamps, modern writes beat
legacy writes; two legacy writes compare keys in UTF-8 byte order on both
targets. Equal legacy keys use the existing replica ID ordering as a final
metadata tie-break. An optional v1 writer is retained, not erased; a missing
writer uses `""`. V3 preserves the original key rather than recomputing it from
the decoded payload. `set` still requires a strictly greater timestamp and turns
an accepted write into a modern write with the supplied local author.

Generic `from_json_with` now rejects v1. Use
`import_legacy_with(input, decoder, tie_key)` explicitly:

```gleam
import gleam/dynamic/decode
import gleam/int
import lattice_registers/lww_register

pub fn import_integer_snapshot(input: String) {
  lww_register.import_legacy_with(input, decode.int, int.to_string)
}
```

All replicas must use the same deterministic key function. Keys must distinguish
different payloads at the same timestamp; equal keys must mean equal payloads.
This is a String ordering key, not a numeric comparator or a writer ID.
After import, save and exchange the v3 snapshot to preserve its key.

Valid v2 snapshots remain modern, including an empty-but-present `replica_id`.
V2 still requires that field to contain a string; missing, null, and non-string
IDs are errors. V3 also requires valid provenance. An empty ID does not prove a
legacy origin. If an old reader already re-encoded v1 as v2, the legacy
provenance was lost. Recover a verified v1 baseline from backups or external
history, then import it explicitly under an agreed migration policy. Do not
reclassify all empty-writer v2 data as legacy or mix that migration with
uncoordinated old writers.

String `crdt.from_json` uses the register's String import path.
`crdt.from_json_with`, recursive map child decoding, and typed dispatch delta
decoding use the generic path and reject embedded v1 registers. Import each
legacy child explicitly, then encode v3 before constructing the modern
container. Producers of incomplete v2 snapshots need an application-specific
policy to recover the actual winning writer; the decoder does not invent it.

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
