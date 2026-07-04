# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0 - 2026-05-16


### Breaking

#### Initial release: pure distributed presence CRDT

Provides `lattice_presence/presence_state` with topic/key/pid/meta tracking,
opaque CRDT state, add-wins observed-remove semantics, replica up/down
visibility, pure `merge`, `merge_with_diff` for Phoenix-style join/leave
diffs, and `lattice_presence/state_json` for validated cross-node
serialization. Implementation and acceptance test suite ported from Beryl's
custom presence CRDT (#62).


