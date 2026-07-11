# Lattice CRDT Monorepo

## Project Overview

A Gleam CRDT (Conflict-free Replicated Data Types) library targeting both Erlang (BEAM) and JavaScript runtimes. Organized as a multi-package monorepo with independent versioning.

## Package Structure

The workspace is managed by [trellis](https://github.com/tylerbutler/trellis):
membership is declared once in the root `gleam.toml` (`[tools.trellis]`
table); the package list, dependency graph, and release wiring are derived
from `packages/*/gleam.toml`.

```
lattice/                               # git repo root
├── packages/
│   ├── lattice_core/                  # VersionVector, DotContext
│   ├── lattice_counters/              # GCounter, PNCounter
│   ├── lattice_sets/                  # GSet, TwoPSet, ORSet
│   ├── lattice_registers/             # LWWRegister, MVRegister
│   ├── lattice_maps/                  # LWWMap, ORMap
│   ├── lattice_sequence/              # Generic sequence CRDT
│   ├── lattice_fugue/                 # Fugue tree sequence CRDT
│   ├── lattice_text_core/             # Shared text primitives
│   ├── lattice_text/                  # Plain-text CRDT backed by sequence
│   ├── lattice_text_fugue/            # Text CRDT backed by fugue
│   ├── lattice_presence/              # Ephemeral presence
│   └── lattice_crdt/                  # Umbrella — depends on the above
├── examples/                          # Runnable examples (member, never published)
├── gleam.toml                         # Workspace root: [tools.trellis] config
├── justfile                           # Thin recipes delegating to trellis
├── .changes/                          # Changelog fragments + version sections
└── .tool-versions                     # Tool version pinning
```

### Dependency Graph

Derived, never declared — run `trellis list` (topological order),
`trellis graph` (full graph, `--format mermaid` for docs), or
`trellis info <package>` (one package's deps and dependents).

## Just Commands

Recipes are thin delegations to `trellis run <task>`, which fans out over the
workspace graph-parallel, in dependency order. Extra args pass through (e.g.
`just test lattice_core`).

```bash
just deps              # Download dependencies for all packages
just build             # Build all packages
just test              # Run all tests (Erlang)
just test-js           # Run all tests (JavaScript)
just test-all          # Run all tests (both targets)
just test-pkg <name>   # Test a single package
just format            # Format code
just format-check      # Check formatting
just check             # Type check all packages
just lint              # Lint all packages + examples (glinter)
just lint-pkg <name>   # Lint a single package
just docs              # Build documentation
just doctor            # Validate workspace invariants
just ci                # Run all CI checks (doctor, format, check, lint, test, build)
just pr                # Alias for ci (use before PR)
just main              # Extended checks for main branch
just clean             # Remove build artifacts
just change --package <name> --kind <kind> --body "<text>"   # Changelog entry
just change-pkg <name> --kind <kind> --body "<text>"         # Same, package first
just changelog-preview # Preview pending version bumps
```

## Architecture

### Error Handling

Use Result types for all fallible operations.

### Pattern Matching

Gleam enforces exhaustive pattern matching. Always handle all cases.

## Dependencies

### Runtime
- `gleam_stdlib` - Standard library
- `gleam_json` - JSON serialization

### Development
- `startest` - Testing framework

## Testing

Tests use `startest` framework with `startest/expect`.

```bash
just test              # All packages, Erlang
just test-js           # All packages, JavaScript
just test-pkg <name>   # Single package
```

## Tool Versions

Managed via `.tool-versions` (source of truth for CI):
- Erlang 27.2.1
- Gleam 1.16.0
- just 1.38.0

trellis is pinned in `.mise.toml` (locally) and in
`.github/actions/setup/action.yml` (CI).

## CI/CD

### Workflows
- **ci.yml**: `trellis doctor` + `trellis run format --check / check / lint / test / build --strict / docs` (Erlang + JavaScript targets)
- **pr.yml**: PR title validation (commitlint) + changelog fragment check (`trellis changelog check`, sticky PR comment, non-blocking)
- **release.yml**: `trellis release pr` — batches unreleased fragments into per-package version bumps on the `release/pending` branch and opens/updates the release PR
- **release-publish.yml**: On release-PR merge (or manual dispatch): `trellis publish --all-untagged` → `trellis tag create --push --github-release` → per-package lockfile refresh + follow-up PR

### Release Flow (tags-after-publish)

```
Developer adds changelog fragment → merge to main → trellis release pr
→ single release PR with per-package version bumps → merge PR
→ trellis publishes all unpublished versions to Hex.pm in dependency order
→ per-package tags (e.g., lattice_core-v1.1.0) + GitHub Releases created
→ lockfile update PR created automatically
```

Publishing is idempotent — already-published versions are skipped — so a
partially failed release is retried by re-dispatching the Publish workflow.

### Workspace Configuration

The `[tools.trellis]` table in the root `gleam.toml` is the single source of
configured truth: member globs, `ignore-release` (examples), custom tasks
(lint), publish and changelog settings. Everything derivable — package lists,
dependency order, path-dep rewrite maps, tag mappings — is computed by
trellis from the member manifests, and `trellis doctor` verifies the
invariants in CI.

## Conventions

- Use Result types over exceptions
- Exhaustive pattern matching
- Follow `gleam format` output
- Keep public API minimal
- Document public functions with `///` comments

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(parser): add support for nested objects
fix(validation): handle empty strings correctly
docs: update installation instructions
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

See `.commitlintrc.json` for configuration.

## Additional Documentation

- **DEV.md**: Detailed development workflows and guidelines
- **examples/**: Runnable examples demonstrating library usage
