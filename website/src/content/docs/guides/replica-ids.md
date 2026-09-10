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

## Unicode ordering and upgrades

`replica_id.compare` uses lexicographic UTF-8 byte order on both Erlang and
JavaScript. For example, `"\u{e000}"` sorts before `"\u{10000}"`. IDs retain
their original strings; the library does not normalize Unicode.
Pass well-formed Unicode strings at JavaScript interop boundaries.

LWWRegister uses this order to break equal-timestamp ties. Sequence and Fugue
use it to order concurrent items and operations, which also affects text and
anchor positions.

Older JavaScript versions used UTF-16 order, which reverses some Unicode pairs
such as the example above. The correction preserves Erlang's previous order
and ASCII ordering. Upgrade peers that exchange affected Unicode IDs together
so they use the same conflict-resolution rules.

An upgrade cannot restore a register winner that no replica retained.
Sequence snapshots can retain their previous item order, and compaction can
remove the origins needed to reconstruct it. The comparator correction does
not migrate historical snapshots. Fugue computes traversal from its nodes, so
existing Unicode-ID siblings can appear in a different order after the upgrade.
Plan any historical-state migration separately.

`lattice_presence` provides this pattern directly:

```gleam
import lattice_presence/presence_state

let presence = presence_state.new_incarnation("node-a")
```

`new_incarnation` preserves `node-a` as the stable base while generating a
unique identity for the current process. Use `base_replica` when you need the
stable name, and use `same_base` to compare incarnation identities by that name.
