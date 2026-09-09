# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.2 - 2026-08-12

### Dependencies

#### Updated lattice_registers to 1.2.0

## v1.1.1 - 2026-08-04

### Fixed

#### Remove internal panic branches from LWWMap and ORMap merge

The merge implementations no longer contain an unreachable panic when resolving keys present on only one side; they now fold over each side's entries directly. Also corrects the LWWMap type documentation, which wrongly described the timestamp tie-break as first-argument-wins (the actual rule: tombstones win, otherwise the lexicographically greater value).

## v1.1.0 - 2026-05-16


### Added

#### Add delta-state API to ORMap

New opaque `ORMapDelta` type plus `or_map.update_with_delta`, `remove_with_delta`, `apply_delta`, `merge_deltas`, `empty_delta`, `delta_to_json`, and `delta_from_json`. Mutations return a small delta carrying only the touched keys, the OR-Set key-set delta, and sparse per-key CRDT values — much smaller than full-state messages for sync over unreliable transports such as websockets. `update_with_delta` validates value types with `Result`, and `apply_delta` validates `crdt_spec` while applying deltas idempotently and commutatively. Also adds `crdt.default_delta` and `crdt.is_empty_delta` helpers in the dispatch module.

## v1.0.0 - 2026-04-11


### Breaking

#### Extracted from monolithic `lattice` package into standalone `lattice_maps` package

Imports change from `import lattice/lww_map`, `import lattice/or_map`, and `import lattice/crdt` to `import lattice_maps/lww_map`, `import lattice_maps/or_map`, and `import lattice_maps/crdt`. Update all import paths accordingly. See the [packages overview](https://lattice.tylerbutler.com/packages/) for the full package structure.

#### `crdt.merge` and `or_map.merge` now return `Result` instead of bare values

`crdt.merge(a, b)` returns `Result(Crdt, MergeError)` — type mismatches produce
`Error(TypeMismatch(expected: ..., found: ...))` instead of silently returning
the first argument. `or_map.merge(a, b)` returns `Result(ORMap, MergeError)` —
spec mismatches produce the same error. Callers must handle the `Result`;
for same-type merges, `let assert Ok(merged) = crdt.merge(a, b)` is idiomatic. See the [maps guide](https://lattice.tylerbutler.com/guides/maps/) for usage examples.


### Added

#### Add `or_map.prune(stable_vv)` for garbage collection

Call `or_map.prune(map, stable_vv)` with a version vector that all replicas have acknowledged to reclaim memory from removed keys and their associated CRDT values. Removals that are not yet causally stable are preserved to maintain merge correctness across replicas. The JSON format is bumped to v2 to persist removal metadata; v1 payloads are still accepted on read.

#### Add `lww_map.pruned_timestamp()` accessor

Returns the highest stable timestamp passed to `prune`, useful for monitoring
pruning state and debugging merge behavior.

#### Add `MergeError` type and `crdt.type_name` function

`MergeError` has a single variant `TypeMismatch(expected: String, found: String)`
with human-readable CRDT type names. `crdt.type_name(value)` returns the name
string for any wrapped `Crdt` value (e.g., `"g_counter"`, `"or_set"`).

#### Conflict-free replicated map types

- **`lww_map`** — Last-writer-wins map with timestamp-based conflict resolution per key. Supports `set`, `get`, `remove`, and `keys`. Removed keys leave tombstones; use `prune` to reclaim space.
- **`or_map`** — Observed-remove map where each key holds a nested CRDT value (counter, register, set, etc.). Use `update` with a callback to modify values, and `remove` to delete keys with add-wins semantics.
- **`crdt`** — Tagged union wrapper (`Crdt`) and spec type (`CrdtSpec`) for ORMap values. Supports all lattice CRDT types as nested values.

```gleam
let map = lww_map.new() |> lww_map.set("name", "Alice", 1)
lww_map.get(map, "name")  // -> Ok("Alice")
```

All types include JSON serialization via `to_json`/`from_json`. See the [maps guide](https://lattice.tylerbutler.com/guides/maps/) for details.


### Fixed

#### LWWMap `prune` now prevents deleted keys from reappearing after merge

Previously, pruning tombstones from one replica could cause deleted keys to reappear when merging with a stale replica that still had the old entry. `prune` now records a `pruned_timestamp` so that `merge` automatically discards entries at or below the pruned threshold. JSON serialization is bumped to v2 to persist the pruned timestamp; `from_json` still accepts v1.
