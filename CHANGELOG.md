# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.0.0 - 2026-03-06


#### Added

##### Counter types

Grow-only counters (`g_counter`) and positive-negative counters (`pn_counter`) that automatically converge across replicas.

##### Register types

Last-writer-wins registers (`lww_register`) and multi-value registers (`mv_register`) for storing single values with conflict resolution.

##### Set types

Grow-only sets (`g_set`), two-phase sets with remove-once semantics (`two_p_set`), and observed-remove sets (`or_set`) for managing collections across replicas.

##### Map types

Last-writer-wins maps (`lww_map`) and observed-remove maps (`or_map`) for key-value storage with automatic conflict resolution.

##### Causal context primitives

Version vectors (`version_vector`) and dot contexts (`dot_context`) for tracking causality between replicas.

##### JSON serialization

All CRDT types include `to_json` and `from_json` functions for persisting and transmitting state between nodes.


