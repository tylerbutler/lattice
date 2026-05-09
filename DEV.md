# Development Guide

This document provides detailed instructions for developing and contributing to this project.

## Prerequisites

Ensure you have the following installed:

| Tool | Version | Purpose |
|------|---------|---------|
| Erlang/OTP | 27.2.1+ | BEAM runtime |
| Gleam | 1.16.0+ | Compiler and tooling |
| just | 1.38.0+ | Task runner |
| changie | latest | Changelog management |

**Recommended:** Use [mise](https://mise.jdx.dev/) or [asdf](https://asdf-vm.com/) with the provided `.tool-versions` file.

```bash
# With mise
mise install

# With asdf
asdf install
```

## Getting Started

```bash
# Clone the repository
git clone <repo-url>
cd lattice

# Install dependencies for all packages
just deps

# Verify everything works
just ci
```

## Monorepo Structure

This project is a monorepo containing 6 independently-versioned Gleam packages:

```
lattice/                               # git repo root (NOT a Gleam package)
├── packages/
│   ├── lattice_core/                  # VersionVector, DotContext
│   ├── lattice_counters/              # GCounter, PNCounter
│   ├── lattice_sets/                  # GSet, TwoPSet, ORSet
│   ├── lattice_registers/             # LWWRegister, MVRegister
│   ├── lattice_maps/                  # LWWMap, ORMap, Crdt dispatch
│   └── lattice_crdt/                  # Umbrella — depends on all above
├── examples/                          # Runnable examples
├── workspace.toml                     # Gleam workspace definition (source of truth)
├── justfile                           # Orchestrates across all packages
├── .changie.yaml                      # Project-mode changelog config
└── .tool-versions                     # Tool version pinning
```

### Dependency graph

```
lattice_core          (no lattice deps)
lattice_counters      (no lattice deps)
lattice_sets          (no lattice deps)
lattice_registers  →  lattice_core
lattice_maps       →  lattice_core, lattice_counters, lattice_registers, lattice_sets
lattice_crdt       →  all of the above (umbrella)
```

Each package has its own `gleam.toml`, `src/`, and `test/` directories. Packages use **path dependencies** for local development (e.g., `lattice_core = { path = "../lattice_core" }`).

## Development Workflow

### Daily Development

```bash
# Type check all packages
just check

# Run all tests (Erlang target)
just test

# Test a single package
just test-pkg lattice_core

# Format code (do this before committing)
just format
```

### Before Committing

```bash
# Run full CI checks locally
just pr
```

### Changelog Entries

Use changie to create per-package changelog entries:

```bash
# Interactive project selection
just change

# Direct entry for a specific package
just change-pkg lattice_sets
# or directly:
changie new --project lattice_sets

# Preview unreleased changes for a package
just changelog-preview lattice_sets
```

## Code Style

### Formatting

This project uses Gleam's built-in formatter:

```bash
just format
```

### Error Handling

Always use Result types for fallible operations:

```gleam
pub fn parse(input: String) -> Result(Value, ParseError)
```

### Documentation

Document all public functions with `///` comments including `## Examples` sections.

## Testing

### Running Tests

```bash
# All packages, Erlang target
just test

# All packages, JavaScript target
just test-js

# Single package
just test-pkg lattice_counters

# Single test by name
cd packages/lattice_counters && gleam test -- --filter "test_name"
```

Tests use the `startest` framework with `startest/expect`. Property-based tests use `qcheck`.

## Commit Messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <description>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

## Publishing

Packages are published to Hex.pm independently in dependency order. The `publish.yml` workflow handles this automatically:

1. Developer adds changelog entries with `just change` or `just change-pkg <name>`
2. On merge to main, `release.yml` batches unreleased changes into a release PR
3. Merging the release PR triggers `auto-tag.yml`, which creates per-package git tags (e.g., `lattice_core-v1.1.0`)
4. Tags trigger `publish.yml`, which:
   - Runs CI tests
   - Rewrites path dependencies to Hex version ranges (via `replace-path-deps`)
   - Publishes packages in dependency order
   - Creates a PR to refresh lockfiles

### Workspace Configuration

`workspace.toml` defines which packages belong to the workspace. All workflows read it via the `read-gleam-workspace` action — no need to hardcode package lists in workflow files.

### Publishing Order

Packages must be published in dependency order so that Hex.pm can resolve dependencies:

1. `lattice_core`, `lattice_counters`, `lattice_sets` (no lattice deps)
2. `lattice_registers` (depends on `lattice_core`)
3. `lattice_maps` (depends on `lattice_core`, `lattice_counters`, `lattice_registers`, `lattice_sets`)
4. `lattice_crdt` (depends on all above)

## Troubleshooting

```bash
# Clean all build artifacts
just clean

# Rebuild from scratch
just deps && just build

# Run a specific test
cd packages/<pkg> && gleam test -- --filter "test_name"
```

## Getting Help

- Check the [Gleam documentation](https://gleam.run/documentation/)
- Join the [Gleam Discord](https://discord.gg/Fm8Pwmy)
- Open an issue on GitHub
