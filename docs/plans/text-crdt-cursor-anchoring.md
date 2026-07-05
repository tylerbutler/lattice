# Plan: Cursor / Position Anchoring for Text CRDT

> Status: draft (2026-07-04)
> Scope: `packages/lattice_sequence` (generic anchor support) and
> `packages/lattice_text` (grapheme-level surface).
> Follow-up to `docs/plans/text-crdt-richer-operations.md`, which listed this
> as out of scope.

## Problem

All `lattice_text` positions are visible grapheme indexes. Indexes are
unstable: a remote insert or delete before a cursor shifts every index after
it, so an editor holding `cursor = 5` points at the wrong grapheme after a
merge. Editors, selections, and shared-cursor features (e.g. via
`lattice_presence`) need positions that survive concurrent edits.

The foundation already exists: `lattice_sequence` stores each item with a
stable `ItemId(replica_id, counter)` and keeps deleted items as tombstones
(`sequence.gleam:36`, `sequence.gleam:48`). Neither IDs nor tombstone
positions are exposed publicly, so nothing can be anchored to them today.

## Goal

Add **stable position anchors**: opaque values that name a position in the
text, created from a grapheme index, and resolvable back to a current index
after any sequence of local edits and merges. Implement generically in
`lattice_sequence`, surface at grapheme granularity in `lattice_text` —
mirroring the existing layering (text delegates, sequence owns identity).

Anchors are queries, not mutations: no `*_with_delta` variants. The
plain / `try_*` split still applies for fallible operations.

## Design

### Anchor model

An anchor names a **gap** between items (positions `0..length` inclusive),
not an item itself, because cursors sit between graphemes. Represent it as:

- `Start` — always resolves to 0.
- `End` — always resolves to `length` (tracks growth).
- `AtItem(id: ItemId, bias: Bias)` — attached to a specific item.

`Bias` controls which side of the gap the anchor sticks to when content is
inserted exactly at it:

- `Before` — anchor attaches to the item *after* the gap; concurrent inserts
  at the gap push the anchor right (it stays glued to its item).
- `After` — anchor attaches to the item *before* the gap; concurrent inserts
  at the gap land after the anchor (it stays put).

`anchor_at(seq, index, bias)` picks the item from the bias: `Before` binds to
the item at `index`, `After` binds to the item at `index - 1`. Boundary
positions with no item on the chosen side degrade to `Start` / `End`.

### Resolution

`resolve(seq, anchor) -> Int` counts visible items before the anchored item
(plus 1 for `After` bias when the item is alive). Because tombstones remain
in the ordered item list, an anchor whose item was **deleted** still resolves:
both biases collapse to the gap where the item used to be. Resolution is
total for any anchor whose `ItemId` exists in this replica's item list
(alive or tombstoned).

The one failure mode is an anchor referencing an `ItemId` this replica has
never seen (created remotely, not yet merged): `try_resolve` returns
`Error(UnknownAnchorTarget)`; plain `resolve` asserts, matching the module
convention.

### Sequence-level API (`lattice_sequence/sequence`)

```gleam
pub type Bias { Before After }
pub opaque type Anchor            // Start | End | AtItem(ItemId, Bias)
pub type AnchorError {
  AnchorIndexOutOfBounds(index: Int, length: Int)
  UnknownAnchorTarget
}

pub fn start_anchor() -> Anchor
pub fn end_anchor() -> Anchor
pub fn anchor_at(seq, index: Int, bias: Bias) -> Anchor            // asserts
pub fn try_anchor_at(seq, index: Int, bias: Bias)
  -> Result(Anchor, AnchorError)                                   // bounds: 0 <= index <= length
pub fn resolve(seq, anchor: Anchor) -> Int                         // asserts
pub fn try_resolve(seq, anchor: Anchor) -> Result(Int, AnchorError)
pub fn anchor_to_json(anchor: Anchor) -> json.Json
pub fn anchor_from_json(json_string: String)
  -> Result(Anchor, json.DecodeError)
```

`ItemId` stays opaque; anchors are the only public handle to it. JSON
encoding reuses `replica_id` serialization from `lattice_core` and a small
versioned envelope consistent with the existing sequence envelope, since
anchors must travel between replicas (shared cursors).

### Text-level API (`lattice_text/text`)

Thin wrappers so callers never import `lattice_sequence`:

```gleam
pub fn anchor_at(text, index: Int, bias: sequence.Bias) -> Anchor  // + try_
pub fn resolve_anchor(text, anchor: Anchor) -> Int                 // + try_
pub fn anchor_to_json / anchor_from_json
```

Decide during implementation whether to re-export `Bias` / `Anchor` /
`AnchorError` or alias them at the text level; prefer re-export to avoid
duplicate types (same choice as reusing `sequence.MoveError` today).

A selection is just a pair of anchors; no dedicated range type in this plan.
If a convenience is warranted, add `anchor_range(text, start, end) ->
#(Anchor, Anchor)` with `Before` bias on the start and `After` on the end so
concurrent edits at the edges don't grow the selection — optional, only if
trivial.

## Notes / considerations

- **Tombstone dependency**: anchors stay resolvable only while tombstones are
  retained. The sequence never garbage-collects tombstones today, so this
  holds unconditionally. `docs/plans/sequence-compaction.md` defines the
  interaction when compaction lands: compacted anchors resolve through a
  bounded forwarding map, and `UnknownAnchorTarget` widens to also mean
  "compacted and expired".
- **Move interaction**: `sequence.move` preserves item identity, so an anchor
  bound to a moved item follows it. Document this; it is the correct
  behavior for "cursor on a character" and falls out for free.
- **Merge is unchanged**: anchors live outside the CRDT state; no changes to
  `merge`, item encoding, or the state envelope. This is purely additive API.
- **No-op edits**: creating and resolving anchors must not bump the sequence
  counter or produce deltas.
- **Multi-target**: must compile and pass on Erlang and JavaScript.

## Testing

- **Sequence unit tests** (`lattice_sequence/test/`): anchor_at bounds and
  bias selection, Start/End sentinels, resolve after inserts/deletes before,
  at, and after the anchor gap; bias divergence for inserts exactly at the
  gap; resolve after the anchored item is deleted (both biases collapse);
  resolve after the anchored item is moved; `UnknownAnchorTarget` for a
  foreign anchor before merge and success after merge.
- **Text unit tests** (`test/text/`): grapheme-level wrappers, anchors across
  multi-grapheme inserts (emoji), interaction with `delete_range` /
  `replace_range` spanning the anchor.
- **Property tests** (`test/property/`): for random edit sequences —
  (1) resolution always lands in `[0, length]`; (2) an anchor on a live item
  with `Before` bias resolves to that item's current index (the grapheme
  under the anchor is unchanged); (3) create-then-resolve with no
  intervening edits is the identity; (4) resolution agrees on two replicas
  after merging the same states.
- **Serialization**: anchor JSON round-trip, including Start/End and both
  biases; decoding rejects malformed envelopes.

## Validation

- `just format`
- `just check`
- `just test-pkg lattice_sequence` and `just test-pkg lattice_text` (Erlang),
  plus `just test-js` — confirm both targets pass.
- `just lint-pkg lattice_sequence` and `just lint-pkg lattice_text`
- Changelog entries (changie) for both packages: minor, since this is
  additive public API.

## Out of scope (this plan)

- Integration with `lattice_presence` (sharing cursors as presence state) —
  natural follow-up once anchors serialize.
- Tombstone garbage collection and anchor compaction.
- Codepoint/character-indexed API variants.
- Rich-text concerns (marks, formatting spans).
