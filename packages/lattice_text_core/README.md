# lattice_text_core

Backend-agnostic grapheme and range helpers shared by lattice text CRDTs.

A text CRDT is a sequence CRDT of single-grapheme values plus a thin layer of
grapheme/range bookkeeping: splitting inserted strings into graphemes,
validating `[start, end)` ranges, slicing substrings, and folding
multi-grapheme inserts and deletes into a single mergeable delta. That layer is
identical regardless of which sequence CRDT stores the graphemes, so it lives
here and is shared by [`lattice_text`](../lattice_text) (backed by
`lattice_sequence`) and [`lattice_text_fugue`](../lattice_text_fugue) (backed by
`lattice_fugue`).

This is an internal building block; most users want `lattice_text` or
`lattice_text_fugue` directly.

## Installation

```sh
gleam add lattice_text_core
```

## What it provides

- `RangeError` / `validate_range` — validate `0 <= start <= end <= length`.
- `value` — concatenate a grapheme list into a string.
- `slice` — extract the substring for a grapheme range.
- `insert_graphemes` / `delete_graphemes` — generic multi-grapheme fold
  helpers, parameterized over a backend's `insert`, `delete`, and `merge`
  functions, that thread a single merged delta across the whole edit.

## License

MIT
