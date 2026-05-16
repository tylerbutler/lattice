---
title: Installation
description: How to install lattice in your Gleam project.
---

## Umbrella package (recommended)

Install `lattice_crdt` to get every CRDT in one dependency:

```sh
gleam add lattice_crdt
```

Even with the umbrella, imports use the sub-package names:

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_registers/lww_register
import lattice_maps/or_map
```

Install `lattice_presence` separately when you need distributed presence:

```sh
gleam add lattice_presence
```

## Individual packages

If you only need one category of CRDT, depend on that package directly:

```sh
gleam add lattice_counters
```

Transitive dependencies are pulled in automatically. For example,
`lattice_counters` depends on `lattice_core`, so you can import
`lattice_core/replica_id` without adding `lattice_core` explicitly.

See [Packages](/packages/) for the full list and dependency diagram.

## When to choose which

- **`lattice_crdt`** — getting started, prototyping, or using CRDTs from
  multiple categories.
- **`lattice_presence`** — topic/key/pid presence tracking with metadata and
  replica visibility.
- **Individual packages** — production deployments where you want to minimize
  dependency count or binary size.

## Target runtimes

All packages target both Erlang and JavaScript runtimes, so the same API works
across both Gleam targets.

After installing, continue with the [Quick Start](/quick-start/) or browse the
[guides](/guides/counters/).
