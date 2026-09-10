---
title: Delta-State Replication
description: Sending compact CRDT deltas instead of full state.
---

State-based CRDTs are simple to reason about: every replica can merge another
replica's state and converge. Delta-state replication keeps that merge model,
but sends only the change produced by a local mutation.

Use delta-state APIs when replicas sync frequently over transports such as
websockets, gossip, or reconnect catch-up, where sending the full CRDT after
every small update would waste bandwidth.

## Leaf CRDT convention

Each state-changing operation has a `*_with_delta` companion. Fallible
operations return `Result`:

```gleam
let assert Ok(#(local, delta)) = g_counter.increment_with_delta(local, 5)
let remote = g_counter.merge(remote, delta)
```

The first tuple item is the new local state. The second item is itself a CRDT of
the same type containing the change. Remote replicas merge that delta with the
same `merge` function used for full-state replication.

State-only operations discard the successful delta and preserve errors.
Counter, sequence, and text edits return `Result` under plain names, without
panicking variants. Infallible set operations still return their state directly.

## Example: counter deltas

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter

pub fn main() {
  let local = g_counter.new(replica_id.new("node-a"))
  let remote = g_counter.new(replica_id.new("node-b"))

  let assert Ok(#(local, delta)) = g_counter.increment_with_delta(local, 5)
  let remote = g_counter.merge(remote, delta)

  g_counter.value(remote)
  // -> 5
}
```

The delta carries only the changed replica entry, not every replica count in the
counter.

## Sequence and text identity

Both sequence backends and their text wrappers require the receiving editor's
identity when merging a state or delta:

```gleam
let assert Ok(#(local, delta)) = sequence.insert_with_delta(local, 0, value)
let remote = sequence.merge(remote, delta, remote_id)
```

`merge(delta, remote, remote_id)` has the same result. `merge_as` is an alias
with the same three arguments. Use a fixed output identity when applying merge
laws, and keep each independent writer's identity unique.

## ORMap deltas

`ORMap(a)` tracks generation-qualified membership and stores typed CRDT
children. It uses an opaque `ORMapDelta(a)` instead of representing a map
delta as a full snapshot.

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/or_map

fn add_points(value: crdt.Crdt(String)) -> crdt.Crdt(String) {
  case value {
    crdt.CrdtGCounter(counter) -> {
      let assert Ok(counter) = g_counter.increment(counter, 5)
      crdt.CrdtGCounter(counter)
    }

    other -> other
  }
}

pub fn main() {
  let local = or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
  let remote = or_map.new(replica_id.new("node-b"), crdt.GCounterSpec)

  let assert Ok(#(local, delta)) =
    or_map.update_with_delta(local, "alice", add_points)

  let assert Ok(remote) = or_map.apply_delta(remote, delta)

  or_map.keys(remote)
  // -> ["alice"]
}
```

The callback above returns the full child counter. `update_with_delta`
avoids sending unrelated keys, but does not make that child payload sparse.

For a large Sequence or Text, use the sparse callback API and return the
delta from its `*_with_delta` operation. `CrdtDelta(a)` distinguishes:

| Variant | Payload |
| --- | --- |
| `NoChange(spec)` | No leaf change for the given schema. |
| `StateDelta(child)` | A leaf delta or an explicit full child snapshot. |
| `OrMapChange(delta)` | A sparse nested ORMap delta. |

The map applies the callback's delta to produce local state and emits the
same change to peers. Returning a nested `OrMapChange` preserves sparse
updates through ORMap paths. Do not return the child operation's full
updated state when you need a sparse leaf payload.
For a newly created key, the map also transmits required initial state.
A configured register seed is not an empty merge value, even when the
callback returns `NoChange`.

Removal-only entries also carry their generation. A newer generation
supersedes older membership and values, even when the newer key is absent.
Same-generation update/remove conflicts remain add-wins.

## Batching deltas

Transport layers can combine pending ORMap deltas before sending them:

```gleam
let assert Ok(combined) = or_map.merge_deltas(delta_a, delta_b)
let assert Ok(remote) = or_map.apply_delta(remote, combined)
```

Store unacknowledged deltas in a per-peer outbox, join them with
`merge_deltas`, and send the result. Batching sparse nested ORMap changes
stays sparse. A batch containing a full snapshot can remain a snapshot.
Remove acknowledged outbox data only when the transport's recovery
contract permits it.

## Serialization

Leaf deltas use their state codecs. Typed register/set payloads use the
generic codec entry points with the application's encoder and decoder.
`ORMapDelta(a)` has separate helpers for recursive delta payloads:

```gleam
let encoded = or_map.delta_to_json(delta)
let decoded = or_map.delta_from_json(json_string)
```

Use those helpers when sending ORMap deltas across a process, node, or browser
boundary.

## Transport responsibilities

lattice provides CRDT values and merge semantics. A websocket or gossip layer is
still responsible for peer identity, buffering, acknowledgements, reconnect
policy, and deciding when to fall back to full-state sync.

Transports can tolerate duplicate and reordered messages, but must supply
a baseline or the required earlier deltas. A later Sequence edit can
reference items not yet received; an intermediate view can be incomplete.
One latest delta does not reconstruct an arbitrary empty peer.

Outer-map acknowledgments and pruning clocks do not establish a child
Sequence/Text compaction frontier. Keep those stability decisions
separate. LWWMap assignments carry complete snapshots and choose one
winner; they are outside the sparse ORMap path guarantee.
