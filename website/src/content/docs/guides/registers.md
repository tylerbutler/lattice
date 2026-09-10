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

`LWWRegister(a)` stores a payload, the timestamp of its winning write,
and that write's author.

```gleam
import lattice_core/replica_id
import lattice_registers/lww_register

pub fn main() {
  let local = replica_id.new("node-a")
  let register = lww_register.new("draft", 1, local)

  let updated = lww_register.set(register, "published", 2, local)

  lww_register.value(updated)
  // -> "published"
}
```

`lww_register.set` only applies when the new timestamp is strictly greater than
the current timestamp.

Labeled calls to `new`, `set`, and `set_with_delta` use `value:`:

```gleam
let updated =
  lww_register.set(
    register: register,
    value: "published",
    timestamp: 2,
    replica_id: local,
  )
```

Every update requires the local writer ID. When upgrading, add that fourth
argument to `set` and `set_with_delta`; replace old `set_as` calls with `set`
and old `set_as_with_delta` calls with `set_with_delta`.

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

### Stamping writes from a wall clock

The strict comparison in `set` is what keeps `merge` commutative, but it makes a
wall clock an unsafe timestamp source on its own. A millisecond clock stands
still for a millisecond at a time, so two writes inside the same tick carry the
same timestamp, and the second one is dropped — even though both came from the
same replica and their order is not in doubt. Paint a cell and erase it in the
same millisecond, and the erase vanishes.

Only the writer knows its two writes are ordered, so the fix belongs on the
stamping side: keep the wall clock, but never let it fall behind the timestamp
already held. `lww_register.timestamp` reads that back.

```gleam
import gleam/int
import lattice_registers/lww_register.{type LWWRegister}

/// `now` is your own millisecond wall clock.
pub fn stamp(register: LWWRegister(String), now: Int) -> Int {
  int.max(now, lww_register.timestamp(register) + 1)
}
```

That is the logical half of a [hybrid logical
clock](https://cse.buffalo.edu/tech-reports/2014-04.pdf): the wall clock still
drives the value forward, and the `+ 1` fallback keeps successive local writes
strictly ordered when it does not move.

The same applies across a restart. A client that loads a snapshot must seed its
clock from what the snapshot holds, or its first write to a key can lose to a
checkpoint written by a replica whose clock ran ahead. Fold `timestamp` over the
decoded registers to recover that starting point — no JSON round trip needed.

A writer must not reuse one `(timestamp, replica_id)` stamp for different
values. Generate a fresh replica ID after a process restart, or persist and
restore a logical clock that advances beyond every write made by the reused ID.

`lww_register.replica_id` reads back the other half of the metadata: the replica
that wrote the value currently held. After a merge that is the replica whose
write won, which makes it useful for provenance and for tie-breaking
consistently with `merge` in your own code.

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

## Typed serialization and new authors

Both register modules provide `to_json_with(value, encode)` and
`from_json_with(input, decoder)` for generic payloads. Existing String
codec entry points keep their formats.

An adopted LWWRegister retains the author of its winning write. Pass the local
writer to `set(register, value, timestamp, local_id)` or
`set_with_delta(register, value, timestamp, local_id)` to author a new write.
In a map update callback, use the provided `context.replica_id`.
