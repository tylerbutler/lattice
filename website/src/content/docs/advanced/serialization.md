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
