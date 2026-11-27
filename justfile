# Lattice CRDT Monorepo Tasks
#
# Recipes delegate to trellis (https://github.com/tylerbutler/trellis), which
# derives the package list and dependency order from packages/*/gleam.toml.
# Run `trellis graph` to see the dependency graph.

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias c := check
alias cl := change
alias cp := change-pkg

default:
    @just --list

# === DEPENDENCIES ===

# Download dependencies for all packages
deps *ARGS:
    trellis run deps {{ ARGS }}
    cd tools/audit && gleam deps download

# === BUILD ===

# Build all packages (Erlang target)
build *ARGS:
    trellis run build {{ ARGS }}

# Build all packages with warnings as errors
build-strict *ARGS:
    trellis run build --strict {{ ARGS }}

# Build all packages for JavaScript target
build-js *ARGS:
    trellis run build --target javascript {{ ARGS }}

# Build all targets
build-all *ARGS:
    trellis run build --target all {{ ARGS }}

# Build all targets strictly
build-strict-all *ARGS:
    trellis run build --strict --target all {{ ARGS }}

# === TESTING ===

# Run tests for all packages (Erlang target)
test *ARGS:
    trellis run test {{ ARGS }}

# Test on Erlang target (alias for test)
test-erlang *ARGS: (test ARGS)

# Test on JavaScript target
test-js *ARGS:
    trellis run test --target javascript {{ ARGS }}

# Test on all targets
test-all *ARGS:
    trellis run test --target all {{ ARGS }}

# Test a single package: just test-pkg lattice_core
test-pkg pkg:
    trellis run test {{ pkg }}

# Check the OR-set reference model with Bend and its proof kernel (opt-in)
verify-or-set:
    cd verification/or_set && mise exec -- bend PROOF.bend --verdict

# === CODE QUALITY ===

# Format source code in all packages and examples
format *ARGS:
    trellis run format {{ ARGS }}

# Check formatting without changes
format-check *ARGS:
    trellis run format --check {{ ARGS }}

# Type check all packages
check *ARGS:
    trellis run check {{ ARGS }}

# Lint all packages and examples with glinter (config in each gleam.toml)
lint *ARGS:
    trellis run lint {{ ARGS }}

# Lint a single package: just lint-pkg lattice_core
lint-pkg pkg:
    trellis run lint {{ pkg }}

# Build a single package: just build-pkg lattice_core
build-pkg pkg:
    trellis run build {{ pkg }}

# Validate workspace invariants (graph, lockfiles, changelog state)
doctor:
    trellis doctor

# Enforce licences and the vulnerability threshold for every workspace member
licence-audit *ARGS:
    cd tools/audit && gleam run --target erlang -m licence_audit -- check --checks=all
    trellis run licence-audit --serial {{ ARGS }}

# Generate reproducible CycloneDX SBOMs for workspace members, including dev dependencies
sbom *ARGS:
    trellis run sbom --serial {{ ARGS }}

# === DOCUMENTATION ===

# Build documentation for published packages without bursting the Hex API
docs:
    trellis run docs --serial

# === CHANGELOG ===

# Create a changelog entry: just change --package lattice_core --kind Fixed --body "..."
change *ARGS:
    trellis changelog new {{ ARGS }}

# Create a changelog entry for a specific package
change-pkg pkg *ARGS:
    trellis changelog new --package {{ pkg }} {{ ARGS }}

# Preview pending version bumps from unreleased changelog fragments
changelog-preview *ARGS:
    trellis version plan {{ ARGS }}

# === MAINTENANCE ===

# Remove build artifacts from all packages
clean:
    trellis run clean
    rm -rf build

# === EXAMPLES ===

# Run all examples (Erlang) — the examples package's test suite runs every example
examples-run:
    trellis run test examples

# Run all examples (JavaScript)
examples-run-js:
    trellis run test --target javascript examples

# Run all examples on all targets
examples:
    trellis run test --target all examples

# === CI ===

# Run all CI checks (doctor, dependency audit, SBOM, format, check, lint, test, build strict)
ci:
    trellis doctor
    just licence-audit
    just sbom
    trellis run format --check
    trellis run check
    trellis run lint
    trellis run test
    trellis run build --strict

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs
