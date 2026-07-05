# Text CRDT merge semantics

`lattice_sequence` models ordered content as items with stable IDs and
YATA-style left/right origins. `lattice_text` stores each inserted text segment
as one sequence item and renders visible segments by concatenating them.

## Design notes

- Inserts are resolved by stable item identity, not mutable indexes.
- Deletes are tombstones so later operations can still resolve anchors.
- Concurrent inserts at the same position use deterministic item ID ordering.
- Forward typing stays grouped by anchoring each item to the previous item.
- Text delegates merge and serialization to `lattice_sequence`.

## Interleaving and `lattice_fugue`

The YATA-style item-ID ordering above converges, but concurrent *runs* of
insertions at the same position can interleave item-by-item in the merged
result. The `lattice_fugue` package is a separate, non-interleaving sequence
CRDT (plain Fugue — Weidner & Kleppmann, arXiv:2305.00583) that keeps each
concurrent run contiguous. It is an independent alternative today, not a
`lattice_text` backend; whether `lattice_text` should adopt it (as a default,
alternate, or complement to `lattice_sequence`) is left to a future plan once
`lattice_fugue` has been exercised.


## References

- Yjs internals: <https://github.com/yjs/yjs>
- Automerge text and rich text: <https://automerge.org/>
- Peritext paper: <https://www.inkandswitch.com/peritext/>
- Fugue list CRDT: <https://mattweidner.com/2023/09/26/crdt-survey-2.html>
- Fugue paper ("The Art of the Fugue"): <https://arxiv.org/abs/2305.00583>
- `lattice_fugue` package: `packages/lattice_fugue` (non-interleaving alternative)
