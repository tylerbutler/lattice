---
title: Quick Start
description: Get up and running with lattice in minutes.
---

Install the umbrella package:

```sh
gleam add lattice_crdt
```

This gives you the core CRDT packages. See [Installation](/installation/) for
individual package options, including distributed presence.

## Merge counters from multiple replicas

`GCounter` is the simplest place to start: each replica can only increase its
own contribution, and merging takes the per-replica maximum.

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let counter_a =
    g_counter.new(replica_id.new("node-a"))
    |> g_counter.increment(2)

  let counter_b =
    g_counter.new(replica_id.new("node-b"))
    |> g_counter.increment(3)

  let merged = g_counter.merge(counter_a, counter_b)

  g_counter.value(merged)
  // -> 5
}
```

`g_counter.increment` rejects negative deltas. If you need a counter that can
go down, use `pn_counter` from `lattice_counters`; both `increment` and
`decrement` still take non-negative deltas because the underlying state is
grow-only.

For incremental replication, counters also expose `*_with_delta` mutators that
return both the new state and a compact delta. See
[Delta-State Replication](/advanced/delta-state/).

## Resolve ties deterministically with LWW registers

`LWWRegister` stores a value plus a timestamp. Newer timestamps win. If two
replicas write at the same timestamp, lattice breaks the tie deterministically
using the replica ID.

```gleam
import lattice_core/replica_id
import lattice_registers/lww_register

pub fn main() {
  let left = lww_register.new("apple", 7, replica_id.new("node-a"))
  let right = lww_register.new("zebra", 7, replica_id.new("node-b"))

  let merged = lww_register.merge(left, right)

  lww_register.value(merged)
  // -> "zebra"  (node-b > node-a lexicographically)
}
```

`lww_register.set` only applies when the new timestamp is strictly greater than
the current one.

## Store CRDT values inside an OR-Map

`ORMap` tracks keys with add-wins semantics and stores a CRDT value at each
key. The `CrdtSpec` you choose when creating the map determines the default
value used when `or_map.update` sees a missing key.

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/or_map

fn add_points(value: crdt.Crdt, delta: Int) -> crdt.Crdt {
  case value {
    crdt.CrdtGCounter(counter) ->
      crdt.CrdtGCounter(g_counter.increment(counter, delta))

    other -> other
  }
}

pub fn main() {
  let scoreboard_a =
    or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
    |> or_map.update("alice", fn(value) { add_points(value, 2) })

  let scoreboard_b =
    or_map.new(replica_id.new("node-b"), crdt.GCounterSpec)
    |> or_map.update("alice", fn(value) { add_points(value, 3) })

  let assert Ok(merged) = or_map.merge(scoreboard_a, scoreboard_b)

  case or_map.get(merged, "alice") {
    Ok(crdt.CrdtGCounter(counter)) -> g_counter.value(counter)
    _ -> 0
  }
  // -> 5
}
```

For more detail, see the [Counters guide](/guides/counters/),
[Registers guide](/guides/registers/), [Sets guide](/guides/sets/),
and [Maps guide](/guides/maps/). For topic/key presence tracking, see the
[Presence guide](/guides/presence/).
