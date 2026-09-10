---
title: JSON Serialization
description: Serializing and deserializing CRDTs with JSON.
---

Every CRDT module across all lattice packages exposes `to_json` and `from_json`.

Most encoded CRDTs include a `"type"` discriminator and schema version.
Presence retains its unversioned replication format, described below.

## Basic example

```gleam
import gleam/json
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let assert Ok(counter) =
    g_counter.new(replica_id.new("node-a"))
    |> g_counter.increment(3)

  let encoded =
    counter
    |> g_counter.to_json
    |> json.to_string

  case g_counter.from_json(encoded) {
    Ok(decoded) -> g_counter.value(decoded)
    Error(_) -> 0
  }
  // -> 3
}
```

## ORMap serialization

`ORMap` also supports JSON round-tripping:

```gleam
import gleam/json
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/or_map

fn add_points(value: crdt.Crdt(String)) -> crdt.Crdt(String) {
  case value {
    crdt.CrdtGCounter(counter) -> {
      let assert Ok(counter) = g_counter.increment(counter, 1)
      crdt.CrdtGCounter(counter)
    }

    other -> other
  }
}

pub fn main() {
  let assert Ok(map) =
    or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
    |> or_map.update("alice", add_points)

  let encoded =
    map
    |> or_map.to_json
    |> json.to_string

  case or_map.from_json(encoded) {
    Ok(decoded) -> or_map.keys(decoded)
    Error(_) -> []
  }
  // -> ["alice"]
}
```

Modern map snapshots include recursive child schemas and the metadata
needed to preserve generations or LWW assignment order. Typed leaves
retain their causal state rather than encoding only visible values.

Use caller-supplied payload encoders and decoders for `Crdt(a)` values
such as integers or records. Existing String leaf codec entry points
retain their formats. A register's configured initial value belongs to
the schema so newly created keys after load use the same default.

Dispatch distinguishes Text from `Sequence(String)` with a Text wrapper.
The standalone Text codec still uses its canonical Sequence envelope;
a bare Sequence envelope decodes as Sequence.

## ORMap delta serialization

`ORMapDelta(a)` has dedicated JSON helpers because it is not a full map:

```gleam
import gleam/json
import lattice_maps/or_map

let encoded =
  delta
  |> or_map.delta_to_json
  |> json.to_string

let decoded = or_map.delta_from_json(encoded)
```

Use the delta helpers for map-level messages. Nested `OrMapChange`
payloads remain deltas rather than full child snapshots. Preserve
generation floors even for removed keys, plus leaf counters, item IDs,
move/delete records, frontiers, and forwarding metadata.

## Legacy map import

Modern map formats require a coordinated migration. Import an agreed
legacy baseline, distribute the modern snapshot, then switch writers.
Do not mix legacy map deltas with generation-aware replication.
ORMap snapshots use version 3 and deltas use version 2; LWWMap snapshots
use version 3.

Legacy ORMap entries enter the initial generation. Supply an explicit
payload schema/default when the old String spec cannot determine it.
An importer cannot recover history that an old writer already pruned;
use a fresh writer identity where allocation history is unavailable.

Legacy String LWWMap imports wrap scalar values as register children and
retain the original String tie keys. Modern entries use writer identity.
At equal timestamp and tombstone status, modern entries outrank legacy
entries; legacy-versus-legacy comparisons keep the old rule.

The import APIs require an explicit schema and receiving identity:

```gleam
import gleam/dynamic/decode
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map

pub fn import_string_register_map(legacy_snapshot: String) {
  or_map.import_legacy(
    legacy_snapshot,
    crdt.LwwRegisterSpec(""),
    decode.string,
    replica_id.new("new-writer"),
  )
}
```

For a scalar String LWWMap baseline, call
`lww_map.import_legacy(snapshot, crdt.LwwRegisterSpec(""), local_id)`.
Its modern children are LWWRegisters rather than raw strings.

LWWMap snapshots must contain one entry at most for each exact key.
Modern decoding and legacy v1/v2 import reject repeated live entries,
tombstones, and live/tombstone pairs rather than selecting an array-order
winner. Producers of previously accepted duplicate entries must resolve
each key before encoding or before calling `import_legacy`. Key identity
is exact and is not Unicode-normalized.

Decoding rejects unsupported versions, incompatible schemas, unsafe
allocation metadata, and conflicting immutable write identities. Use
the receiving editor's identity when adopting decoded state for edits.

## Presence serialization

`lattice_presence/presence_state` serializes distributed presence state for
cross-node replication:

```gleam
import lattice_presence/presence_state

let payload = presence_state.to_json_string(state)
let decoded = presence_state.from_json(payload)
```

Presence JSON contains only replicated CRDT data: replica name, causal context,
clouds, and presence entries. Local replica visibility state from
`replica_up`/`replica_down` is intentionally not encoded. Decoding validates
clock values and limits nested metadata depth before returning `Ok(state)`.

Use `presence_state.decoder()` to embed presence state in a larger JSON
decoder. The former `state_json` module and public replicated-parts constructor
are removed; the wire representation is unchanged.

## Sequence snapshots and local identity

Sequence and text decoding restores the serialized replica identity. Before
editing a snapshot received from another replica, merge it with your local
state using `merge(local, decoded, local_id)`. Do not edit remote state under
the sender's identity.

YATA sequence and text state use schema v2. V1 states without moves decode
directly; v1 states with moves and no compacted blocks reconstruct base order.
V1 states with both moves and compacted blocks are rejected and require a
resync. Fugue retains schema v1.
