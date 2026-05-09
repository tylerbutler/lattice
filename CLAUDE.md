# Lattice CRDT Monorepo

## Project Overview

A Gleam CRDT (Conflict-free Replicated Data Types) library targeting both Erlang (BEAM) and JavaScript runtimes. Organized as a multi-package monorepo with independent versioning.

## Package Structure

```
lattice/                               # git repo root (NOT a Gleam package)
├── packages/
│   ├── lattice_core/                  # VersionVector, DotContext
│   ├── lattice_counters/              # GCounter, PNCounter
│   ├── lattice_sets/                  # GSet, TwoPSet, ORSet
│   ├── lattice_registers/             # LWWRegister, MVRegister
│   ├── lattice_maps/                  # LWWMap, ORMap
│   └── lattice_crdt/                  # Umbrella — depends on all above
├── examples/                          # Runnable examples
├── workspace.toml                     # Gleam workspace definition (source of truth)
├── justfile                           # Orchestrates across all packages
├── .changie.yaml                      # Project-mode changelog config
└── .tool-versions                     # Tool version pinning
```

### Dependency Graph

```
lattice_core          (no lattice deps)
lattice_counters      (no lattice deps)
lattice_sets          (no lattice deps)
lattice_registers  →  lattice_core
lattice_maps       →  lattice_core, lattice_counters, lattice_registers, lattice_sets
lattice_crdt       →  all of the above (umbrella)
```

## Just Commands

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
just docs              # Build documentation
just ci                # Run all CI checks (format, check, test, build)
just pr                # Alias for ci (use before PR)
just main              # Extended checks for main branch
just clean             # Remove build artifacts
just change            # Create changelog entry (interactive project selection)
just change-pkg <name> # Create changelog entry for a specific package
just changelog-preview <name>  # Preview unreleased changes for a package
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

## CI/CD

### Workflows
- **ci.yml**: Per-package matrix checks via `gleam-workspace-ci.yml` reusable workflow + JavaScript target tests
- **pr.yml**: PR title validation (commitlint) + changelog entry check (changie-check with workspace projects)
- **release.yml**: Changie-based release PR automation — reads `workspace.toml` via `read-gleam-workspace`
- **auto-tag.yml**: Creates per-package tags (e.g., `lattice_core-v1.1.0`) and GitHub Releases on release PR merge
- **publish.yml**: Publishes to Hex.pm on per-package tags with path→version dependency rewriting, then creates lockfile update PR

### Release Flow

```
Developer adds changelog → merge to main → changie-release batches
→ single release PR with per-package version bumps → merge PR
→ auto-tag creates per-package tags → publish.yml publishes each to Hex.pm
→ lockfile update PR created automatically
```

### Workspace Configuration

`workspace.toml` is the single source of truth for package membership. All workflows read it via the `read-gleam-workspace` action to derive project lists, package paths, and version-file mappings dynamically.

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
