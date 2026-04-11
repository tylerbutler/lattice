---
title: Counters
description: Using GCounter and PNCounter for distributed counting.
---

Counters are provided by the `lattice_counters` package. If you installed the
`lattice_crdt` umbrella, they are already available.

Use counters when replicas need to accumulate numeric state and later merge
without coordination.

## GCounter

`GCounter` is grow-only. Each replica can increase its own contribution, and
merge takes the per-replica maximum before summing the result.

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let left =
    g_counter.new(replica_id.new("node-a"))
    |> g_counter.increment(2)

  let right =
    g_counter.new(replica_id.new("node-b"))
    |> g_counter.increment(5)

  let merged = g_counter.merge(left, right)

  g_counter.value(merged)
  // -> 7
}
```

`g_counter.increment` only accepts non-negative deltas. Passing a negative
value is invalid because it would break the grow-only invariant.

## PNCounter

`PNCounter` supports both increments and decrements by pairing two internal
`GCounter`s.

```gleam
import lattice_core/replica_id
import lattice_counters/pn_counter

pub fn main() {
  let counter =
    pn_counter.new(replica_id.new("node-a"))
    |> pn_counter.increment(10)
    |> pn_counter.decrement(3)

  pn_counter.value(counter)
  // -> 7
}
```

Both `pn_counter.increment` and `pn_counter.decrement` require non-negative
deltas. To subtract 3, call `pn_counter.decrement(counter, 3)` rather than
passing `-3`.
