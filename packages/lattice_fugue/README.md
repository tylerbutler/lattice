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
- Traversal uses an explicit work stack and builds a temporary child index once
  per walk. Deep sequential documents do not consume the JavaScript call stack.
  The index is not cached; repeated single-item edits still rebuild it.

## API migration

Use the plain Result-returning edit and anchor functions in place of the old
fallible names. State-only edits map the successful delta result to the updated
state; invalid input no longer causes a panic.

Both `merge(a, b, local_replica)` and its safe alias
`merge_as(a, b, local_replica)` require the identity for subsequent local edits.
The result has that identity in either operand order, for full states and
deltas. Give each independent writer a distinct identity.

Decoded snapshots retain their serialized identity. Merge a remote snapshot
with your local identity before editing it.

## JSON migration

`to_json` emits Fugue **v2** for snapshots and deltas. Each node has a required
`deleted` boolean: `false` passes `value` to the application's decoder, including
JSON null; `true` marks a tombstone and requires `value` to be null.

`from_json` accepts both v1 and v2. In v1, a null `value` still means a tombstone,
even if the application's decoder accepts null. Live null values already lost
through v1 serialization cannot be recovered. Decode a v1 snapshot and encode it
again to migrate to v2.

Upgrade readers before sending v2 snapshots or deltas. Old v1-only readers need
not accept v2. Public function signatures and the v1 anchor format are unchanged.

`from_json` raises the allocation counter to cover retained node IDs and
referenced parent IDs, including tombstones and other replicas, so later
edits do not reuse those IDs. It rejects duplicate IDs and parent cycles.
Sparse deltas may omit parents; merge the missing ancestors to attach them.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_fugue>
- Hex package: <https://hex.pm/packages/lattice_fugue>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
