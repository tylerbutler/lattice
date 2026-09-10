# lattice_text_fugue

Non-interleaving plain-text CRDT for Gleam, backed by `lattice_fugue`.

Use this package when replicas edit shared text concurrently and you want
concurrent insertions at the same position to stay contiguous instead of
interleaving. All operations are grapheme-based, so emoji and combining
sequences count as one unit.

This is a Fugue-backed alternative to `lattice_text` (which uses a YATA-style
sequence). It exposes the same core text API plus anchors and a causal
frontier, but intentionally omits `move` and compaction/forwarding, which have
no Fugue equivalent in this release.

## Installation

```sh
gleam add lattice_text_fugue
```

## Quick example

```gleam
import gleam/result
import lattice_core/replica_id
import lattice_text_fugue/text

pub fn main() {
  use node_a <- result.try(
    text.new(replica_id.new("node-a"))
    |> text.insert(0, "Hello world"),
  )

  use node_b <- result.try(
    text.new(replica_id.new("node-b"))
    |> text.append("!"),
  )

  let merged = text.merge(node_a, node_b, replica_id.new("node-a"))

  Ok(text.value(merged))
}
```

## Non-interleaving

When two replicas concurrently insert runs at the same position, Fugue keeps
each run contiguous rather than interleaving their characters. This is the main
reason to choose this package over `lattice_text`.

## Anchors and frontier

- `start_anchor` / `end_anchor` create boundary anchors. `anchor_at` returns a
  `Result` with a stable position that survives concurrent edits and merges.
- `resolve_anchor` returns a `Result` with the anchor's current grapheme index.
- `anchor_to_json` / `anchor_from_json` serialize anchors.
- `frontier` returns the causal frontier as a `VersionVector`.

Anchor JSON is not interchangeable with `lattice_text` anchors.

## API migration

`insert`, `delete`, `delete_range`, `replace_range`, and `append`, together
with their `*_with_delta` variants, return `Result`. Use the plain edit and
anchor names instead of the old fallible names. Errors retain their existing
types and payloads. State-only edits map a successful delta result to the
updated text; an empty edit returns a neutral delta.

`substring` still clamps indexes, while `try_substring` still validates the
range and returns `Result`.

Both `merge(a, b, local_replica)` and its safe alias
`merge_as(a, b, local_replica)` require the identity for subsequent local
edits, whether the inputs are full states or deltas. Operand order does not
change that identity. Give each independent writer a distinct identity.
Decoded snapshots retain their serialized identity: merge a remote snapshot
with your local identity before editing it. The Fugue v1 wire format is
unchanged.

## Choosing a backend

| Feature          | `lattice_text` | `lattice_text_fugue` |
| ---------------- | -------------- | -------------------- |
| Non-interleaving | no             | yes                  |
| Anchors          | yes            | yes                  |
| Frontier         | yes            | yes (causal)         |
| Move             | yes            | no                   |
| Compaction       | yes            | no                   |
