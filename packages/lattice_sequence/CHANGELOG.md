# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 - 2026-08-12

### Added

#### Add merge_as for order-independent replica identity

`merge` keeps the first argument's replica id, so applying an incoming delta as `merge(delta, state)` silently hands the local state the sender's identity and later local edits mint colliding item IDs. `merge_as(a, b, replica)` takes the local identity explicitly and is order-independent in every field. The `merge(self, other)` contract is now documented on `merge`, on the delta-producing functions, and in the module docs.

## v1.0.1 - 2026-08-04

### Changed

#### Document that a move record permanently disables compact

The compact docs previously suggested a replica holding a move could compact again after merging a peer that had already stabilized the item. It cannot: nothing clears a move record, so such a replica stops reclaiming tombstones and origins for good. The docs now state that plainly and record why the guard cannot be relaxed. The unreachable settled-move stabilization case is gone from the classifier.

### Fixed

#### Stack co-gap moves in op order regardless of how each resolved

Concurrent moves landing in the same gap now stack left to right in op order even when some resolve against the gap's right boundary and others fall back to its left anchor. Previously a move that kept its right boundary was skipped by later movers in the same gap, so the visible mover order could disagree with the op order.

## v1.0.0 - 2026-07-07


### MajorRelease

#### Stable 1.0 release with a committed public API

`lattice_sequence` is now 1.0. Its generic sequence CRDT API — index-based insert, delete, and move operations, mergeable deltas, JSON serialization, position anchors, and tombstone compaction — is stable and safe to depend on. From this release on, the package follows semantic versioning, so any future breaking change will come with a new major version.


### Added

#### Add generic sequence CRDT package

Introduces `lattice_sequence/sequence` with index-based insert/delete/move operations, mergeable deltas, generic JSON codecs, and YATA-style left/right origin ordering for ordered-list CRDT values.

#### Add stable position anchors with `anchor_at`, `resolve`, and JSON serialization

Anchors name a gap between items and survive concurrent edits and merges: `anchor_at`/`try_anchor_at` create one from a visible index with a `Bias` (`Before` or `After`) controlling which side of the gap it sticks to, and `resolve`/`try_resolve` map it back to a current index. `start_anchor` and `end_anchor` provide sentinels, and `anchor_to_json`/`anchor_from_json` let anchors travel between replicas for shared-cursor features. Anchors on deleted items collapse to the gap left behind, and anchors follow moved items.

#### Add `compact` for tombstone garbage collection and block merging

`compact(sequence, stable)` takes a stability frontier (a `VersionVector` covering everything no in-flight or future op can reference, e.g. derived from a global sequencer's acknowledgement floor) and rewrites the stable region: stable tombstones are dropped, runs of adjacent same-replica items with sequential counters merge into compact value blocks, and stable items shed their origins and move slots. Every dropped ID gets a forwarding entry pointing at its retained neighbors so anchors and rebased ops still resolve; hosts bound the map with `remove_forwardings` and can read the applied frontier with `frontier`. `translate_origins` rebases a delta from an evicted client onto a compacted state, hard-failing with `UnknownOriginTarget` when a forwarding has expired. Deletes now mint an op ID (bumping the replica counter) so a frontier can distinguish acknowledged deletes from in-flight ones, and the state JSON envelope (`"v": 1`) carries segments, forwardings, and the applied frontier. States holding move records are not compacted; compact during move-free windows.

#### Add `insert_many`, `insert_many_with_delta`, and `try_insert_many_with_delta`

Insert a run of values at consecutive indices in a single operation, reported as one combined delta instead of one delta per value. `try_insert_with_delta` now delegates to the batched path.


### Performance

#### Splice local inserts into the stored order instead of rebuilding it

When the state holds no live move record, stored order is already the canonical order, so a local insert is spliced directly in place (O(n)) rather than re-deriving the whole canonical order twice (O(n^2)). States holding a live move fall back to the previous rebuild path. The emitted delta is unchanged, so convergence is unaffected.
