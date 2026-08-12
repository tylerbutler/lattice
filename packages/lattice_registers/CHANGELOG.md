# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.2.0 - 2026-08-12

### Added

#### Expose `lww_register.timestamp` and `lww_register.replica_id`, two pure accessors mirroring `value`. Because `set` accepts only strictly greater timestamps, a caller stamping writes from a wall clock has to stay ahead of the timestamp already held — otherwise two writes inside the same clock tick are unordered and the second is silently dropped. Reading the timestamp back makes that possible, including seeding a logical clock from a decoded snapshot without paying a JSON encode per key. `replica_id` returns the replica that wrote the value currently held, which after a merge is the replica whose write won. Neither accessor exposes the constructor, so the opacity that keeps the merge rule enforceable is unchanged.

## v1.1.0 - 2026-05-16


### Added

#### Add delta-state mutator APIs to LWWRegister and MVRegister

New `lww_register.set_with_delta` and `mv_register.set_with_delta` return both the new state and a small delta of the same type. The MV-Register delta carries the new tag/value plus the writer's full vclock, encoding the causal context the write supersedes so remotes correctly retract dominated tags. Deltas merge into remotes via the existing `merge` function. Existing `set` is unchanged and now delegates internally.


### Fixed

#### Prevent divergence when an LWW-Register set is rejected locally

When `lww_register.set` is called with a timestamp not strictly greater than the current one, the local state is correctly left unchanged. The companion `set_with_delta` now also returns the unchanged register as the delta in that case, ensuring a rejected write cannot win on a remote replica with an even smaller timestamp and cause divergence between local and remote.

## v1.0.0 - 2026-04-11


### Breaking

#### Extracted from monolithic `lattice` package into standalone `lattice_registers` package

Imports change from `import lattice/lww_register` and `import lattice/mv_register` to `import lattice_registers/lww_register` and `import lattice_registers/mv_register`. Update all import paths accordingly. See the [packages overview](https://lattice.tylerbutler.com/packages/) for the full package structure.


### Added

#### Conflict-free replicated register types

- **`lww_register`** — Last-writer-wins register. Resolves conflicts by timestamp; the most recent write wins. Use for values where "latest update wins" is acceptable (e.g. user profile fields).
- **`mv_register`** — Multi-value register. Preserves all concurrent writes, returning them as a list via `value`. Use when your application needs to present or resolve conflicts explicitly.

```gleam
// Concurrent writes to an MV register are all preserved
let a = mv_register.new(replica_id.new("node-a")) |> mv_register.set("hello")
let b = mv_register.new(replica_id.new("node-b")) |> mv_register.set("world")
mv_register.value(mv_register.merge(a, b))  // -> ["hello", "world"]
```

All types include JSON serialization via `to_json`/`from_json`. See the [registers guide](https://lattice.tylerbutler.com/guides/registers/) for details.


### Fixed

#### Validate MVRegister state during JSON deserialization

`mv_register.from_json` now rejects payloads with invalid causal metadata (e.g. negative counters or tags that exceed the version vector). Previously, malformed JSON could produce a register in an inconsistent state that would behave incorrectly on merge.
