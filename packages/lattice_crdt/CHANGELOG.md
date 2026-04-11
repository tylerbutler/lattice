# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0 - 2026-03-06

Initial release of lattice — a [CRDT](https://en.wikipedia.org/wiki/Conflict-free_replicated_data_type) library for Gleam targeting both Erlang and JavaScript runtimes. Every type converges automatically when replicas merge, with no coordination required. See the [documentation](https://lattice.tylerbutler.com) for guides and API reference.

#### Added

##### Counter types

Grow-only counters (`g_counter`) for monotonically increasing values, and positive-negative counters (`pn_counter`) that support both increment and decrement. Use `g_counter` when values only go up (e.g. event counts); use `pn_counter` when you need subtraction (e.g. inventory levels).

```gleam
let counter = g_counter.new("node-a") |> g_counter.increment(5)
g_counter.value(counter)  // -> 5

// Merge two replicas — values combine automatically
let merged = g_counter.merge(counter_a, counter_b)
```

##### Register types

Last-writer-wins registers (`lww_register`) resolve conflicts by timestamp — the most recent write wins. Multi-value registers (`mv_register`) preserve all concurrent writes, letting your application decide how to resolve them.

```gleam
// LWW: latest timestamp wins
let reg = lww_register.new("initial", 1, "node-a")
let reg = lww_register.set(reg, "updated", 2)

// MV: concurrent writes are all preserved
let merged = mv_register.merge(reg_a, reg_b)
mv_register.value(merged)  // -> ["value-a", "value-b"]
```

##### Set types

Three set types with different trade-offs:

- **`g_set`** — Grow-only. Elements can be added but never removed. Simplest and most efficient.
- **`two_p_set`** — Two-phase. Elements can be removed once, but a removed element can never be re-added.
- **`or_set`** — Observed-remove. Elements can be freely added and removed. Concurrent add and remove of the same element resolves in favor of the add (add-wins semantics).

```gleam
let a = or_set.new("node-a") |> or_set.add("item")
let b = or_set.new("node-b") |> or_set.add("item") |> or_set.remove("item")
let merged = or_set.merge(a, b)
or_set.contains(merged, "item")  // -> True (add wins)
```

##### Map types

Key-value maps with automatic conflict resolution:

- **`lww_map`** — Last-writer-wins semantics per key, with timestamp-based conflict resolution. Supports `remove` with tombstones.
- **`or_map`** — Observed-remove semantics with nested CRDT values. Each key holds a full CRDT (counter, register, set, etc.) that merges independently.

```gleam
let map = lww_map.new() |> lww_map.set("name", "Alice", 1)
lww_map.get(map, "name")  // -> Ok("Alice")
```

##### Causal context primitives

Version vectors (`version_vector`) for tracking happened-before relationships between replicas, and dot contexts (`dot_context`) for fine-grained causal tracking used internally by `or_set` and `or_map`. You typically interact with version vectors directly when configuring advanced merge or pruning behavior.

##### JSON serialization

All types include `to_json` and `from_json` functions for persisting state and transmitting it between nodes.

```gleam
let json_str = g_counter.to_json(counter) |> json.to_string
let assert Ok(restored) = g_counter.from_json(json_str)
```
