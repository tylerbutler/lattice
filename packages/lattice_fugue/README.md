# lattice_fugue

Non-interleaving sequence CRDT for Gleam implementing the Fugue algorithm.

Use this package when replicas edit a shared ordered list concurrently and you need concurrent runs of insertions to stay contiguous rather than interleave. `lattice_fugue` implements plain **Fugue** (Weidner & Kleppmann, ["The Art of the Fugue"](https://arxiv.org/abs/2305.00583), PODC 2023): it chooses each insertion's place in a tree so that a depth-first traversal keeps concurrently-typed runs together. This is the ordering guarantee that YATA-style CRDTs like `lattice_sequence` do not provide — they converge, but concurrent runs can interleave character-by-character.

Both packages converge; pick `lattice_fugue` specifically for the non-interleaving guarantee, or `lattice_sequence` for its richer feature set (moves, anchors, compaction).

## Installation

```sh
gleam add lattice_fugue
```

## Quick example

```gleam
import gleam/result
import lattice_core/replica_id
import lattice_fugue/sequence

pub fn main() {
  use node_a <- result.try(
    sequence.new(replica_id.new("node-a"))
    |> sequence.insert(0, "hello")
    |> result.try(sequence.insert(_, 1, "world")),
  )

  use node_b <- result.try(
    sequence.new(replica_id.new("node-b"))
    |> sequence.insert(0, "!"),
  )

  let merged = sequence.merge(node_a, node_b, replica_id.new("node-a"))

  Ok(sequence.values(merged))
  // -> Ok(["hello", "world", "!"])
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_fugue/sequence` | Non-interleaving list CRDT with index-based insert/delete and plain-union merge. |

## Notes

- Editing operations: `insert` and `delete`.
- Query helpers: `values`, `length`, and `replica_id`.
- `insert`, `delete`, `anchor_at`, and `resolve` return `Result` with typed errors for invalid indexes or unknown anchor targets.
- Delta-state variants (`*_with_delta`) return `Result` containing the updated sequence plus a delta (always a single node) that can be merged into other replicas, avoiding full-state sync.
- `merge` is a plain union keyed by node identity — a node's parent/side are creation-time invariants, so no re-integration pass is needed and convergence is immediate.
- Deletes tombstone a node's value; the node is retained because it may be an ancestor of live nodes. There is no tombstone compaction in this version.
- `merge`, `to_json`, and `from_json` round-trip the full CRDT state; convergence and non-interleaving hold on both Erlang and JavaScript targets.

## API migration

Use the plain Result-returning edit and anchor functions in place of the old
fallible names. State-only edits map the successful delta result to the updated
state; invalid input no longer causes a panic.

Both `merge(a, b, local_replica)` and its safe alias
`merge_as(a, b, local_replica)` require the identity for subsequent local edits.
The result has that identity in either operand order, for full states and
deltas. Give each independent writer a distinct identity.

Decoded snapshots retain their serialized identity. Merge a remote snapshot
with your local identity before editing it. The Fugue v1 wire format is
unchanged.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_fugue>
- Hex package: <https://hex.pm/packages/lattice_fugue>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
