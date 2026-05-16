# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 - 2026-05-16


### Added

#### Add delta-state mutator APIs to GCounter and PNCounter

New `g_counter.increment_with_delta` / `try_increment_with_delta` and `pn_counter.{increment,decrement}_with_delta` / their `try_*` variants return both the new state and a small delta of the same type. Deltas are merged into remote replicas via the existing `merge` function, enabling efficient incremental sync over unreliable transports (e.g. websockets) without shipping full state. Existing mutators are unchanged and now delegate to the delta versions internally.


## v1.0.0 - 2026-04-11


### Breaking

#### Extracted from monolithic `lattice` package into standalone `lattice_counters` package

Imports change from `import lattice/g_counter` and `import lattice/pn_counter` to `import lattice_counters/g_counter` and `import lattice_counters/pn_counter`. Update all import paths accordingly. See the [packages overview](https://lattice.tylerbutler.com/packages/) for the full package structure.


### Added

#### Conflict-free replicated counter types

- **`g_counter`** — Grow-only counter for monotonically increasing values (e.g. event counts, page views). Supports `increment`, `value`, and `merge`. Use `try_increment` for explicit error handling on negative deltas.
- **`pn_counter`** — Positive-negative counter that supports both `increment` and `decrement` (e.g. inventory levels, user counts). Built on a pair of grow-only counters internally.

```gleam
let counter = g_counter.new(replica_id.new("node-a")) |> g_counter.increment(5)
g_counter.value(counter)  // -> 5
```

All types include JSON serialization via `to_json`/`from_json`. See the [counters guide](https://lattice.tylerbutler.com/guides/counters/) for details.


