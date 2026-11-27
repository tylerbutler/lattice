# OR-set merge proofs

This directory covers part 1 of [#284](https://github.com/tylerbutler/lattice/issues/284).
The Bend2 model includes OR-set live tags, tombstones, pruning frontiers,
and allocation counters. The proofs establish commutativity, associativity,
and idempotency up to causal-state equivalence.

## Run the check

The directory-local mise configuration pins Bend 2.0.40. From the repository
root, set up the tool and run the check:

```sh
cd verification/or_set
mise trust .mise.toml
mise install
cd ../..
just verify-or-set
```

The recipe runs `mise exec -- bend PROOF.bend --verdict` from this directory.
Success prints `ALL PROOFS CHECK`. Open laws, false proofs, and kernel
failures return a nonzero status. There is no `main`, native build, or GPU
requirement. Normal Gleam builds and CI do not run this opt-in check.

## Files

| File | Purpose |
| --- | --- |
| `MODEL.bend` | Finite snapshots and pointwise merge semantics. |
| `LAWS.bend` | Universal merge and normalization claims. |
| `PROOF.bend` | Proofs, including the imported examples. |
| `EXAMPLES.bend` | Concrete pruning and delta regressions. |

## Model representation

A `Snapshot` stores finite lists of live `(element, tag)` pairs, tombstones,
and pruning clocks. A `Merged` node stores two finite states. Queries evaluate
the merge rules on demand. This represents arbitrary finite snapshots and
merge trees; it does not enumerate operation histories or materialize a
dictionary.

Replica and element identifiers are natural numbers. A finite collection of
Gleam identifiers can use distinct natural-number labels without changing
equality tests. `Tag{replica, previous}` represents counter `previous + 1`,
so tag counters are positive. Allocation and pruning clocks use natural
numbers. The model abstracts machine arithmetic.

`observe(state, element, tag)` returns three Boolean facts: whether the tag
is live for that element, whether a tombstone exists, and whether the pruning
frontier covers it. Merge uses the source rules:

1. Union the observed tombstones.
2. Keep a tag from either live set unless a tombstone removes it or either
   operand covers it while lacking that live tag.
3. Drop tombstones covered by the merged frontier.

The frontier query takes the per-replica maximum. The `frontier_coverage`
proof connects this numerical maximum to the Boolean coverage used by
`join_point`. Live pairs avoid empty dictionary entries.

The allocation calculation factors the maximum pruning clock out of a merge
tree. `counter_step` proves that it equals taking both input counters and
applying the merged pruning floor at each merge. `counter_covers_pruning`
proves that the result covers that floor. The model keeps the left writer,
outside the commutative causal state.

## Equality and proof domain

Raw state equality cannot express these merge laws: merge keeps the left
writer, collection order has no meaning, and self-merge can discard a covered
tombstone.

For each element and tag, `knowledge` records:

- `seen`: a live tag, a tombstone, or frontier coverage.
- `removed`: a tombstone, or coverage without a live tag.
- `covered`: frontier coverage.

`same(a, b)` compares this knowledge for arbitrary elements and tags, the
frontier for arbitrary replicas, and the allocation counter after applying
the pruning floor. It ignores local writer identity and list order. Lookup
uses zero for a missing clock, so an explicit zero does not change equality.

`valid` states that live tags and tombstones are disjoint at each query.
Positive tag counters and non-negative clocks follow from the model types.
The merge laws hold even for snapshots outside this pointwise validity
condition. The separate `same_preserves_live` and
`normalization_preserves_live` proofs require validity: for valid snapshots,
normalization does not hide a live tag. `normalization_retains_tombstones`
shows that normalized removal metadata keeps the tombstones above
the frontier.

`closure` proves pointwise validity of a merge. `congruence` proves that
equivalent inputs remain equivalent after further merges. The normalization
proofs therefore cover causal state, not just visible element values.

The Boolean case analysis in `point_merge_bits` covers the full per-tag
domain. The natural-number lemmas use induction, and the state claims
quantify over arbitrary finite states. No proof uses an operation bound,
sampled input, an admitted axiom, unsafe recursion, or foreign code.

## Source mapping

| Model | Gleam source |
| --- | --- |
| Snapshot live pairs and tombstones | `packages/lattice_sets/src/lattice_sets/or_set.gleam`, `ORSet` |
| `join_point` live filtering and tombstone filtering | `or_set.merge`, `is_pruned_zombie`, `pruned_on_side_without_live_tag`, `not_dominated` |
| `frontier`, `lookup` | `packages/lattice_core/src/lattice_core/version_vector.gleam`, `merge`, `get` |
| `counter`, `counter_step`, `pruning_floor` | `or_set.merge`, `counter_with_pruned_floor` |
| `EXAMPLES.bend` later removal, replay, and fresh deltas | `packages/lattice_sets/test/set/or_set_prune_test.gleam` |

The source revision used for this model is
`6e9977446f35d52a12314399a243d108f4017e4d`.
Review this mapping when changing the Gleam merge.

## Limits

The checker and BendTT kernel check the Bend model. They do not prove that
Gleam's collection iteration, compiler, or runtime implements this model.
The kernel also relies on the unproven Bend parser and translation. See the
[Bend 2.0.40 guide](https://github.com/bendlang/bend/blob/v2.0.40/guide/GUIDE.md).

The source still requires unique tag allocation, a consistent element for
each tag across replicas, sufficient allocation history, and a valid
causal-stability protocol. This model proves the merge equations and
pointwise closure, not those protocol or cross-tag invariants.

Exhaustive histories, a JSON differential oracle, mutator and serialization
proofs, and other CRDTs remain outside this work. Without the oracle or a CI
gate, contributors must check the source mapping to prevent model drift.
