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

Choose IDs that are unique across your system and across process incarnations.
A stable hostname or node name alone is unsafe after a restart because peers may
retain causal history for its previous run. Generate a fresh ID for every
process incarnation and keep the stable name separately when other CRDTs need
restart-safe identities.

`lattice_presence` provides this pattern directly:

```gleam
import lattice_presence/presence_state

let presence = presence_state.new_incarnation("node-a")
```

`new_incarnation` preserves `node-a` as the stable base while generating a
unique identity for the current process. Use `base_replica` when you need the
stable name, and use `same_base` to compare incarnation identities by that name.
