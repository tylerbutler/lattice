---
title: Presence
description: Tracking distributed presence with add-wins CRDT semantics.
---

Presence is provided by the `lattice_presence` package. It tracks which pids are
present for a topic and key, together with arbitrary JSON metadata.

Use it when multiple nodes need to maintain a shared view of online users,
socket processes, sessions, or similar ephemeral membership without routing all
joins and leaves through one coordinator.

## Basic joins and reads

```gleam
import gleam/json
import lattice_presence/presence_state as presence

pub fn main() {
  let assert Ok(replica) =
    presence.new_replica("node-a", "process-incarnation-123")
  let assert Ok(state) =
    presence.join(
      presence.new(replica),
      "pid-1",
      "room:lobby",
      "alice",
      json.object([]),
    )

  presence.get_by_topic(state, "room:lobby")
  // -> [#("pid-1", "alice", _)]
}
```

Each `join` creates a causal tag owned by the local replica incarnation. The
caller must generate a fresh unique incarnation token on every process restart;
the stable base alone is not a safe identity. Queries hide entries from replicas
you have marked down locally.

## Merging replicas

`merge` rejects divergent histories claiming the same full incarnation:

```gleam
let assert Ok(merged) = presence.merge(node_a, node_b)
```

Use `merge_with_diff` when an application needs Phoenix-style join and leave
notifications while applying remote state:

```gleam
let assert Ok(#(merged, diff)) = presence.merge_with_diff(node_a, node_b)
```

The diff groups joins and leaves by topic. It is for notifying subscribers; the
merged state is still the source of truth.

## Replica visibility

Replica liveness is local view state, not replicated CRDT state. If a node sees a
peer go down, it marks that peer down in its own state:

```gleam
let #(state, diff) = presence.replica_down(state, node_b_replica)
```

Entries owned by a down replica become invisible to query functions and appear
as leaves in the returned diff. If the replica comes back:

```gleam
let assert Ok(#(state, diff)) = presence.replica_up(state, node_b_replica)
```

Those entries become visible again and appear as joins. This keeps cluster
liveness decisions in the embedding application instead of trying to replicate
up/down status as CRDT data.

## Leaving and cleanup

`leave` removes one local pid/topic/key entry:

```gleam
let state = presence.leave(state, "pid-1", "room:lobby", "alice")
```

`leave_by_pid` removes all local entries for a pid. Both operations only remove
entries owned by the local replica; foreign entries must be removed by their
owning replica or hidden with replica liveness.

After a replica is permanently gone, `remove_down_replica` can prune its entries
after it has been marked down:

```gleam
let assert Ok(#(state, diff)) =
  presence.remove_down_replica(state, node_b_replica)
```

The identity is added to a replicated, grow-only retired-incarnation set, so a
stale peer cannot replay removed entries or unseen higher clocks. Retired
identities cannot join or be marked up. To start a replacement incarnation and
prune all known older incarnations sharing its base:

```gleam
let assert Ok(new_replica) = presence.new_replica("node-b", fresh_token)
let assert Ok(#(state, diff)) = presence.supersede(state, new_replica)
```

`supersede` always preserves the state's local identity while recording the
replacement and retiring older identities. A restarted process should create a
fresh state with the new incarnation before merging peer state.

## Serialization

Serialization is part of `presence_state`:

```gleam
let payload = presence.to_json_string(state)
let decoded = presence.from_json(payload)
```

Replica identities are structured `{base, incarnation}` objects. Replica-keyed
contexts and clouds are arrays of records, and `retired` carries the grow-only
incarnation tombstones. This wire format is intentionally incompatible with
version 1. Local visibility is not serialized. Decoding validates identities,
causal coverage and canonical clocks, and limits nested metadata depth.
