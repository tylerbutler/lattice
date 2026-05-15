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
  let state =
    presence.new("node-a")
    |> presence.join("pid-1", "room:lobby", "alice", json.object([]))

  presence.get_by_topic(state, "room:lobby")
  // -> [#("pid-1", "alice", _)]
}
```

Each `join` creates a causal tag owned by the local replica. Queries hide entries
from replicas you have marked down locally.

## Merging replicas

`merge` returns the merged state:

```gleam
let merged = presence.merge(node_a, node_b)
```

Use `merge_with_diff` when an application needs Phoenix-style join and leave
notifications while applying remote state:

```gleam
let #(merged, diff) = presence.merge_with_diff(node_a, node_b)
```

The diff groups joins and leaves by topic. It is for notifying subscribers; the
merged state is still the source of truth.

## Replica visibility

Replica liveness is local view state, not replicated CRDT state. If a node sees a
peer go down, it marks that peer down in its own state:

```gleam
let #(state, diff) = presence.replica_down(state, "node-b")
```

Entries owned by a down replica become invisible to query functions and appear
as leaves in the returned diff. If the replica comes back:

```gleam
let #(state, diff) = presence.replica_up(state, "node-b")
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

After a replica is permanently gone, `remove_down_replica` can discard its
entries and causal context:

```gleam
let state = presence.remove_down_replica(state, "node-b")
```

Only call this after the application has decided that the replica will not
return with useful state.

## Serialization

Use `lattice_presence/state_json` for cross-node payloads:

```gleam
import lattice_presence/state_json

let payload = state_json.to_json_string(state)
let decoded = state_json.from_json(payload)
```

The JSON format contains replicated CRDT data: replica name, causal context,
clouds, and presence entries. Local replica visibility (`replica_up` /
`replica_down`) is intentionally not serialized. Decoding validates causal clock
values and limits nested metadata depth so malformed payloads fail as
`Result(Error(_))` instead of producing invalid state.
