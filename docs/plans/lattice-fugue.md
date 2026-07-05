# Plan: `lattice_fugue` — Non-Interleaving Sequence CRDT

> Status: draft (2026-07-05)
> Scope: new package `packages/lattice_fugue`, depending only on
> `lattice_core`. No changes to `lattice_sequence` or `lattice_text`.
> Assumes: implements plain **Fugue** (not FugueMax) — the algorithm from
> Weidner & Kleppmann, "The Art of the Fugue: Minimizing Interleaving in
> Collaborative Text Editing" (arXiv:2305.00583, PODC 2023). Fugue guarantees
> forward non-interleaving always and backward non-interleaving except in
> rare situations where the paper proves interleaving is unavoidable for
> *any* algorithm; FugueMax closes that remaining gap at the cost of a
> reverse-sorted right-sibling order and extra per-node metadata. This plan
> takes plain Fugue for its simplicity, matching this repo's preference for
> minimal public surface.
> Related: `docs/text-crdts-character-level-merge-semantics.md` (already
> flags the interleaving gap in `lattice_sequence` and cites Fugue as future
> direction). `docs/plans/sequence-compaction.md` and
> `docs/plans/text-crdt-cursor-anchoring.md` — analogous features
> (compaction, anchors) that this plan deliberately does not port; see Out
> of scope.
> Sources: see References at the end of this document. All algorithm
> details (Algorithm 1 pseudocode, Figures 1–8, Theorem 1, Definitions
> 2/4/6, §5.1–5.5) are cited from the paper itself, read directly from the
> arXiv PDF rather than secondary summaries.

## Problem

