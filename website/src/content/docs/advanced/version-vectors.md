---
title: Version Vectors
description: Understanding version vectors and causal context for OR-types.
---

Version vectors are the causal backbone of lattice's observed-remove CRDTs.
They are provided by the `lattice_core` package.

## What is a version vector?

A version vector is a map from replica IDs to logical clock values. It tracks
which events each replica has seen, enabling detection of causal ordering
between states.

## Creating and incrementing

```gleam
import lattice_core/replica_id
import lattice_core/version_vector

pub fn main() {
  let node_a = replica_id.new("node-a")
  let node_b = replica_id.new("node-b")

  let vv =
    version_vector.new()
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_b)

  version_vector.get(vv, node_a)  // -> 2
  version_vector.get(vv, node_b)  // -> 1
}
```

## Comparing version vectors

`version_vector.compare` returns one of four `Order` variants:

- `Equal` — both vectors have the same clock values
- `Before` — `a` happened before `b` (every clock in `a` is less than or equal
  to the corresponding clock in `b`, and at least one is strictly less)
- `After` — `a` happened after `b`
- `Concurrent` — neither vector dominates the other

```gleam
import lattice_core/replica_id
import lattice_core/version_vector

pub fn main() {
  let node_a = replica_id.new("node-a")
  let node_b = replica_id.new("node-b")

  let vv_a =
    version_vector.new()
    |> version_vector.increment(node_a)
    |> version_vector.increment(node_a)

  let vv_b =
    version_vector.new()
    |> version_vector.increment(node_b)

  version_vector.compare(vv_a, vv_b)
  // -> Concurrent  (vv_a has higher node-a, vv_b has higher node-b)
}
```

## Merging

Merge takes the pairwise maximum of every clock value:

```gleam
let merged = version_vector.merge(vv_a, vv_b)

version_vector.get(merged, node_a)  // -> 2
version_vector.get(merged, node_b)  // -> 1
```

## Dominates

`version_vector.dominates(a, b)` returns `True` when `a` has seen everything
`b` has seen — every clock in `a` is greater than or equal to the corresponding
clock in `b`.

## Where version vectors are used

You rarely need to work with version vectors directly. They are used internally
by:

- `MVRegister` — to track causal history of writes and detect concurrent
  updates
- `ORSet` — via pruned version vectors for tombstone garbage collection
- `ORMap` — inherits pruning from the underlying `ORSet` key tracker

## DotContext

A `DotContext` tracks individual observed events — "dots" consisting of a
replica ID and a counter value. It is used internally by causal CRDTs to
determine which add operations have been observed by a given replica.

You typically do not interact with `DotContext` directly unless you are building
custom CRDTs on top of lattice's causal infrastructure.
