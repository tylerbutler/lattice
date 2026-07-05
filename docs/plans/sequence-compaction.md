# Plan: Sequence Compaction (Tombstone GC + Block Merging)

> Status: implemented (2026-07-04) — see "Implementation notes" at the end
> for where the built design deviates from or refines this plan.
> Scope: `packages/lattice_sequence` (compaction, block representation,
> forwarding map) with knock-on effects in `packages/lattice_text` (anchors)
> and the state JSON envelope.
> Assumes: deployments run a **global sequencer** — a server (or total-order
> broadcast) that assigns every op a global sequence number and tracks
> per-client acknowledgements. The library stays transport-agnostic; the
> sequencer is how the host derives the stability input cheaply.
> Also assumes: **`lattice_sequence` and `lattice_text` have never been
> released** (confirmed 2026-07-04) — no documents and no readers exist, so
> the envelope shape changes in place and stays `"v": 1` (see
> Serialization).
> Related: `docs/plans/text-crdt-cursor-anchoring.md` — **shipped** (#89,
> `6e95f95`). Anchors resolve through tombstones today; this plan defines
> what happens to them when tombstones go away.

## Problem

`lattice_sequence` never garbage-collects. Every deleted item persists as a
tombstone (`sequence.gleam:48`), and every grapheme in `lattice_text` is a
full `Item` carrying an ID, two origins, and a move slot. Long-lived
documents grow without bound in both memory and serialized size, dominated
by (a) tombstones and (b) per-grapheme item overhead on text that will never
change again.

Tombstones cannot simply be dropped: they prevent resurrection during
state-based merge, they order concurrent inserts (YATA origins may reference
them), and the anchoring plan resolves deleted anchors through them. Removal
is only safe once an item is **causally stable** — no in-flight or future op
can reference it.

## Why a sequencer changes the problem

Without coordination, causal stability requires tracking a version-vector
frontier across all replicas. With a global sequencer it collapses to a
single integer:

- Every op gets a global sequence number.
- Each client acks the highest seq it has integrated.
- The **ack floor** is `min(acked_seq)` over active sessions.

Any op created by a client *after* it acked seq `s` can only reference items
that client considered live at that point. Once the floor passes a delete,
no arriving op can reference the tombstone as an insert origin or move
target. Everything below the floor is compactable, unconditionally.

The floor also serves op-log truncation and snapshot placement, which the
host needs anyway.

## Goal

Two-tier state with a floor-driven compaction pipeline:

- **Stable prefix** (at or below the floor): tombstones removed, contiguous
  runs merged into compact blocks, origins dropped (nothing can be
  concurrent with the stable prefix anymore).
- **Volatile suffix** (above the floor): full YATA items, exactly as today.

The floor advancing moves the boundary. Compaction is a pure library
function; the host decides when to call it and with what stability input.

## Design

### Stability input

The library does not know about sequence numbers. Compaction takes a
stability frontier expressed in terms the library already speaks — a
`VersionVector` from `lattice_core` describing "everything causally at or
below this is stable":

```gleam
pub fn compact(seq: Sequence(a), stable: VersionVector)
  -> #(Sequence(a), ForwardingMap)
```

A sequencer host derives `stable` trivially: it is the version vector
accumulated by replaying ops up to the ack floor. Hosts without a sequencer
could compute it some other way; nothing in the library binds to the
transport. Items are stable when their insert **and** (if deleted) their
delete are dominated by `stable`, and no move op above the frontier targets
them.

**Prerequisite — deletes must mint dots.** Today a tombstone is just
`deleted: Bool` and `try_delete_with_delta` does not bump the replica
counter, so a delete produces no dot a `VersionVector` can dominate: given
only the current state, `compact` cannot tell an acked delete from one still
in flight, and dropping the latter's tombstone resurrects the item on merge.
Deletes must start minting counters (like moves already do) and tombstones
must record the delete `OpId`. This changes the state shape (envelope stays
v1 — see Serialization) and lands in step 1 of the sequencing below.

