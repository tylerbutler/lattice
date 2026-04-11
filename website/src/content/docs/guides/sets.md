---
title: Sets
description: Using GSet, TwoPSet, and ORSet for distributed collections.
---

Sets are provided by the `lattice_sets` package. If you installed the
`lattice_crdt` umbrella, they are already available.

Use sets when replicas need to track membership and later merge without
coordination.

## GSet

`GSet` is a grow-only set. Elements can be added but never removed. Merge is
a set union.

```gleam
import lattice_sets/g_set

pub fn main() {
  let set_a =
    g_set.new()
    |> g_set.add("apple")
    |> g_set.add("banana")

  let set_b =
    g_set.new()
    |> g_set.add("banana")
    |> g_set.add("cherry")

  let merged = g_set.merge(set_a, set_b)

  g_set.contains(merged, "apple")   // -> True
  g_set.contains(merged, "cherry")  // -> True
}
```

`GSet` requires no `ReplicaId` because it does not track causal history.

## TwoPSet

`TwoPSet` supports both add and remove, but removal is permanent. Once an
element is removed, it can never be re-added — the tombstone is irrevocable.

```gleam
import lattice_sets/two_p_set

pub fn main() {
  let set =
    two_p_set.new()
    |> two_p_set.add("apple")
    |> two_p_set.add("banana")
    |> two_p_set.remove("banana")

  two_p_set.contains(set, "apple")   // -> True
  two_p_set.contains(set, "banana")  // -> False (tombstoned)

  // Re-adding has no effect
  let re_added = two_p_set.add(set, "banana")
  two_p_set.contains(re_added, "banana")  // -> False
}
```

Like `GSet`, `TwoPSet` requires no `ReplicaId`.

## ORSet

`ORSet` is the most flexible set CRDT. It supports add, remove, and re-add.
Each add operation creates a unique causal tag, and remove only deletes tags
that the removing replica has observed. This gives **add-wins** semantics: a
concurrent add on another replica survives a remove.

`ORSet` requires a `ReplicaId` from `lattice_core` to track causal history.

```gleam
import lattice_core/replica_id
import lattice_sets/or_set

pub fn main() {
  let node_a =
    or_set.new(replica_id.new("node-a"))
    |> or_set.add("apple")

  let node_b =
    or_set.new(replica_id.new("node-b"))
    |> or_set.add("apple")
    |> or_set.remove("apple")

  let merged = or_set.merge(node_a, node_b)

  or_set.contains(merged, "apple")
  // -> True  (node-a's add was concurrent with node-b's remove)
}
```

Unlike `TwoPSet`, elements can be re-added after removal:

```gleam
import lattice_core/replica_id
import lattice_sets/or_set

pub fn main() {
  let set =
    or_set.new(replica_id.new("demo"))
    |> or_set.add("x")
    |> or_set.remove("x")
    |> or_set.add("x")

  or_set.contains(set, "x")
  // -> True
}
```

## Choosing the right set

- **`GSet`** — when you never need to remove elements. Simplest, no causal
  tracking overhead.
- **`TwoPSet`** — when you need one-time removal. Still no causal tracking, but
  removed elements can never come back.
- **`ORSet`** — when you need full add/remove/re-add flexibility. Requires a
  replica ID and maintains causal metadata.
