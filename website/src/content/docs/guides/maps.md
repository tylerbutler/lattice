---
title: Maps
description: Using LWWMap and ORMap for distributed key-value storage.
---

Maps are provided by the `lattice_maps` package. If you installed the
`lattice_crdt` umbrella, they are already available.

lattice ships with two map CRDTs:

- `LWWMap` for timestamp-based last-writer-wins key/value storage
- `ORMap` for add-wins maps whose values are themselves CRDTs

## LWWMap (Last-Writer-Wins Map)

`LWWMap` stores `String` keys and `String` values with timestamps.

```gleam
import lattice_maps/lww_map

pub fn main() {
  let profile =
    lww_map.new()
    |> lww_map.set("name", "Ada", 1)
    |> lww_map.set("role", "admin", 2)

  lww_map.get(profile, "name")
  // -> Ok("Ada")
}
```

### Update and remove semantics

- `lww_map.set(map, key, value, timestamp)` only replaces an existing entry when
  `timestamp` is strictly greater than the current timestamp for that key.
- `lww_map.remove(map, key, timestamp)` inserts a tombstone. Equal or older
  timestamps are ignored for the same reason.

Tombstones participate in merges, so a remove can still win later if it has the
newest timestamp.

### Equal-timestamp conflict resolution

`LWWMap` resolves equal timestamps deterministically:

- tombstones win over active values
- when both sides hold active values, the lexicographically greater string wins

```gleam
import lattice_maps/lww_map

pub fn main() {
  let left = lww_map.new() |> lww_map.set("label", "apple", 7)
  let right = lww_map.new() |> lww_map.set("label", "zebra", 7)

  let merged = lww_map.merge(left, right)

  lww_map.get(merged, "label")
  // -> Ok("zebra")
}
```

This tie-break keeps merges replica-order independent even when timestamps are
equal.

## ORMap (Observed-Remove Map)

`ORMap` is for maps whose values should also converge as CRDTs. You choose the
value type up front with a `CrdtSpec`.

Because `ORMap` uses types from multiple lattice packages, it is a good example
of where the `lattice_crdt` umbrella is convenient.

```gleam
import lattice_core/replica_id
import lattice_maps/crdt
import lattice_maps/or_map

let counters = or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
```

When you call `or_map.update`, lattice looks up the current value for that key.
If the key does not exist yet, it creates a default value from the chosen
`CrdtSpec` and passes that into your update function.

### Safe update helpers

A `case` expression is clearer than `assert` for destructuring the `Crdt` union
and keeps the example safe if you refactor later.

```gleam
import lattice_core/replica_id
import lattice_counters/g_counter
import lattice_maps/crdt
import lattice_maps/or_map

fn add_stock(value: crdt.Crdt, delta: Int) -> crdt.Crdt {
  case value {
    crdt.CrdtGCounter(counter) ->
      crdt.CrdtGCounter(g_counter.increment(counter, delta))

    other -> other
  }
}

pub fn main() {
  let inventory =
    or_map.new(replica_id.new("node-a"), crdt.GCounterSpec)
    |> or_map.update("widgets", fn(value) { add_stock(value, 4) })
    |> or_map.update("widgets", fn(value) { add_stock(value, 1) })

  case or_map.get(inventory, "widgets") {
    Ok(crdt.CrdtGCounter(counter)) -> g_counter.value(counter)
    _ -> 0
  }
  // -> 5
}
```

Because the map was created with `crdt.GCounterSpec`, the `"widgets"` key starts
at the default `GCounter` value of zero.

### Merge behavior

`or_map.merge` returns a `Result` because it checks that both maps use the same
`CrdtSpec`:

```gleam
let assert Ok(merged) = or_map.merge(map_a, map_b)
```

The merge combines two pieces of state:

1. the key tracker, using add-wins observed-remove semantics
2. the value at each key, using `crdt.merge`

That means a concurrent `update` and `remove` of the same key keeps the key in
the merged map, and concurrent updates to the nested CRDT converge using that
CRDT's own merge rules.
