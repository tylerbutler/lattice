<p align="center">
  <img src="https://lattice.tylerbutler.com/lattice-min.webp" alt="lattice logo" width="25%" />
</p>

<h1 align="center">LATTICE</h1>

<p align="center">
Conflict-free replicated data types (CRDTs) for Gleam. Tested with property-based tests, targeting both Erlang and JavaScript runtimes.
</p>

## Packages

| Package | Version | Docs | Description |
|---------|---------|------|-------------|
| [`lattice_crdt`](https://hex.pm/packages/lattice_crdt) | [![](https://img.shields.io/hexpm/v/lattice_crdt)](https://hex.pm/packages/lattice_crdt) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_crdt/) | Umbrella — all CRDT types |
| [`lattice_counters`](https://hex.pm/packages/lattice_counters) | [![](https://img.shields.io/hexpm/v/lattice_counters)](https://hex.pm/packages/lattice_counters) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_counters/) | GCounter, PNCounter |
| [`lattice_sets`](https://hex.pm/packages/lattice_sets) | [![](https://img.shields.io/hexpm/v/lattice_sets)](https://hex.pm/packages/lattice_sets) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_sets/) | GSet, TwoPSet, ORSet |
| [`lattice_registers`](https://hex.pm/packages/lattice_registers) | [![](https://img.shields.io/hexpm/v/lattice_registers)](https://hex.pm/packages/lattice_registers) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_registers/) | LWWRegister, MVRegister |
| [`lattice_maps`](https://hex.pm/packages/lattice_maps) | [![](https://img.shields.io/hexpm/v/lattice_maps)](https://hex.pm/packages/lattice_maps) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_maps/) | LWWMap, ORMap, Crdt dispatch |
| [`lattice_sequence`](https://hex.pm/packages/lattice_sequence) | [![](https://img.shields.io/hexpm/v/lattice_sequence)](https://hex.pm/packages/lattice_sequence) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_sequence/) | Generic sequence CRDT with move support |
| [`lattice_text`](https://hex.pm/packages/lattice_text) | [![](https://img.shields.io/hexpm/v/lattice_text)](https://hex.pm/packages/lattice_text) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_text/) | Plain-text CRDT |
| [`lattice_core`](https://hex.pm/packages/lattice_core) | [![](https://img.shields.io/hexpm/v/lattice_core)](https://hex.pm/packages/lattice_core) | [![](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/lattice_core/) | VersionVector, DotContext |

### Modules

| Package | Module | Description |
|---------|--------|-------------|
| lattice_counters | `g_counter` | GCounter — grow-only counter |
| | `pn_counter` | PNCounter — positive-negative counter |
| lattice_sets | `g_set` | GSet — grow-only set |
| | `two_p_set` | TwoPSet — two-phase set with add/remove-once |
| | `or_set` | ORSet — observed-remove set |
| lattice_registers | `lww_register` | LWWRegister — last-writer-wins register |
| | `mv_register` | MVRegister — multi-value register |
| lattice_maps | `lww_map` | LWWMap — last-writer-wins map |
| | `or_map` | ORMap — observed-remove map |
| | `crdt` | Crdt(a) — typed leaves and recursive map values |
| lattice_sequence | `sequence` | Sequence — generic ordered-list CRDT with insert, delete, and move |
| lattice_text | `text` | Text — plain-text CRDT backed by Sequence |
| lattice_core | `version_vector` | VersionVector — logical clocks for causality tracking |
| | `dot_context` | DotContext — causal context for OR-types |

## Installation

Install the umbrella package to get all CRDT types:

```sh
gleam add lattice_crdt
```

Or install individual packages for minimal dependencies:

```sh
gleam add lattice_counters   # GCounter, PNCounter
gleam add lattice_sets       # GSet, TwoPSet, ORSet
gleam add lattice_registers  # LWWRegister, MVRegister
gleam add lattice_maps       # LWWMap, ORMap, Crdt dispatch
gleam add lattice_sequence   # Generic sequence CRDT
gleam add lattice_text       # Plain-text CRDT
gleam add lattice_core       # VersionVector, DotContext
```

## Quickstart

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let assert Ok(counter_a) =
    g_counter.new(replica_id.new("node-a"))
    |> g_counter.increment(1)

  let assert Ok(counter_b) =
    g_counter.new(replica_id.new("node-b"))
    |> g_counter.increment(3)

  let merged = g_counter.merge(counter_a, counter_b)

  g_counter.value(merged)
  // -> 4
}
```

`g_counter.increment` returns `Result` and rejects negative deltas with
`Error(NegativeDelta(delta))`. If you need both
increments and decrements, use `lattice_counters/pn_counter`; its `increment` and
`decrement` operations also require non-negative deltas.

## Breaking API migration

### Typed map composition

`Crdt(a)`, `CrdtSpec(a)`, `ORMap(a)`, and `LWWMap(a)` share one payload
type. Both maps can contain CRDT children, including other maps.
`SequenceSpec` creates a `Sequence(a)` and `TextSpec` creates a concrete
`Text`. Supply the initial value in `LwwRegisterSpec(initial_value)`.
Update type annotations and exhaustive matches for the new union variants.
Construct either map with `new(local_id, child_spec)`. Map `merge(left,
right)` keeps the left map's local identity; use `merge_as(left, right,
local_id)` or `bind(map, local_id)` to adopt remote state. Dispatch
`crdt.merge(left, right, local_id)` requires the explicit identity.

ORMap merges concurrent child edits within a generation. Removing and
re-adding a key creates a fresh generation. A newer generation replaces
older content, including edits concurrent with the reset; concurrent
re-adds choose a deterministic winner. A concurrent edit still keeps a key
when only removal, without a reset, races with it.

LWWMap replaces each child snapshot atomically. A Text child in LWWMap
does not preserve both concurrent assignments. Use ORMap for collaborative
child edits and sparse Sequence/Text updates.

Map snapshots and deltas use new protocol versions. Import an agreed
legacy baseline before switching writers; do not mix legacy deltas with
generation-aware replication. Existing leaf formats remain available
through their String codec entry points. Keep local editing identity
separate from the author stored in a received snapshot.

Use `or_map.update_delta` with `CrdtDelta(a)` for sparse child edits.
`update_with_delta` remains the full-value convenience path. LWWMap
`set`, `remove`, and `update` now return `Result`; use `update` and its
editing context for Sequence/Text replacements.

### Fallible edits and explicit identity

Counter, sequence, and text operations that previously panicked now return
`Result` under their plain names. Replace calls such as `try_increment` and
`try_insert_with_delta` with `increment` and `insert_with_delta`; handle or
propagate the result. Text `append` and `append_with_delta` also return `Result`.
Clamping `substring` and strict `try_substring` keep their existing behavior.

Both sequence backends and text wrappers require an explicit output identity:
`merge(local, remote, local_id)`. The argument order no longer selects the
identity for later edits. `merge_as` remains an equivalent alias.

`or_map.update` now returns `Result` and reports `TypeMismatch` instead of
keeping a fallback value. LWW-register construction and updates use the
`value:` label instead of `val:`. Import presence JSON functions from
`lattice_presence/presence_state` instead of `lattice_presence/state_json`;
the presence wire format is unchanged.

## Migrating from v1

### Import path changes

All import paths have changed from `lattice/` to package-specific paths:

```gleam
// Before (v1)
import lattice/g_counter
import lattice/or_set

// After (v2)
import lattice_counters/g_counter
import lattice_sets/or_set
```

### API changes

- **CRDT state types are opaque.** Use public query functions (`value`, `get`, `keys`, etc.) instead of state constructors. Dispatch and specification unions remain public for pattern matching.
- **Replica IDs are opaque.** Functions that identify a replica now take `replica_id.ReplicaId`; create one with `replica_id.new("node-a")`.
- **`lww_register.new`** now takes a third argument `replica_id: ReplicaId` for commutative merge on equal timestamps.
- **Two-phase set imports** use `lattice_sets/two_p_set`.
- **ORMap composition** uses `lattice_maps/crdt.CrdtSpec` variants such as `crdt.GCounterSpec` rather than a callback record.
- **JSON format:** v2 adds `replica_id` to LWWRegister JSON. `from_json` accepts both v1 and v2 formats.

See the [full import mapping](#packages) above.

## Features

- Property-based tested merge semantics (commutativity, associativity, idempotency)
- Erlang and JavaScript target support
- Delta-state mutators for efficient incremental replication
- JSON serialization with typed payload codecs and explicit legacy map migration
- Opaque CRDT state with public dispatch and specification unions
- Independent versioning — update only the packages you need
- Comprehensive documentation with examples

## Documentation

Full API documentation is available at <https://hexdocs.pm/lattice_crdt>.

## License

MIT — see [LICENSE](LICENSE) for details.
