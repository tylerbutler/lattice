# lattice_crdt Examples

Sample applications demonstrating the [lattice_crdt](https://hex.pm/packages/lattice_crdt) library.

## Running Examples

From this directory:

```sh
# Run a specific example
gleam run -m g_counter_example
gleam run -m pn_counter_example
gleam run -m lww_register_example
gleam run -m mv_register_example
gleam run -m g_set_example
gleam run -m two_p_set_example
gleam run -m or_set_example
gleam run -m lww_map_example
gleam run -m or_map_example
gleam run -m or_map_delta_websocket_example
gleam run -m or_map_sequence_text_example
gleam run -m nested_map_example
gleam run -m version_vector_example
gleam run -m sequence_example
gleam run -m text_example

# Run on JavaScript target
gleam run -m g_counter_example --target javascript
```

## Available Examples

### Counters

| Example | Description |
|---------|-------------|
| `g_counter_example` | Grow-only counter — increment and merge across replicas |
| `pn_counter_example` | Positive-negative counter — increment, decrement, and merge |

### Registers

| Example | Description |
|---------|-------------|
| `lww_register_example` | Last-writer-wins register — timestamp-based conflict resolution |
| `mv_register_example` | Multi-value register — preserves concurrent writes as multiple values |

### Sets

| Example | Description |
|---------|-------------|
| `g_set_example` | Grow-only set — elements can only be added |
| `two_p_set_example` | Two-phase set — add and remove-once semantics |
| `or_set_example` | Observed-remove set — add-wins conflict resolution |

### Maps

| Example | Description |
|---------|-------------|
| `lww_map_example` | Atomic CRDT child assignments, timestamp/writer order, and snapshot adoption |
| `or_map_example` | Observed-remove map with typed CRDT children |
| `or_map_delta_websocket_example` | Two simulated websocket peers exchanging `ORMapDelta` values instead of full state, demonstrating delta-state replication |
| `or_map_sequence_text_example` | Text and Sequence(Int) leaves, sparse updates, joining-replica edits, and fresh reset generations |
| `nested_map_example` | A sparse Text edit through two ORMap levels with delta serialization and duplicate delivery |

### Clocks

| Example | Description |
|---------|-------------|
| `version_vector_example` | Version vectors — logical clocks for causality tracking |

### Sequences and Text

| Example | Description |
|---------|-------------|
| `sequence_example` | Generic sequence CRDT — ordered list insert and merge |
| `text_example` | Plain-text CRDT — collaborative text insert and merge |

## About These Examples

Each example demonstrates:
- Creating CRDT instances on multiple replicas
- Performing type-specific mutations
- Merging replicas to show automatic convergence
- JSON serialization round-trips

These examples also serve as integration tests — they exercise the public API surface
and will fail to compile if breaking changes are introduced to the library.

## Composition rules

ORMap uses one child schema and joins concurrent edits within a generation.
Removing and re-adding a key creates a fresh generation; the newer
generation replaces older content. LWWMap chooses one whole child
assignment, so it does not merge competing Text edits.

Sparse replicas need a baseline or eventual delivery of the required
deltas. Keep outer-map pruning separate from Sequence/Text compaction.
The examples do not compact inner leaves.
