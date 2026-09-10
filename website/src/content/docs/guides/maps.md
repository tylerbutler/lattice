---
title: Maps
description: Typed recursive maps with observed-remove or last-writer-wins semantics.
---

The `lattice_maps` package provides `ORMap(a)` and `LWWMap(a)`. Both store
String keys and `Crdt(a)` children, including nested maps. The
`lattice_crdt` umbrella includes them.

Choose the container by its merge behavior:

| Container | Concurrent child changes |
| --- | --- |
| ORMap | Join child CRDTs within the same generation. |
| LWWMap | Select one complete child assignment. |

## Typed child specifications

Each map has one `CrdtSpec(a)` that defines its children and their initial
state. Parameterized registers, sets, and sequences share payload type `a`.
Text has a concrete String/grapheme payload. For mixed application data,
use a tagged union as `a` and supply its JSON encoder and decoder.

```gleam
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map

let local = replica_id.new("node-a")
let documents: or_map.ORMap(String) =
  or_map.new(local, crdt.TextSpec)
let lists: or_map.ORMap(Int) =
  or_map.new(local, crdt.SequenceSpec)
let boards: or_map.ORMap(String) =
  or_map.new(local, crdt.OrMapSpec(crdt.LwwRegisterSpec("")))
```

`LwwRegisterSpec(initial_value)` supplies an actual initial payload.
Nested `OrMapSpec(child_spec)` and `LwwMapSpec(child_spec)` create empty
maps with the chosen schema. A changed register value need not equal its
configured initial value.

Map updates and merges return errors for incompatible child kinds or
recursive schemas. A rejected update does not activate a missing or
removed key.

## ORMap updates

The full-value `update` and `update_with_delta` callbacks receive the
current child. A first update creates the configured default. Within a
generation, the map joins the returned child through the same apply path
used for replication.

Use the sparse callback API for large Sequence/Text values. Perform the
leaf's `*_with_delta` operation and return `StateDelta` containing its
delta. For a nested ORMap, return `OrMapChange` containing the child map's
delta. The map computes local state from that change, so local updates
and remote application use the same payload.

A leaf no-op can still refresh key membership. Callback failures and
schema errors do not emit a successful map delta.

### Sparse Text example

```gleam
import gleam/result
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map
import lattice_text/text

pub fn main() {
  let documents: or_map.ORMap(String) =
    or_map.new(replica_id.new("node-a"), crdt.TextSpec)

  or_map.update_delta(documents, "notes", fn(value, _context) {
    let assert crdt.CrdtText(document) = value
    text.insert_with_delta(document, 0, "hello")
    |> result.map(fn(pair) {
      let #(_updated, delta) = pair
      crdt.StateDelta(crdt.CrdtText(delta))
    })
  })
}
```