### Compaction pass

For the stable region, in order:

1. **Drop tombstones.** Emit a forwarding entry for each (see below).
2. **Merge runs into blocks.** Adjacent stable items from the same replica
   with strictly sequential counters collapse into a block:
   `Block(first_id: ItemId, values: List(a))` with implicit sequential IDs.
   For text this is the dominant win — one block per typing burst instead of
   one item per grapheme. Note this is best-case: inserts, moves, and (after
   the delete-dots prerequisite) deletes share one counter stream per
   replica, so any interleaved op breaks counter sequentiality and starts a
   new block. Correctness is unaffected; compression is just patchier than
   "one block per burst" on move/delete-heavy histories.
3. **Strip origins and move slots.** Origins only disambiguate concurrent
   inserts; below the frontier there are none. Blocks carry no origins.

**Representation: interleaved segments, not prefix + suffix.** The floor
separates ops *causally*, not *positionally* — the moment a user types in
the middle of old, compacted text, the new volatile item sits between two
halves of a block, with origins pointing at block-interior IDs. So a
two-list `stable_blocks + items` model breaks on the most common edit there
is. Instead:

```gleam
type Segment(a) {
  Block(first_id: ItemId, values: List(a))   // implicit sequential IDs
  Live(Item(a))                              // full YATA item, as today
}
// Sequence(a) internally: List(Segment(a))
```

Consequences the implementation must handle:

- **Block splitting.** An insert whose origin falls inside a block splits it
  into two blocks around the insertion point (cheap: the value list splits;
  nothing re-expands to items).
- **Origin resolution into blocks.** ID lookup must resolve block-interior
  IDs via the implicit `(replica, first_counter + offset)` arithmetic, in
  origin walks and in anchor/forwarding resolution alike.
- **Blocks stay out of `order_items`.** The YATA reordering pass runs only
  over `Live` items (relative to fixed block boundaries). This is also where
  the CPU win comes from: `order_items` is quadratic-ish over the whole item
  list today, and compaction shrinks its input to the volatile set.

Public functions (`values`, `length`, `insert`, `merge`, …) are unaffected
in signature. IDs remain `(replica, counter)` everywhere — re-numbering to
sequencer positions buys nothing and would break anchors and forwardings.

### Forwarding map

When a tombstone is dropped, anything still holding its ID (anchors, rebased
ops from evicted clients) needs a landing spot. Compaction emits:

```gleam
compacted_id -> Option(ItemId)  // gap after this left neighbor; None = document start
```

Properties:

- **Bounded.** The host retains forwardings for the last K compaction rounds
  or a TTL; after expiry, lookups hard-fail and the holder must re-anchor or
  resync. The library defines the type and lookup; retention policy is the
  host's.
- **No intra-pass chains.** Within a single pass, a run of adjacent dropped
  tombstones must all forward to the nearest *retained* left neighbor — an
  entry never points at another ID dropped in the same pass.
- **Composable across passes.** If a forwarding target is itself later
  compacted into a block, the entry re-points at the block-interior implicit
  ID (which block splitting keeps resolvable), so chains never form across
  rounds either.

### Anchor interaction (amends the anchoring plan)

Anchors are read-only and must **not** gate the ack floor — a client holding
an anchor to a compacted item must not block GC for everyone.

- `try_resolve` gains a forwarding-map parameter (or the map is carried in
  the sequence value — decide during implementation; prefer carrying it so
  existing signatures survive). A missing `ItemId` found in the map resolves
  to the forwarded gap — semantically identical to today's tombstone
  collapse, stored more compactly.
- After forwarding expiry, `try_resolve` returns `UnknownAnchorTarget`. The
  error's contract widens from "not merged yet" to "not merged yet, or
  compacted and expired"; anchors shipped in #89, so this lands as a doc
  update on `try_resolve` / `AnchorError` in `sequence.gleam`.
