---
title: What is lattice?
description: An introduction to lattice and CRDTs.
---

`lattice` is a Gleam library for **Conflict-free Replicated Data Types**
(CRDTs).

## What is a CRDT?

A CRDT is a data structure that can be replicated across multiple nodes, updated
independently on each node without coordination, and merged back together with a
guarantee: all replicas converge to the same state. No consensus protocol, no
locking, no conflict resolution callbacks — the math of the data structure
itself ensures convergence.

For example, a grow-only counter lets every replica increment locally. When two
replicas merge, they take the per-replica maximum and sum the result. No matter
what order merges happen in, the final value is always the same.

## What you get

The library is organized across [focused packages](/packages/):

- **counters** (`lattice_counters`): GCounter (Grow-only Counter), PNCounter (Positive-Negative Counter)
- **registers** (`lattice_registers`): LWWRegister (Last-Writer-Wins Register), MVRegister (Multi-Value Register)
- **sets** (`lattice_sets`): GSet (Grow-only Set), TwoPSet (Two-Phase Set), ORSet (Observed-Remove Set)
- **maps** (`lattice_maps`): LWWMap (Last-Writer-Wins Map), ORMap (Observed-Remove Map)
- **presence** (`lattice_presence`): distributed topic/key/pid presence tracking
- **causal infrastructure** (`lattice_core`): `ReplicaId`, `VersionVector`, `DotContext`

The umbrella package `lattice_crdt` depends on the core CRDT packages, so a
single `gleam add lattice_crdt` gives you counters, registers, sets, maps, and
causal infrastructure. Add `lattice_presence` separately when you need presence
tracking.

Each CRDT module follows the same basic shape:

- `new` to create an empty or initial value
- mutators such as `increment`, `set`, `add`, or `remove`
- `merge` to combine state from replicas
- `value` to read the user-facing value
- `to_json` / `from_json` for serialization

Many state-changing functions also expose `*_with_delta` companions. These
return both the new state and a compact delta that remote replicas merge with
the same CRDT semantics. See [Delta-State Replication](/advanced/delta-state/)
for details.

## Choosing the right CRDT

- Use **counters** for totals that must converge across replicas.
- Use **registers** for single values, with either last-writer-wins or
  multi-value conflict handling.
- Use **sets** for membership tracking.
- Use **maps** when each key needs its own convergent value.
- Use **presence** when you need topic/key membership with metadata and local
  replica visibility.

If you are new to the library, start with the [Quick Start](/quick-start/).
