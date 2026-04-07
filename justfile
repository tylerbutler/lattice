# Lattice CRDT Monorepo Tasks
#
# Packages are built/tested in dependency order:
#   lattice_core → lattice_counters → lattice_sets → lattice_registers → lattice_maps → lattice_crdt

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias c := check
alias cl := change
alias cp := change-pkg

default:
    @just --list

# Packages in topological (dependency) order
packages := "lattice_core lattice_counters lattice_sets lattice_registers lattice_maps lattice_crdt"

# === DEPENDENCIES ===

# Download dependencies for all packages
deps:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: downloading deps"
        cd packages/$pkg && gleam deps download && cd ../..
    done

# === BUILD ===

# Build all packages (Erlang target)
build:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: building"
        cd packages/$pkg && gleam build && cd ../..
    done

# Build all packages with warnings as errors
build-strict:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: building (strict)"
        cd packages/$pkg && gleam build --warnings-as-errors && cd ../..
    done

# === TESTING ===

# Run tests for all packages (Erlang target)
test:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: testing (erlang)"
        cd packages/$pkg && gleam test && cd ../..
    done

# === CODE QUALITY ===

# Format source code in all packages and examples
format:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        cd packages/$pkg && gleam format src test && cd ../..
    done
    cd examples && gleam format src

# Check formatting without changes
format-check:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: format check"
        cd packages/$pkg && gleam format --check src test && cd ../..
    done
    cd examples && gleam format --check src

# Type check all packages
check:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: type check"
        cd packages/$pkg && gleam check && cd ../..
    done

# === DOCUMENTATION ===

# Build documentation for all packages
docs:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: building docs"
        cd packages/$pkg && gleam docs build && cd ../..
    done

# === CHANGELOG ===

# Create a new changelog entry (interactive project selection)
change:
    changie new

# Create a changelog entry for a specific package
change-pkg pkg:
    changie new --project {{ pkg }}

# Preview unreleased changelog for a project
changelog-preview pkg:
    changie batch auto --dry-run --project {{ pkg }}

# Generate CHANGELOG.md for a project
changelog pkg:
    changie merge --project {{ pkg }}

# === MAINTENANCE ===

# Remove build artifacts from all packages
clean:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        rm -rf packages/$pkg/build
    done
    rm -rf build examples/build

# === PER-PACKAGE TARGETS ===

# Test a single package: just test-pkg lattice_core
test-pkg pkg:
    cd packages/{{ pkg }} && gleam test

# Build a single package: just build-pkg lattice_core
build-pkg pkg:
    cd packages/{{ pkg }} && gleam build

# === EXAMPLES ===

# Build examples (Erlang)
examples-build:
    cd examples && gleam build --warnings-as-errors

# Build examples (JavaScript)
examples-build-js:
    cd examples && gleam build --target javascript --warnings-as-errors

# Run all examples (Erlang)
examples-run: examples-build
    #!/usr/bin/env bash
    set -euo pipefail
    cd examples
    for mod in g_counter_example pn_counter_example lww_register_example mv_register_example g_set_example two_p_set_example or_set_example lww_map_example or_map_example version_vector_example; do
        gleam run -m "$mod"
    done

# Run all examples (JavaScript)
examples-run-js: examples-build-js
    #!/usr/bin/env bash
    set -euo pipefail
    cd examples
    for mod in g_counter_example pn_counter_example lww_register_example mv_register_example g_set_example two_p_set_example or_set_example lww_map_example or_map_example version_vector_example; do
        gleam run -m "$mod" --target javascript
    done

# Run all examples on all targets
examples: examples-run examples-run-js

# === CI ===

# Run all CI checks (format, check, test, build strict)
ci: format-check check test build-strict

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs

# =============================================================================
# MULTI-TARGET SUPPORT
# =============================================================================

# Build all packages for JavaScript target
build-js:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: building (javascript)"
        cd packages/$pkg && gleam build --target javascript && cd ../..
    done

# Build all targets
build-all: build build-js

# Build JavaScript with warnings as errors
build-strict-js:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: building strict (javascript)"
        cd packages/$pkg && gleam build --target javascript --warnings-as-errors && cd ../..
    done

# Build all targets strictly
build-strict-all: build-strict build-strict-js

# Test on Erlang target (alias for test)
test-erlang: test

# Test on JavaScript target
test-js:
    #!/usr/bin/env bash
    set -euo pipefail
    for pkg in {{ packages }}; do
        echo "==> $pkg: testing (javascript)"
        cd packages/$pkg && gleam test --target javascript && cd ../..
    done

# Test on all targets
test-all: test-erlang test-js
