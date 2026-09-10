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
- `LWWMap` — to identify immutable child assignments
- Sequence and text CRDTs — for item identities and local editing clocks

A few types do not require one because they have no per-replica state:
`GSet` and `TwoPSet`.

Choose IDs that are unique across your system and across process incarnations.
A stable hostname or node name alone is unsafe after a restart because peers may
retain causal history for its previous run. Generate a fresh ID for every
process incarnation and keep the stable name separately when other CRDTs need
restart-safe identities.

## Sequence and text merges

Both sequence backends and their text wrappers require an explicit output
identity: `merge(local, remote, local_id)`. Swapping the states does not change
which identity later edits use. `merge_as` remains an equivalent alias.

Keep the local ID in your editor or connection context. When combining deltas
from one editing operation, use that operation's ID. When receiving remote
state or deltas, use the receiving editor's ID. A decoded snapshot still carries
the sender's identity until you bind or merge it under a local identity.
`sequence.bind(state, local_id)` and `text.bind(state, local_id)` change
only editor metadata; they do not rebuild the document or rewrite its
historical IDs.

The sequence backends expose `replica_id(state)` for reading a state's editing
identity. This does not establish ownership of a remote state; your application
must still assign a unique ID to each independent writer.

## Recursive maps

Bind a received map to the local writer before editing its children. This
includes keys that existed only on the sender and maps nested inside other
maps. Preserve historical item IDs and winning write authors; rebinding
selects the identity for subsequent operations.

ORMap scopes child editing identities by the enclosing key path and
generation. Removing and re-adding a key creates a fresh generation, so
the same writer does not restart the old leaf's item namespace.
LWWMap child replacements use the new outer write identity as part of
their scope.

Do not alter an LWWRegister's stored author when adopting it. Use an
explicit-author write to create a new register value under the local
editing identity.

## Presence incarnations

`lattice_presence` provides this pattern directly:

```gleam
import lattice_presence/presence_state

let presence = presence_state.new_incarnation("node-a")
```

`new_incarnation` preserves `node-a` as the stable base while generating a
unique identity for the current process. Use `base_replica` when you need the
stable name, and use `same_base` to compare incarnation identities by that name.
