---
title: What is lattice?
description: An introduction to lattice and CRDTs.
---

`lattice` is a Gleam CRDT library for building replicated state that converges
after merging, even when replicas update independently.

## What you get

The library includes:

- counters: `GCounter`, `PNCounter`
- registers: `LWWRegister`, `MVRegister`
- sets: `GSet`, `TwoPSet`, `ORSet`
- maps: `LWWMap`, `ORMap`
- supporting structures such as `VersionVector` and `DotContext`

Each CRDT module follows the same basic shape:

- `new` to create an empty or initial value
- mutators such as `increment`, `set`, `add`, or `remove`
- `merge` to combine state from replicas
- `value` to read the user-facing value
- `to_json` / `from_json` for serialization

## Choosing the right CRDT

- Use **counters** for totals that must converge across replicas.
- Use **registers** for single values, with either last-writer-wins or
  multi-value conflict handling.
- Use **sets** for membership tracking.
- Use **maps** when each key needs its own convergent value.

If you are new to the library, start with the [Quick Start](/quick-start/).
