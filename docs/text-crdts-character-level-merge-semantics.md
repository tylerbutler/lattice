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

## References

- Yjs internals: <https://github.com/yjs/yjs>
- Automerge text and rich text: <https://automerge.org/>
- Peritext paper: <https://www.inkandswitch.com/peritext/>
- Fugue list CRDT: <https://mattweidner.com/2023/09/26/crdt-survey-2.html>
