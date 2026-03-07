# Copilot Instructions

## Build, Test, and Lint

This is a Gleam project targeting both Erlang and JavaScript runtimes. Use `just` as the task runner:

```bash
just build           # Build (Erlang target)
just test            # Run tests (Erlang)
just test-js         # Run tests (JavaScript)
just test-all        # Run tests on both targets
just check           # Type check only
just format          # Format code (gleam format src test)
just format-check    # Check formatting without modifying
just ci              # Full CI: format-check, check, test-all, build-strict-all
just pr              # Alias for ci — run before opening a PR
```

Run a single test by name:

```bash
gleam test -- --filter "test_name"
```

Tool versions are pinned in `.tool-versions` (Erlang 27.2.1, Gleam 1.14.0).

## Architecture

**lattice_crdt** is a CRDT (Conflict-free Replicated Data Types) library. Each CRDT type lives in its own module under `src/lattice/`:

- **Counters**: `g_counter` (grow-only), `pn_counter` (positive-negative, composed of two `GCounter`s)
- **Registers**: `lww_register` (last-writer-wins), `mv_register` (multi-value)
- **Sets**: `g_set` (grow-only), `two_p_set` (two-phase), `or_set` (observed-remove, uses `dot_context` for causal tracking)
- **Maps**: `lww_map` (timestamp-based), `or_map` (observed-remove, keys tracked via `ORSet`)
- **Supporting**: `version_vector` (logical clocks), `dot_context` (causal context for OR-types)

### The `crdt` dispatch module

`src/lattice/crdt.gleam` defines a `Crdt` tagged union over all leaf CRDT types (counters, registers, sets, version vectors). This enables `ORMap` to hold heterogeneous CRDT values and merge them uniformly. Maps (`LWWMap`, `ORMap`) are **not** included in the union to avoid circular module dependencies. Parameterized types in the union are fixed to `String` for v1.

`CrdtSpec` is a companion enum used by `ORMap` to auto-create default values for new keys.

### Every CRDT module follows the same API pattern

Each module exposes: `new`, type-specific mutators, `merge`, `value` (query), `to_json`/`from_json`. JSON includes a `"type"` discriminator field for deserialization dispatch.

## Testing

Tests use the `startest` framework with `startest/expect` (not `gleeunit/should` despite what some docs say). Test files mirror the source structure under `test/`:

- `test/counter/`, `test/register/`, `test/set/`, `test/map/`, `test/clock/` — unit tests
- `test/serialization/` — JSON round-trip tests
- `test/property/` — property-based tests using `qcheck` verifying CRDT laws (commutativity, associativity, idempotency of merge)

Test functions must end with `_test` to be discovered. Property tests use a `small_test_config()` helper with a fixed seed for reproducibility.

## Conventions

- **Commit messages**: Conventional Commits (`feat`, `fix`, `docs`, etc.). Subject must be lowercase, max 72 chars. See `.commitlintrc.json`.
- **Error handling**: Use `Result` types for all fallible operations.
- **Documentation**: Document public functions with `///` doc comments including `## Examples` sections.
- **Formatting**: Always run `gleam format src test` (or `just format`). CI enforces this.
- **Multi-target**: Code must compile and pass tests on both Erlang and JavaScript targets. CI tests both.
