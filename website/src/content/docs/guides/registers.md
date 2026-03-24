---
title: Registers
description: Using LWWRegister and MVRegister for storing values.
---

Registers store a value rather than a collection. lattice provides two flavors:

- `LWWRegister` for single-value, timestamp-based conflict resolution
- `MVRegister` for preserving concurrent writes

## LWWRegister

`LWWRegister` stores a `String` and the timestamp of the write that produced it.

```gleam
import lattice/lww_register

pub fn main() {
  let register = lww_register.new("draft", 1)

  let updated = lww_register.set(register, "published", 2)

  lww_register.value(updated)
  // -> "published"
}
```

`lww_register.set` only applies when the new timestamp is strictly greater than
the current timestamp.

### Equal-timestamp ties

When two replicas merge registers with the same timestamp, lattice resolves the
tie deterministically by choosing the lexicographically greater string.

```gleam
import lattice/lww_register

pub fn main() {
  let left = lww_register.new("apple", 10)
  let right = lww_register.new("zebra", 10)

  let merged = lww_register.merge(left, right)

  lww_register.value(merged)
  // -> "zebra"
}
```

This keeps merges deterministic and replica-order independent even when clocks
collide.

## MVRegister

`MVRegister` keeps all concurrent values instead of picking one winner.

```gleam
import lattice/mv_register

pub fn main() {
  let left = mv_register.new("node-a") |> mv_register.set("hello")
  let right = mv_register.new("node-b") |> mv_register.set("world")

  let merged = mv_register.merge(left, right)

  mv_register.value(merged)
  // -> ["hello", "world"]
}
```

If one write causally supersedes another, the older value disappears. Multiple
values only remain when the writes were concurrent.
