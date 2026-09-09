# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 - 2026-08-20

### Added

#### Add `new_incarnation` for restart-safe replica identities

A replica that restarts under the same identity it used before can collide with the causal history peers still hold for it, which silently drops its fresh joins or resurrects presence it had already left. `new_incarnation(base)` derives a replica ID that is unique per process run while keeping a stable base identity, and `base_replica` and `same_base` let callers recover and compare that base without parsing the encoded string. `new` is unchanged for callers that already supply a globally unique ID per run.

### Fixed

#### Keep pruned replicas from reappearing

Pruning a replica discarded the causal watermark that recorded what had already been seen from it, so a lagging peer's older sync could restore the entry it had just removed. Pruning now retains that watermark, drops the replica's entries and pending clocks, and applies only to replicas explicitly marked down. Live replicas are unaffected.
#### Stop restarted replicas from resurrecting as ghost presence

After a restart, a peer holding a higher clock from the previous run could silently swallow the replica's fresh join, or replay a cached entry from that earlier run so it showed up as present again. A replica now rejects incoming values owned by a different incarnation of its own identity while still merging their causal context, so syncing back to peers clears the stale entries instead of reviving them.
#### Shrink full-state payloads by dropping already-covered clocks

Out-of-order updates park clocks in a pending cloud until the gaps ahead of them fill in. Clocks that the merged context already covered were never cleared, so the cloud grew without bound and inflated every full-state payload sent afterwards. Compaction now discards covered clocks before folding in the contiguous run.

## v1.0.1 - 2026-08-04

### Fixed

#### Correct the doc comment on replica()

The doc comment said "Get the current vector clock"; it now describes the returned replica name.

## v1.0.0 - 2026-05-16


### Breaking

#### Initial release: pure distributed presence CRDT

Provides `lattice_presence/presence_state` with topic/key/pid/meta tracking,
opaque CRDT state, add-wins observed-remove semantics, replica up/down
visibility, pure `merge`, `merge_with_diff` for Phoenix-style join/leave
diffs, and `lattice_presence/state_json` for validated cross-node
serialization. Implementation and acceptance test suite ported from Beryl's
custom presence CRDT (#62).
