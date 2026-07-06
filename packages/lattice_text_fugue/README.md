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
import lattice_core/replica_id
import lattice_text_fugue/text

pub fn main() {
  let node_a =
    text.new(replica_id.new("node-a"))
    |> text.insert(0, "Hello world")

  let node_b =
    text.new(replica_id.new("node-b"))
    |> text.append("!")

  let merged = text.merge(node_a, node_b)

  text.value(merged)
}
```

## Non-interleaving

When two replicas concurrently insert runs at the same position, Fugue keeps
each run contiguous rather than interleaving their characters. This is the main
reason to choose this package over `lattice_text`.

## Anchors and frontier

- `start_anchor` / `end_anchor` / `anchor_at` / `try_anchor_at` create stable
  positions that survive concurrent edits and merges.
- `resolve` / `try_resolve` map an anchor back to a current index.
- `anchor_to_json` / `anchor_from_json` serialize anchors.
- `frontier` returns the causal frontier as a `VersionVector`.

Anchor JSON is not interchangeable with `lattice_text` anchors.

## Choosing a backend

| Feature          | `lattice_text` | `lattice_text_fugue` |
| ---------------- | -------------- | -------------------- |
| Non-interleaving | no             | yes                  |
| Anchors          | yes            | yes                  |
| Frontier         | yes            | yes (causal)         |
| Move             | yes            | no                   |
| Compaction       | yes            | no                   |
