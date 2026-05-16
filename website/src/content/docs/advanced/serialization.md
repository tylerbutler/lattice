---
title: JSON Serialization
description: Serializing and deserializing CRDTs with JSON.
---

Every CRDT module across all lattice packages exposes `to_json` and `from_json`.

The encoded JSON includes a `"type"` discriminator and a schema version so the
decoder can dispatch to the right implementation.

## Basic example

```gleam
import gleam/json
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let counter =
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

fn add_points(value: crdt.Crdt) -> crdt.Crdt {
  case value {
    crdt.CrdtGCounter(counter) ->
      crdt.CrdtGCounter(g_counter.increment(counter, 1))

    other -> other
  }
}

pub fn main() {
  let map =
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

Internally, `ORMap` encodes its key-set tracker and nested CRDT values as JSON
strings inside the outer envelope so they can reuse the existing per-type
decoders.

## ORMap delta serialization

`ORMapDelta` has dedicated JSON helpers because it is not itself an `ORMap`:

```gleam
import gleam/json
import lattice_maps/or_map

let encoded =
  delta
  |> or_map.delta_to_json
  |> json.to_string

let decoded = or_map.delta_from_json(encoded)
```

Use these helpers for map-level delta messages. Leaf CRDT deltas use the normal
`to_json` and `from_json` functions for their type because leaf deltas are values
of the same type as the full state.

## Presence serialization

`lattice_presence/state_json` serializes distributed presence state for
cross-node replication:

```gleam
import lattice_presence/state_json

let payload = state_json.to_json_string(state)
let decoded = state_json.from_json(payload)
```

Presence JSON contains only replicated CRDT data: replica name, causal context,
clouds, and presence entries. Local replica visibility state from
`replica_up`/`replica_down` is intentionally not encoded. Decoding validates
clock values and limits nested metadata depth before returning `Ok(state)`.
