# Gleam Project Tasks

# === ALIASES ===
alias b := build
alias t := test
alias f := format
alias c := check
alias d := docs
alias cl := change

default:
    @just --list

# === DEPENDENCIES ===

# Download project dependencies
deps:
    gleam deps download

# === BUILD ===

# Build project (Erlang target)
build:
    gleam build

# Build with warnings as errors
build-strict:
    gleam build --warnings-as-errors

# === TESTING ===

# Run all tests
test:
    gleam test

# === CODE QUALITY ===

# Format source code
format:
    gleam format src test
    cd examples && gleam format src

# Check formatting without changes
format-check:
    gleam format --check src test
    cd examples && gleam format --check src

# Type check without building
check:
    gleam check

# === DOCUMENTATION ===

# Build documentation
docs:
    gleam docs build

# === CHANGELOG ===

# Create a new changelog entry
change:
    changie new

# Preview unreleased changelog
changelog-preview:
    changie batch auto --dry-run

# Generate CHANGELOG.md
changelog:
    changie merge

# === MAINTENANCE ===

# Remove build artifacts
clean:
    rm -rf build

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

# Run all CI checks (format, check, test all targets, build strict all targets, examples)
ci: format-check check test-all build-strict-all examples

# Alias for PR checks
alias pr := ci

# Run extended checks for main branch
main: ci docs

# =============================================================================
# MULTI-TARGET SUPPORT
# =============================================================================

# Build for JavaScript target
build-js:
    gleam build --target javascript

# Build all targets
build-all: build build-js

# Build JavaScript with warnings as errors
build-strict-js:
    gleam build --target javascript --warnings-as-errors

# Build all targets strictly
build-strict-all: build-strict build-strict-js

# Test on Erlang target
test-erlang:
    gleam test

# Test on JavaScript target
test-js:
    gleam test --target javascript

# Test on all targets
test-all: test-erlang test-js

# =============================================================================
# JAVASCRIPT INTEGRATION TESTS (Uncomment if needed)
# =============================================================================

# # Run integration tests with Node.js
# test-integration-node: build-js
#     node --test test/integration/test_runner.mjs

# # Run integration tests with Deno
# test-integration-deno: build-js
#     deno test --allow-read --allow-env test/integration/test_runner.mjs

# # Run integration tests with Bun
# test-integration-bun: build-js
#     bun test test/integration/test_runner.mjs

# =============================================================================
# COVERAGE (Uncomment if needed)
# =============================================================================

# # Run tests with coverage (requires setup - see README)
# coverage:
#     @echo "Coverage requires additional setup. See README.md"