`lattice_sequence` orders concurrent inserts at the same position by
comparing item IDs (`sequence.gleam` origin-based integration, documented in
`docs/text-crdts-character-level-merge-semantics.md`: "Concurrent inserts at
the same position use deterministic item ID ordering"). This is the classic
YATA/RGA approach, and it is exactly the family of algorithms the Fugue
paper shows is prone to **interleaving**: when two users concurrently type
at the same position (e.g. two lines prepended to a shared list while
offline), the merged result can intersperse their characters/items
character-by-character or block-by-block, in an order that reflects
arbitrary ID comparison rather than either user's intent. This is a
correctness-adjacent property gap, not a convergence bug — the merge still
converges, but the converged result can be surprising or unreadable.

Fugue eliminates this by choosing, at insertion time, a parent/side in a
tree structure such that concurrent runs of insertions end up as separate
subtrees. A depth-first traversal of the tree then keeps each run
contiguous instead of interleaving it with a concurrent run.

## Goal

Ship a new, independently-versioned package, `lattice_fugue`, implementing
plain Fugue as a **state-based** sequence CRDT with the same external shape
as other lattice packages (`new`, `insert`/`try_insert_with_delta`,
`delete`/`try_delete_with_delta`, `values`, `length`, `merge`, `to_json`/
`from_json`). Scope is strictly the core algorithm (Algorithm 1 in the
paper): ordered insert/delete with non-interleaving guarantees. No moves, no
compaction, no anchors — see Out of scope.

This is a new package, not a replacement for `lattice_sequence`. The two
can coexist; whether `lattice_text` eventually adopts `lattice_fugue` as an
alternate or default backend is a decision for a later plan once this one
ships and is exercised.

## Design

### Data model

The paper's tree (Algorithm 1, types on p.5) is a set of node triples
`(node, leftChildren, rightChildren)` maintained incrementally by an
operation-based CRDT under causal broadcast. This plan reshapes that as a
**state-based** CRDT: store only the immutable structural facts per node in
a flat dict, and derive sibling order and traversal order from that set on
demand. This is possible because — unlike YATA's origins, which get
reinterpreted differently depending on what else is present — a Fugue
node's `parent` and `side` are decided once at creation and never
recomputed; only its `value` can change (tombstoning). That makes the tree
a pure function of the node set, and merge a plain union:

```gleam
pub opaque type NodeId {
  NodeId(replica_id: ReplicaId, counter: Int)
}

pub type Side {
  Left
  Right
}

type Node(a) {
  Node(
    id: NodeId,
    value: Option(a),           // None = tombstone
    parent: Option(NodeId),     // None = virtual root
    side: Side,
  )
}

pub opaque type Sequence(a) {
  Sequence(
    replica_id: ReplicaId,
    counter: Int,
    nodes: Dict(NodeId, Node(a)),
  )
}
```

`parent: None` represents the paper's virtual `root`; `side` is only
meaningful relative to that parent and has no special case for root itself
(root can gain right children exactly like any other node — see below).

### Traversal (`values`, and internal use)

Depth-first in-order walk, exactly Algorithm 1 lines 12–20: for a given
parent, recurse into its **left** children (sorted ascending by `NodeId`),
then each of those parents' own value if present, then recurse into
**right** children (same sort). Concretely:

```gleam
fn children(nodes: Dict(NodeId, Node(a)), parent: Option(NodeId), side: Side)
  -> List(NodeId)
// filter nodes by (parent, side), sort ascending by (counter, replica_id) —
// paper: "the exact construction of IDs and their order is not important",
// only that it is total and deterministic.

fn full_order(nodes: Dict(NodeId, Node(a))) -> List(NodeId)
// DFS from parent=None, per node: left children (recursively), self, right
// children (recursively). Includes tombstoned node ids.

pub fn values(seq: Sequence(a)) -> List(a)
// full_order, filter to nodes whose value is Some(_), unwrap.
```

`full_order` (tombstones included) is also what `insert` needs to find a
right-origin successor — see below. This mirrors the paper's distinction
between `values()` (visible only) and "the list including tombstones"
(§5.1, used to define right origin).

### Insert

Directly Algorithm 1 lines 21–28, restated for the state-based shape:

```gleam
pub fn try_insert_with_delta(seq: Sequence(a), index: Int, value: a)
  -> Result(#(Sequence(a), Sequence(a)), InsertError) {
  // 1. bounds check index against visible length, as lattice_sequence does
  // 2. id = NodeId(seq.replica_id, seq.counter + 1)
  // 3. left_origin = visible node at (index - 1), or None (root) if index == 0
  // 4. case has_right_children(seq.nodes, left_origin) {
  //      False -> Node(id, Some(value), parent: left_origin, side: Right)
  //      True -> {
  //        // left_origin has right children, so per Theorem 1's proof its
  //        // right-origin exists, is a descendant of left_origin, and has
  //        // no left children — always safe to attach here.
  //        let right_origin = successor_in_full_order(seq.nodes, left_origin)
  //        Node(id, Some(value), parent: Some(right_origin), side: Left)
  //      }
  //    }
  // 5. insert node into seq.nodes; bump counter
  // 6. delta = Sequence with only this one node (like lattice_sequence's
  //    delta_sequence helper) — a Fugue delta is always exactly one node,
  //    since parent/side never change after creation.
}
```

`has_right_children` and `successor_in_full_order` are both simple queries
over `full_order`/`children`. Figure 4 in the paper is the worked example
to test against directly: inserting `g` between `a` and `b` (a has no right
children → g becomes a's right child); then inserting `h` between `a` and
`g` (a now has a right child → h becomes g's left child).

### Delete

Algorithm 1 lines 39–44: tombstone by setting `value` to `None`. The
node's `id`/`parent`/`side` are never removed — deleted nodes may be
ancestors of live (including concurrently-inserted) nodes, exactly as the
paper notes ("We cannot remove a deleted element's node entirely"). This
plan does not attempt tombstone GC; see Out of scope /
`docs/plans/sequence-compaction.md` for how `lattice_sequence` treats the
analogous problem, as a reference for a possible future `lattice_fugue`
compaction plan.

Delete mints a counter bump (an `OpId`-shaped dot) for parity with
`lattice_sequence`'s delete-dot convention, even though this plan has no
frontier/compaction consumer yet — cheap now, and avoids a breaking change
if compaction follows the same path later.

### Merge

Because a node's `parent`/`side` are creation-time invariants and never
recomputed, `merge` is a plain dict union keyed by `NodeId`:

- Node present on one side only → keep as is.
- Node present on both sides → `parent`/`side` are identical by invariant
  (assert this in debug/property tests, never at runtime — trusting
  internal invariants per repo convention); `value` joins as "tombstone
  wins": `None` if either side is `None`, else the (necessarily equal)
  `Some(value)`.

No re-integration pass, no Lamport-order replay, no rebuild step — this is
the main simplification relative to `lattice_sequence`'s `rebuild`/
`rebuild_base`. Convergence follows directly from Theorem 1 in the paper
(Fugue satisfies the strong list specification): our state-based merge is
equivalent to delivering every node's causal-broadcast insert exactly once,
in any order, because delivery order in the paper's algorithm never affects
a node's own parent/side and sibling order is a pure function (sort by ID)
of the final set. Both are the properties Theorem 1's proof already relies
on, so no new correctness argument is needed beyond restating this
equivalence — but it should still be property-tested directly (see
Testing).

### JSON envelope

Mirror `lattice_sequence`'s envelope shape (`type`, `v`, `state`):

```gleam
pub fn to_json(seq: Sequence(a), encode_value: fn(a) -> json.Json) -> json.Json
pub fn from_json(json_string: String, value_decoder: decode.Decoder(a))
  -> Result(Sequence(a), json.DecodeError)
```

`state` = `self_id`, `counter`, and a flat array of nodes: `id`, `value`
(nullable), `parent` (nullable), `side`. No forwarding map, no frontier —
neither concept exists in this plan's scope.

### Public API surface

```gleam
pub opaque type Sequence(a)

pub type InsertError { IndexOutOfBounds(index: Int, length: Int) }
pub type DeleteError { DeleteIndexOutOfBounds(index: Int, length: Int) }

pub fn new(replica_id: ReplicaId) -> Sequence(a)

pub fn insert(seq: Sequence(a), index: Int, value: a) -> Sequence(a)
pub fn insert_with_delta(seq, index, value) -> #(Sequence(a), Sequence(a))
pub fn try_insert_with_delta(seq, index, value)
  -> Result(#(Sequence(a), Sequence(a)), InsertError)

pub fn delete(seq: Sequence(a), index: Int) -> Sequence(a)
pub fn delete_with_delta(seq, index) -> #(Sequence(a), Sequence(a))
pub fn try_delete_with_delta(seq, index)
  -> Result(#(Sequence(a), Sequence(a)), DeleteError)

pub fn values(seq: Sequence(a)) -> List(a)
pub fn length(seq: Sequence(a)) -> Int
pub fn merge(a: Sequence(a), b: Sequence(a)) -> Sequence(a)

pub fn to_json(seq, encode_value) -> json.Json
pub fn from_json(json_string, value_decoder)
  -> Result(Sequence(a), json.DecodeError)
```

`NodeId` and `Side` stay unexported (or exported opaque with no
constructors) — nothing in this plan's scope needs to expose node identity
outside the package, unlike `lattice_sequence`'s `ItemId`, which anchors
depend on. If a future anchoring plan for `lattice_fugue` needs stable
identity, it can open that up the same way `lattice_sequence` did.

## Notes / considerations

- **Package layout**: `packages/lattice_fugue/{gleam.toml,src/lattice_fugue/sequence.gleam,test/...}`,
  modeled directly on `packages/lattice_sequence`. `gleam.toml` deps:
  `gleam_stdlib`, `gleam_json`, `lattice_core` (path dep) — no more than
  that; dev-deps `startest`, `qcheck`, `glinter`, matching every other
  package.
- **Workspace wiring**: `workspace.toml` membership is the wildcard
  `packages/lattice_*`, so no change needed there. CI/release workflows
  read package lists dynamically via `read-gleam-workspace`, so a new
  package directory with a `gleam.toml` is picked up automatically.
- **Changie registration**: add a `lattice_fugue` project entry to
  `.changie.yaml` (label, key, changelog path, gleam.toml version
  replacement — copy the `lattice_core`/`lattice_sequence` entry shape) and
  create `.changes/lattice_fugue/.gitkeep` (the empty archive dir every
  other project has for its released version files, e.g.
  `.changes/lattice_core/v1.0.0.md`). Pending fragments themselves are
  files in `.changes/unreleased/`, named `lattice_fugue-<Kind>-<slug>.yaml`
  (see Validation).
- **Non-interleaving is the entire value proposition** — property-test it
  explicitly (see Testing), not just convergence. Convergence alone is
  satisfied by `lattice_sequence` today; the reason this package exists is
  the ordering guarantee.
- **Sibling sort key is an arbitrary but deterministic choice.** The paper
  is explicit that same-side sibling order (by ID) doesn't affect
  correctness, only determinism. Use `(counter, replica_id)` to match
  `lattice_sequence`'s existing `compare_lamport` convention.
- **No moves, no compaction, no anchors** (see Out of scope) — this keeps
  the implementation a close, verifiable match to Algorithm 1 as published,
  and keeps the state-based-merge argument in Design clean. All three are
  natural, separate follow-up plans once this core ships; each has a
  `lattice_sequence` analog to crib from (`docs/plans/sequence-compaction.md`,
  `docs/plans/text-crdt-cursor-anchoring.md`), though the tree shape means
  none of them will be a direct port — e.g. compaction here means dropping
  *leaf* tombstones only (an ancestor tombstone can't be dropped without
  breaking descendants' parent pointers), which is a different shape of
  problem than `lattice_sequence`'s block-merging.
- **Performance is unoptimized by design for v1**, matching this repo's
  general pattern of shipping correctness first (`lattice_sequence`'s own
  `rebuild` was O(n) before compaction; see
  `docs/plans/sequence-compaction.md`). `values()`/`full_order` walk the
  whole node dict; `insert` does one such walk to find right-origin
  successors. Note this rather than optimize it — a follow-up can
  introduce cached order or the paper's own §6 "string implementation"
  (path-as-string positions) if profiling shows it's warranted.
- **Not FugueMax.** If a future need arises for the maximal guarantee
  (right-side siblings sorted by reverse right-origin instead of ID, right
  children additionally tagged with their right-origin — Definition 6 /
  §5.3 in the paper), it's a small, additive change to this same package
  (same tree shape, different sibling comparator) rather than a rewrite —
  worth noting here so it isn't accidentally over-scoped into this plan.

## Testing

- **Unit**: Figure 3/4 worked examples from the paper directly (insert `g`
  between `a`,`b` where `a` has no right children → right child of `a`;
  insert `h` between `a`,`g` where `a` now has a right child → left child
  of `g`); insert at index 0 repeatedly (root right-child then left-chain,
  per the "prepend" scenario in Figure 2); delete then re-query `values`;
  delete of an item with live descendants (tombstone retained, descendants
  unaffected); bounds errors for both insert and delete.
- **Interleaving regression tests** — port the paper's own examples
  directly, since they are the actual spec for this package:
  - Figure 1 (forward interleaving): two replicas each append a line +
    word to a shared line; result must **not** interleave characters
    (`"ebgrgesad"` is the wrong answer this package must avoid).
  - Figure 2 (backward interleaving): two replicas each prepend items then
    a category header while offline; result must keep each replica's
    insertions contiguous.
  - Figure 6/7 (the forced-interleaving edge case): three replicas
    concurrently insert into an empty list, then two of them concurrently
    insert between the same pair — confirm the result matches the paper's
    plain-Fugue answer (`AXYBC` per Fig. 7, where Fugue may pick either of
    the two valid same-ID-window orderings, unlike FugueMax which is
    forced to a unique one) rather than crashing or converging to
    something structurally invalid.
- **Property tests** (`test/property/`, mirroring `lattice_sequence`'s
  suite): (1) `merge` is commutative, associative, idempotent — the FR-1
  contract every lattice type must satisfy; (2) convergence: any two
  replicas that have received the same op set converge to the same
  `values()`, regardless of delivery order or merge tree shape; (3)
  non-interleaving: for two disjoint runs of insertions performed
  concurrently at the same position (simulating two offline sessions),
  every element of run A is either entirely before or entirely after every
  element of run B in the merged result (this is the forward
  non-interleaving property, Definition 2 — the property that YATA-style
  `lattice_sequence` cannot guarantee); (4) round-trip: `from_json(to_json(s)) == s`
  for random edit histories.
- **Multi-target**: must compile and pass on Erlang and JavaScript
  (`just test-pkg lattice_fugue` and the JS target equivalent).

## Validation

- `just format`, `just check`
- `just test-pkg lattice_fugue` (Erlang) and `just test-js` (confirm target
  parity)
- `just lint-pkg lattice_fugue`
- **Version resolved**: `gleam.toml` starts at `version = "0.0.1"`, not
  `1.0.0`. Confirmed from history: both `lattice_sequence` and
  `lattice_text` were first merged at `1.0.0` (#59) and then corrected
  (`44a28b2`, "Neither package has been published to Hex; 1.0.0 wrongly
  implied a released stable API") — `0.0.1` is this repo's actual
  convention for an unpublished package, not a one-off. `lattice_fugue`
  should skip that detour and scaffold straight at `0.0.1`.
- Changie fragment for this plan's work: kind `Added`, `project:
  lattice_fugue`, one fragment per landed increment — mirroring
  `.changes/unreleased/lattice_sequence-Added-generic-sequence-crdt.yaml`
  ("Add generic sequence CRDT package" body). **No `MajorRelease`/
  `Breaking` "stabilize 1.0" fragment in this plan** — both existing
  packages only got that fragment much later, once their API had matured
  on a dedicated stabilization branch (`.changes/unreleased/lattice_sequence-MajorRelease-stabilize-1-0.yaml`,
  landing in the same commits that produced the `chore/prep-1.0-sequence-text`
  branch this plan was written from). Cutting `lattice_fugue`'s own 1.0 is
  a separate, later decision.

## Suggested sequencing

1. Package scaffold: `gleam.toml` at `version = "0.0.1"`, empty module,
   `.changie.yaml` project entry, empty `CHANGELOG.md` (Keep-a-Changelog
   header only, matching `lattice_sequence/CHANGELOG.md`) — confirm `just
   test-pkg lattice_fugue` runs (even with zero tests) before writing
   algorithm code.
2. Data model + traversal (`children`, `full_order`, `values`, `length`) —
   testable in isolation by hand-constructing node dicts before `insert`
   exists.
3. `insert`/`try_insert_with_delta`, verified against Figure 3/4's worked
   examples.
4. `delete`/`try_delete_with_delta`.
5. `merge`, verified against Figure 1/2/6/7 scenarios and the property
   suite (commutative/associative/idempotent + non-interleaving).
6. JSON serialization.
7. Docs: package README (matching the other packages' READMEs added in
   #71), and an update to
   `docs/text-crdts-character-level-merge-semantics.md` noting
   `lattice_fugue` now exists as the non-interleaving alternative, with a
   pointer for a future plan deciding `lattice_text`'s relationship to it.

## Out of scope (this plan)

- **FugueMax.** Deferred; noted above as a small follow-up if ever needed.
- **Move operations.** No equivalent in the paper; a `lattice_fugue` move
  would need its own design (e.g. re-parenting a subtree, or tombstone +
  re-insert with identity preserved some other way) — separate plan.
- **Compaction / tombstone GC.** The tree-ancestor constraint (can't drop a
  tombstone that's an ancestor of a live node) makes this a different
  problem shape than `lattice_sequence`'s block-merging compaction —
  separate plan, after this core ships and has real usage data.
- **Cursor/position anchoring.** No stable public node identity is exposed
  in this plan; a follow-up mirroring
  `docs/plans/text-crdt-cursor-anchoring.md` can open `NodeId` up the same
  way `lattice_sequence` opened `ItemId`.
- **`lattice_text` integration.** Whether text adopts this as a backend
  (replacing, complementing, or offering as an alternative to
  `lattice_sequence`) is a decision for a later plan once `lattice_fugue`
  exists and has been exercised on its own.
- **Performance optimization** (cached traversal order, path-string
  positions per the paper's §6, tree balancing) — correctness first, per
  repo convention; revisit if profiling on real workloads warrants it.

## References

- Matthew Weidner and Martin Kleppmann, ["The Art of the Fugue: Minimizing
  Interleaving in Collaborative Text Editing"](https://arxiv.org/abs/2305.00583)
  (arXiv:2305.00583). **Primary source for this plan.** Algorithm 1
  (pseudocode for insert/delete/traversal), Table 1 (interleaving
  susceptibility survey), Figures 1–8 (interleaving examples and worked
  tree constructions), Theorem 1 (Fugue satisfies the strong list
  specification), Definitions 2/4/6 and §5.1–5.5 (forward/backward/maximal
  non-interleaving, FugueMax) are all cited directly from the PDF
  (arxiv.org/pdf/2305.00583), read in full for this plan rather than
  summarized secondhand.
- Matthew Weidner, ["Fugue: A Basic List
  CRDT"](https://mattweidner.com/2022/10/21/basic-list-crdt.html) (2022).
  Earlier, more informal write-up of the same tree/traversal idea
  (`createBetween`, left/right children, in-order traversal) — used here
  only as background/cross-check, not as a source of algorithmic detail;
  the paper above is authoritative.
- [github.com/mweidner037/fugue](https://github.com/mweidner037/fugue) —
  the paper authors' reference implementation and benchmarks. Not read in
  detail for this plan; worth consulting during implementation for
  concrete Rust/TypeScript encodings of the tree, if the Gleam port of any
  step is ambiguous.
- `docs/text-crdts-character-level-merge-semantics.md` (this repo) — already
  cites Fugue as a future direction and documents `lattice_sequence`'s
  current YATA-style ordering, which is the baseline this plan contrasts
  against.
- `docs/plans/sequence-compaction.md` and
  `docs/plans/text-crdt-cursor-anchoring.md` (this repo) — prior art for
  the compaction and anchoring features this plan explicitly defers; see
  Out of scope for how the tree shape changes those designs.
  repo convention; revisit if profiling on real workloads warrants it.
