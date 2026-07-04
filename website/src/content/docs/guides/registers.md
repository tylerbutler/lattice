---
title: Registers
description: Using LWWRegister and MVRegister for storing values.
---

Registers are provided by the `lattice_registers` package. If you installed the
`lattice_crdt` umbrella, they are already available.

Registers store a value rather than a collection. lattice provides two flavors:

- `LWWRegister` for single-value, timestamp-based conflict resolution
- `MVRegister` for preserving concurrent writes

## LWWRegister (Last-Writer-Wins Register)

`LWWRegister` stores a `String`, the timestamp of the write that produced it,
and the replica ID of its creator.

```gleam
import lattice_core/replica_id
import lattice_registers/lww_register

pub fn main() {
  let register = lww_register.new("draft", 1, replica_id.new("node-a"))

  let updated = lww_register.set(register, "published", 2)

  lww_register.value(updated)
  // -> "published"
}
```

`lww_register.set` only applies when the new timestamp is strictly greater than
the current timestamp.

### Equal-timestamp ties

When two replicas merge registers with the same timestamp, lattice resolves the
tie deterministically using the replica ID. The register with the
lexicographically greater replica ID wins.

```gleam
import lattice_core/replica_id
import lattice_registers/lww_register

pub fn main() {
  let left = lww_register.new("apple", 10, replica_id.new("node-a"))
  let right = lww_register.new("zebra", 10, replica_id.new("node-b"))

  let merged = lww_register.merge(left, right)

  lww_register.value(merged)
  // -> "zebra"  (node-b > node-a)
}
```

This keeps merges deterministic and replica-order independent even when clocks
collide.

## MVRegister (Multi-Value Register)

`MVRegister` keeps all concurrent values instead of picking one winner.

```gleam
import lattice_core/replica_id
import lattice_registers/mv_register

pub fn main() {
  let left =
    mv_register.new(replica_id.new("node-a"))
    |> mv_register.set("hello")

  let right =
    mv_register.new(replica_id.new("node-b"))
    |> mv_register.set("world")

  let merged = mv_register.merge(left, right)

  mv_register.value(merged)
  // -> ["hello", "world"]
}
```

If one write causally supersedes another, the older value disappears. Multiple
values only remain when the writes were concurrent.

## Delta-state mutators

Registers expose `set_with_delta`:

- `lww_register.set_with_delta`
- `mv_register.set_with_delta`

Each returns both the new register state and a register delta. `MVRegister`
deltas carry the new value and the writer's vector clock so remote replicas can
remove values causally superseded by the write. See
[Delta-State Replication](/advanced/delta-state/) for the shared convention.
