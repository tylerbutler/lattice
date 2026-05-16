---
title: Delta-State Replication
description: Sending compact CRDT deltas instead of full state.
---

State-based CRDTs are simple to reason about: every replica can merge another
replica's state and converge. Delta-state replication keeps that merge model,
but sends only the change produced by a local mutation.

Use delta-state APIs when replicas sync frequently over transports such as
websockets, gossip, or reconnect catch-up, where sending the full CRDT after
every small update would waste bandwidth.

## Leaf CRDT convention

For each state-changing operation, lattice keeps the existing mutator and adds a
`*_with_delta` companion:

```gleam
let #(local, delta) = g_counter.increment_with_delta(local, 5)
let remote = g_counter.merge(remote, delta)
```

The first tuple item is the new local state. The second item is itself a CRDT of
the same type containing the change. Remote replicas merge that delta with the
same `merge` function used for full-state replication.

Existing mutators such as `increment`, `add`, `remove`, and `set` keep their
signatures. They delegate to the delta-aware version and discard the delta.

## Example: counter deltas

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let local = g_counter.new(replica_id.new("node-a"))
  let remote = g_counter.new(replica_id.new("node-b"))

  let #(local, delta) = g_counter.increment_with_delta(local, 5)
  let remote = g_counter.merge(remote, delta)

  g_counter.value(remote)
  // -> 5
}
```

The delta carries only the changed replica entry, not every replica count in the
counter.

## ORMap deltas

`ORMap` is a composite CRDT: it tracks keys with an OR-Set and stores nested CRDT
values. It therefore uses a dedicated opaque `ORMapDelta` type instead of
representing deltas as a full `ORMap`.

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/or_map

fn add_points(value: crdt.Crdt) -> crdt.Crdt {
  case value {
    crdt.CrdtGCounter(counter) ->
      crdt.CrdtGCounter(g_counter.increment(counter, 5))

    other -> other
  }
}

pub fn main() {
  let local = or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
  let remote = or_map.new(replica_id.new("node-b"), crdt.GCounterSpec)

  let assert Ok(#(local, delta)) =
    or_map.update_with_delta(local, "alice", add_points)

  let assert Ok(remote) = or_map.apply_delta(remote, delta)

  or_map.keys(remote)
  // -> ["alice"]
}
```

`ORMapDelta` includes the key-set delta, changed value payloads, and causal
remove bounds. This lets `apply_delta` preserve add-wins remove semantics while
touching only the changed keys.

## Batching deltas

Transport layers can combine pending ORMap deltas before sending them:

```gleam
let assert Ok(combined) = or_map.merge_deltas(delta_a, delta_b)
let assert Ok(remote) = or_map.apply_delta(remote, combined)
```

This is useful for per-peer outboxes: store unacknowledged deltas, join them with
`merge_deltas`, send one payload, and garbage-collect deltas after the peer
acknowledges receipt.

## Serialization

Leaf CRDT deltas use their existing `to_json` and `from_json` functions because
they are values of the same type as their state. `ORMapDelta` has separate
helpers:

```gleam
let encoded = or_map.delta_to_json(delta)
let decoded = or_map.delta_from_json(json_string)
```

Use those helpers when sending ORMap deltas across a process, node, or browser
boundary.

## Transport responsibilities

lattice provides CRDT values and merge semantics. A websocket or gossip layer is
still responsible for peer identity, buffering, acknowledgements, reconnect
policy, and deciding when to fall back to full-state sync.

Because delta merge is idempotent, commutative, and associative, transports can
use at-least-once delivery and tolerate duplicate or out-of-order delta messages.
