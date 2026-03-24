---
title: Installation
description: How to install lattice in your Gleam project.
---

Add lattice from Hex:

```sh
gleam add lattice_crdt
```

Then import the modules you need:

```gleam
import lattice/g_counter
import lattice/lww_register
import lattice/or_map
```

The package targets both Erlang and JavaScript runtimes, so the same API works
across both Gleam targets.

After installing, continue with the [Quick Start](/quick-start/) or browse the
[guides](/guides/counters/).
