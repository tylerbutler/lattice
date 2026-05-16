# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 - 2026-05-16


### Added

#### Add delta-state mutator APIs to GSet, TwoPSet, and ORSet

New `g_set.add_with_delta`, `two_p_set.{add,remove}_with_delta`, and `or_set.{add,remove}_with_delta` return both the new state and a small delta of the same type. The OR-Set delta carries only the changed dot/tombstones plus the causal context required for any remote (including ones that have never observed the element) to converge. Deltas merge into remotes via the existing `merge` function. Existing mutators are unchanged and now delegate to the delta versions internally.

#### Add ORSet ergonomic helpers for adapter code

Adds `or_set.Diff`, `or_set.diff`, `or_set.merge_with_diff`, `or_set.remove_all`, and `or_set.remove_where` for consumers that need observable value changes or bulk removals without inspecting internal tags.


## v1.0.0 - 2026-04-11


### Breaking

#### Extracted from monolithic `lattice` package into standalone `lattice_sets` package

Imports change from `import lattice/g_set`, `import lattice/two_p_set`, and `import lattice/or_set` to `import lattice_sets/g_set`, `import lattice_sets/two_p_set`, and `import lattice_sets/or_set`. Update all import paths accordingly. See the [packages overview](https://lattice.tylerbutler.com/packages/) for the full package structure.

#### Bump ORSet JSON serialization schema from v1 to v2

`or_set.to_json` now emits `"v": 2` with a `pruned` version vector field. `or_set.from_json` accepts both v1 and v2, so existing serialized data can still be decoded. However, data written by the new version cannot be read by older versions.


### Added

#### Add `or_set.prune(stable_vv)` for tombstone compaction

Call `or_set.prune(set, stable_vv)` with a version vector that all replicas have acknowledged to reclaim memory from removed elements. The merge algorithm detects stale tags from replicas that haven't caught up, preventing removed elements from reappearing after pruning.

#### Add `or_set.remove_with_bound` and `or_set.pruned_vv`

`remove_with_bound(set, element)` works like `remove` but also returns a `VersionVector` representing the causal context of the removal. `pruned_vv(set)` returns the version vector below which tombstones have been garbage-collected. These are primarily useful for building higher-level data structures like `or_map` that need to track when a removal is safe to finalize.

#### Conflict-free replicated set types

Three set types with different trade-offs:

- **`g_set`** — Grow-only. Elements can be added but never removed. Simplest and most efficient.
- **`two_p_set`** — Two-phase. Elements can be removed once, but a removed element can never be re-added.
- **`or_set`** — Observed-remove. Elements can be freely added and removed with add-wins semantics: if one replica adds an element while another concurrently removes it, the add wins.

```gleam
let a = or_set.new(replica_id.new("node-a")) |> or_set.add("item")
let b = or_set.new(replica_id.new("node-b")) |> or_set.add("item") |> or_set.remove("item")
or_set.contains(or_set.merge(a, b), "item")  // -> True (add wins)
```

All types include JSON serialization via `to_json`/`from_json`. See the [sets guide](https://lattice.tylerbutler.com/guides/sets/) for details.


