---
title: Installation
description: How to install lattice in your Gleam project.
---

## Umbrella package (recommended)

Use `lattice_crdt` for counters, registers, sets, maps, sequence, and text.
Install it from your Gleam project directory:

```sh
gleam add lattice_crdt
```

### Pin a version

`gleam add` writes a version range to `gleam.toml`. To pin a release,
replace the range under `[dependencies]` with the version you tested.
For example, if you tested version 4.0.0, use:

```toml
[dependencies]
lattice_crdt = "4.0.0"
```

Run `gleam deps download`. Check `manifest.toml` for the versions Gleam
selected. If you are building an application, commit both files so the next
build uses the same versions. Check the [releases on Hex](https://hex.pm/packages/lattice_crdt)
before you change the pin.

### Import modules

Import each module by its package name:

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_registers/lww_register
import lattice_maps/or_map
```

## Presence

The umbrella does not include presence. To track
[who is online](/guides/presence/), install `lattice_presence`:

```sh
gleam add lattice_presence
```

## Individual packages

If you only need counters, install the counter package:

```sh
gleam add lattice_counters
```

Gleam also installs `lattice_core` because `lattice_counters` needs it. You
can import `lattice_core/replica_id` without a second `gleam add` command.

See [Packages](/packages/) for the full list and dependency diagram.

## When to choose which

Start with `lattice_crdt` for a prototype or an application that uses several
CRDT types. If binary size or dependency count matters, install the individual
packages you need. Use `lattice_presence` to track processes by topic and key,
store metadata, and control which replicas are visible.

## Target runtimes

Use the same lattice API on Erlang and JavaScript.

After installation, run the [Quick Start](/quick-start/) or read the
[Counters guide](/guides/counters/).
