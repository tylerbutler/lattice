# Plan: Richer Text CRDT Operations

> Status: implemented (2026-07-04). A latent `lattice_sequence` ordering bug
> surfaced by the `replace_range` delta tests was fixed alongside: local
> inserts now normalize item order via `order_items`, matching merge/move/JSON
> decoding.
> Scope: expand `packages/lattice_text` grapheme-based operations.

## Problem

`packages/lattice_text/src/lattice_text/text.gleam` (~200 lines) is a thin,
grapheme-level wrapper over `lattice_sequence`. It currently exposes only
`new`, `insert`, `delete`, their `try_*` / `*_with_delta` variants, `values`,
`value`, `merge`, and JSON round-trip. It lacks common text conveniences and
does not surface several operations the underlying sequence already supports.

## Goal

Add **richer text operations**, all grapheme-based (consistent with existing
`insert`/`delete`). Every new *mutating* operation gets the full family:
plain (assert-on-error), `try_*` (returns `Result`), and `*_with_delta` /
`try_*_with_delta` variants — matching the established module pattern.

## Scope — operations to add

### Query helpers (no delta)
- `length(text) -> Int` — grapheme count (delegates to `sequence.length`).
- `substring(text, start, end) -> String` — grapheme slice `[start, end)`,
  clamped to bounds; add `try_substring` returning `Result` for out-of-range.
  (Decide clamp vs. error during impl; default: `try_substring` errors,
  `substring` clamps.)

### Mutating ops (full plain / try / with_delta / try_with_delta family)
- `delete_range(text, start, end)` — delete graphemes in `[start, end)`.
  Implemented by repeatedly deleting at `start` (`end - start` times), since
  each delete shifts subsequent indices left. Accumulate per-delete deltas via
  `sequence.merge`, mirroring `insert_graphemes_with_delta`.
- `replace_range(text, start, end, value)` — delete `[start, end)` then insert
  `value` at `start`. Delta = merge of delete-range delta and insert delta.
- `move(text, from_index, to_index)` — surface the existing
  `sequence.move` / `try_move` / `*_with_delta` at grapheme granularity.

### Convenience
- `append(text, value)` — insert `value` at `length(text)` (thin helper over
  `try_insert`; include `try_append` + delta variants only if trivial).

## Notes / considerations
- Reuse existing private helpers (`insert_graphemes_with_delta`) and add a
  symmetric `delete_range_with_delta` private helper for delta accumulation.
- Error types: reuse `sequence.InsertError` / `sequence.DeleteError` /
  `sequence.MoveError`. Range ops validate `start <= end` and bounds; define
  whether to reuse `IndexOutOfBounds` or add a text-level range error
  (prefer reusing sequence errors to avoid new public error types).
- Empty-range and no-op cases (`start == end`, empty string) must be handled
  without producing spurious deltas (return identity delta like existing
  empty-insert path at text.gleam:160).
- Multi-grapheme correctness: keep using `string.to_graphemes` so emoji /
  combining sequences count as one unit (covered by existing tests).
- Multi-target: must compile & pass on Erlang and JavaScript.

## Testing
- Unit tests in `test/text/text_test.gleam`: range delete (incl. empty range,
  full range, out-of-bounds), replace_range (shrink/grow/equal length), move,
  substring, length, append.
- Serialization: unchanged envelope — add a round-trip test after range/replace
  edits in `test/serialization/text_json_test.gleam` if behavior warrants.
- Property tests in `test/property/text_property_test.gleam`: delta correctness
  for `delete_range`, `replace_range`, and `move` (merge(base, delta) == updated),
  reusing the existing delta-correctness pattern.
- Docs: add `///` doc comments with `## Examples` for each new public function.

## Validation
- `just format`
- `just check`
- `just test-pkg lattice_text` (Erlang) and JS target via `just test-js` (scoped
  if possible) — confirm both targets pass.
- `just lint-pkg lattice_text`

## Out of scope (this plan)
- Cursor/position anchoring (stable refs surviving concurrent edits).
- Codepoint/character-indexed API variants.
- README authoring for the package (can follow up separately).
