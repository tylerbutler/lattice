---
title: Replica IDs
description: Identifying nodes in a distributed system.
---

A `ReplicaId` identifies which node performed an operation. It is an opaque
wrapper around a string, provided by `lattice_core`.

```gleam
import lattice_core/replica_id

let node = replica_id.new("node-a")
```

Most CRDTs in lattice require a `ReplicaId` at construction time:

- `GCounter`, `PNCounter` — to track per-replica contributions
- `LWWRegister` — for deterministic tie-breaking when timestamps are equal
- `MVRegister`, `ORSet`, `ORMap` — for causal tagging

A few types do not require one because they have no per-replica state:
`GSet`, `TwoPSet`, and `LWWMap`.

Choose IDs that are unique across your system. In practice, hostnames, UUIDs,
or node names all work — the only requirement is that no two active replicas
share the same ID.