The result contains the updated map and its transport delta. For ordered
lists, select `SequenceSpec` and wrap the Sequence operation's delta in
`CrdtSequence`. The runnable
[Sequence/Text example](https://github.com/tylerbutler/lattice/blob/main/examples/src/or_map_sequence_text_example.gleam)
also covers typed snapshot adoption and moves.

### Removal and re-addition

Within one generation, removal retracts observed membership tags. An
unobserved concurrent update survives under add-wins semantics.

Re-adding a removed key starts a fresh empty/default generation. A newer
generation replaces the old generation's membership and child state.
This also replaces old-generation edits concurrent with the reset.
Concurrent re-adds choose one winner by generation clock, then replica
ID in lexicographic UTF-8 byte order on both runtimes.

The map retains a generation floor even after removal. A delayed older
snapshot cannot reactivate an older value when the newer generation is
absent. It must not supply fallback content for a newer generation.

### Identity and pruning

Map operations bind child editing identities to the local writer,
enclosing path, and generation. They preserve historical item IDs and
write authors. Adopt received snapshots under your local identity before
editing, including keys that existed only on the sender.
Use `or_map.bind(map, local_id)` or
`or_map.merge_as(local, received, local_id)`. The two-argument `merge`
retains the left map's identity.

The current generation's inactive leaf history remains until a newer
generation supersedes it. Pruning can discard superseded payloads but
must retain generation and allocation floors. Outer key clocks do not
authorize Sequence/Text compaction or forwarding expiry.

## LWWMap assignments

LWWMap has the same recursive child schema model, but each assignment
stores one complete child snapshot. A map can contain Text, Sequence, or
another map without changing this atomic replacement rule.

Sets and removals must not precede the key's timestamp and must be strictly
above the pruning threshold. Local writes and merge use the same order:

1. Greater timestamp.
2. Tombstone over active value at equal timestamps.
3. Greater writer identity in lexicographic UTF-8 byte order for modern writes.

Generic child payloads are never compared to break a tie. Different active
payloads claiming the same modern timestamp and writer are invalid and return
`ConflictingWrite`; an active/tombstone conflict at that stamp selects the
tombstone. A timestamp at or below the prune floor remains rejected, including
for a key whose tombstone was pruned.

Use increasing timestamps to express successive writes. Equal timestamps
represent competing assignments: a local set can lose to the stored writer,
and an equal-time remove wins. Before writing received state, use `bind` or
`merge_as` to set the intended local writer identity. Child snapshots remain
immutable under their outer write identity; preparing a new child edit uses a
fresh assignment editing scope.

Two concurrent edits to a Text assigned through LWWMap do not both
survive. Use an ORMap-only path to that Text when collaborative child
merge and sparse leaf updates are required.

## Delta delivery

`ORMapDelta(a)` carries touched keys, generations, membership changes, and
child deltas. `CrdtDelta(a)` separates leaf/full-state payloads from nested
ORMap changes. Batching sparse ORMap changes preserves their sparse form;
an explicit full snapshot can produce a full-state batch.

Receivers need a baseline or eventual delivery of the required history.
A later Sequence edit alone cannot reconstruct prior items. Duplicate
and reordered delivery converges after required origins arrive, but an
intermediate view can be incomplete.

LWWMap uses full-state payloads. Its atomic boundary is outside the sparse
ORMap leaf-size guarantee.

## Migrating legacy maps

The modern map formats include recursive schemas and generation or
write metadata. Import an agreed legacy baseline and distribute the
modern snapshot before switching writers. Do not send legacy map deltas
into modern generation-aware replication.

Legacy ORMap entries start in the initial generation. Supply an explicit
schema/default where an old String spec cannot determine the new payload
type. Previously pruned allocation history cannot be recovered; use a
fresh writer identity if that history is unavailable.

Legacy LWWMap String imports wrap values as register children and retain
the old String tie keys. Legacy entries compare these keys in lexicographic
UTF-8 byte order; modern writes use writer identity and outrank legacy
entries at equal timestamp and tombstone status.

### Unicode ordering and upgrades

Legacy value ties and modern writer ties use the same order on Erlang and
JavaScript, without Unicode normalization. For example, an imported legacy
value `"\u{10000}"` wins over `"\u{e000}"` at an equal timestamp in either
merge order. For modern assignments, that example applies to writer IDs,
not to the child payloads.

Older JavaScript versions used UTF-16 order and chose `"\u{e000}"` for the
legacy value conflict. Erlang's ordering is unchanged. Upgrade peers that
exchange affected Unicode values or IDs together; peers using different
ordering rules can disagree. Coordinate this with the legacy-map cutover
above, rather than mixing legacy deltas with modern generations.

An upgrade cannot restore a losing value that no replica retained. The
[Replica IDs guide](/guides/replica-ids/#unicode-ordering-and-upgrades) describes
the related correction for replica-ID ties and historical sequence state.

See [Delta-State Replication](/advanced/delta-state/),
[JSON Serialization](/advanced/serialization/), and
[Replica IDs](/guides/replica-ids/).