- The asserting `resolve` panics on `UnknownAnchorTarget`. Today that only
  happens for never-merged foreign anchors; once forwardings can expire, any
  long-lived anchor can trip it. Document that hosts holding anchors across
  compaction rounds must use `try_resolve` and treat failure as "re-anchor".
- Ephemeral anchors (cursors, presence) self-heal by re-anchoring on
  resolution failure — no compaction awareness needed.
- Durable anchors (comment spans, bookmarks) are out of scope here; the
  candidate designs are owner-side self-healing on every resolve, or an
  anchor registry that compaction rewrites in-pass. Revisit after the
  anchoring plan ships.

### Eviction and rebase

A slow or offline client freezes the floor, so the host needs a session
policy: evict sessions that have not acked within a window. An evicted
client cannot state-merge its stale state back (tombstones it depends on may
be gone). Rejoin protocol:

1. Fetch the current snapshot (compacted state at the floor) + op suffix.
2. **Rebase** local unacked ops onto it: origins referencing compacted IDs
   translate through the forwarding map; expired forwardings force the op to
   degrade to a position-based re-insert (or be dropped, host's choice).
3. Resume acking.

The library's contribution is the origin-translation function; session
tracking, eviction, and the rejoin handshake are host concerns.

### Serialization

The JSON envelope changes shape: segments (blocks + items), the forwarding
map, per-tombstone delete `OpId`s (the prerequisite above), and the
**applied frontier** — the `VersionVector` the state was last compacted at.
The frontier must be carried in the state, not just passed to `compact`:
without it, "older frontier is a no-op" is uncheckable and merge cannot
tell which side is compacted further.

**No version bump.** `lattice_sequence` and `lattice_text` have never been
released, so no code or documents pin the current shape — the envelope is
redefined in place and stays `"v": 1`. There is no migration, no old-shape
decoder, and no early transitional release; the shape change ships together
with delete dots. Keep the `v` field itself: it costs nothing and is the
hook for whatever migration a *post*-release shape change needs. A payload
in the current (pre-plan) shape simply fails field decoding — acceptable,
since by assumption none exist.

## Notes / considerations

- **Merge across the boundary**: `merge(a, b)` where both sides share the
  same stable region reduces to merging volatile items; assert stable-region
  equality by comparing block digests rather than re-walking. Merging states
  compacted at *different* floors (compare stored frontiers to find the
  newer side) needs the newer side's forwarding map — define this precisely
  during implementation; it is the trickiest correctness spot.
- **Idempotence**: `compact` at the same frontier must be a no-op; at an
  older frontier than the stored applied frontier, also a no-op (floors
  only advance).
- **`lattice_text` surface**: no API change; text inherits compaction
  through the sequence. Add a text-level `compact` passthrough only if
  callers need it without importing `lattice_sequence`.
- **Multi-target**: must compile and pass on Erlang and JavaScript;
  block-merging is pure list work, no target-specific code expected.
- **Ordering invariant**: compaction must preserve the exact visible order
  `values` produced before the pass — property-test this, it is the whole
  correctness bar.

## Testing

- **Unit**: compact empty / all-stable / all-volatile / mixed sequences;
  tombstone drop; a tombstone whose delete dot is *above* the frontier is
  retained; run-merging across replica boundaries and across counter gaps
  (must *not* merge); insert into the middle of a block splits it and
  preserves values/order; idempotence; frontier regression no-op.
- **Property** (the core suite): for random edit histories and a random
  stability frontier — (1) `values(compact(s)) == values(s)`;
  (2) `merge(compact(s), delta) == compact(merge(s, delta))` for deltas
  entirely above the frontier; (3) anchor resolution before/after compaction
  agrees while forwardings are retained; (4) compact-then-compact equals
  compact-once.
- **Rebase**: op with origins below the frontier translates through the
  forwarding map and lands at the same visible position.
- **Serialization**: round-trip covering segments, forwarding map,
  frontier, and delete `OpId`s, for both compacted and never-compacted
  states; an unknown `v` is rejected with the version-mismatch error.

## Validation

- `just format`, `just check`
- `just test-pkg lattice_sequence`, `just test-pkg lattice_text`, and
  `just test-js` — both targets.
- `just lint-pkg lattice_sequence`, `just lint-pkg lattice_text`
- Changelog entries: `lattice_sequence` minor (new API + envelope shape;
  the packages are unreleased, so the in-place shape change breaks no one).
  `lattice_text` patch or minor depending on whether the passthrough lands.

## Suggested sequencing

1. Delete dots + new envelope shape, in one release: deletes mint counters,
   tombstones record the delete `OpId`, envelope carries segments,
   forwardings, and frontier (still `"v": 1` — the packages are unreleased,
   so the shape changes in place). Everything else is blocked on this.
2. ~~Anchoring plan (`text-crdt-cursor-anchoring.md`)~~ — **done** (#89).
3. Compaction core: stability predicate, tombstone drop, forwarding map,
   anchor resolution through forwardings.
4. Block merging (interleaved segments, block splitting) + origin stripping.
5. Rebase/origin-translation helper for evicted-client rejoin.

## Out of scope (this plan)

- The sequencer itself, ack tracking, session eviction policy, and the
  rejoin handshake (host/server concerns; library provides the pure pieces).
- Durable-anchor registry / rewrite-in-pass (revisit after anchoring ships).
- Op-log truncation and snapshot storage/distribution.
- Compaction for other lattice packages (maps/sets have their own tombstone
  stories, e.g. `or_set.prune`, and are not touched here).

## Implementation notes (2026-07-04)

The plan shipped with these refinements, discovered while making the
property suite pass:

- **Ordering engine replaced.** The recursive origin-tree rebuild could not
  order live items against origin-stripped blocks. The implementation uses
  a canonical rebuild instead: elements at or below the frontier are pinned
  in stored order (their order converged before the frontier passed), and
  volatile items are integrated one at a time in Lamport order with the
  YATA/Yjs conflict scan. Every construction path (local ops and both merge
  directions) goes through the same rebuild, so merge convergence holds by
  construction.
- **Origins are creation-time invariants for the scan.** An insert records
  its visible left neighbor and that neighbor's successor in the CANONICAL
  (pre-move) order, which makes the conflict window empty at creation and
  provably free of compacted elements for causally valid ops. The scan
  compares forwarding-chased left origins (so dropped IDs behave like the
  gap they collapsed into) but RAW right origins (chasing those conflates
  ops created before and after a neighbor's delete).
- **Forwardings carry both neighbors.** Entries are
  `dropped_id -> #(left, right)` retained neighbors, not just the left
  gap: right targets are needed to rebase right origins and to resolve
  move-target gaps without inverting their stacking order.
- **Merge takes the covered order from the dominating frontier's side**
  (tiebroken deterministically for concurrent frontiers), reconciles flags
  in place, pools volatile items, and rebuilds. An item absent from a side
  whose frontier covers it is treated as compacted away and stays dropped.
- **Moves gate compaction.** `compact` is a no-op while any move record
  exists in the state. Stabilizing moved geometry would bake the
  displacement into the block skeleton while uncompacted peers still order
  concurrent edits against pre-move positions — the plan's "origins may
  reference tombstones" analysis understated moves. Volatile moves arriving
  AFTER compaction merge correctly and all merge directions converge, but a
  compacted replica can transiently disagree with a never-compacted one
  about the neighborhood of an item a peer concurrently moved; states
  re-align on the next merge. Move origins were reverted to visible-neighbor
  semantics so a volatile move's targets can never be dropped at the floor
  its creator acked. Lifting the gate needs a design pass (likely retaining
  minimal origin metadata for stable items).
- **Deletes carry the winning delete `OpId`** (concurrent deletes keep the
  smaller op deterministically), and delete/move both mint counters as
  planned.
