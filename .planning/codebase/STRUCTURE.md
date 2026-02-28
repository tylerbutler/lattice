# Codebase Structure

**Analysis Date:** 2026-02-28

## Directory Layout

```
lattice/
├── src/                              # Library source code
│   ├── my_gleam_project.gleam       # Main public API module
│   └── my_gleam_project/            # Submodules (optional, future)
│       └── internal/                # Private implementation (optional)
├── test/                             # Test suite
│   ├── my_gleam_project_test.gleam  # Main test module
│   └── test_helpers.gleam           # Shared test utilities
├── examples/                         # Runnable example projects
│   └── hello_world/                 # Hello World example
│       ├── src/
│       │   └── hello_world.gleam    # Example application
│       ├── test/
│       │   └── hello_world_test.gleam
│       ├── gleam.toml               # Example project config
│       └── README.md
├── .github/                          # GitHub configuration
│   └── workflows/                   # CI/CD workflows
│       ├── ci.yml                   # Main CI pipeline
│       ├── release.yml              # Release automation
│       └── publish.yml              # Hex.pm publishing
├── .changes/                         # Changelog management
├── gleam.toml                        # Project manifest
├── justfile                          # Task runner configuration
├── manifest.toml                     # Dependency lock file
├── CLAUDE.md                         # Development instructions
└── README.md                         # Public documentation
```

## Directory Purposes

**src/ - Library Source:**
- Purpose: Contains all library implementation code
- Contains: Gleam modules (.gleam files) implementing library functionality
- Key files: `src/my_gleam_project.gleam` (main public API)

**test/ - Test Suite:**
- Purpose: Contains all automated tests and test utilities
- Contains: Test modules using gleeunit framework, test helper utilities
- Key files: `test/my_gleam_project_test.gleam` (main tests), `test/test_helpers.gleam` (fixtures)

**examples/ - Example Projects:**
- Purpose: Demonstrate library usage with runnable applications
- Contains: Standalone Gleam projects with path dependency on main library
- Key files: `examples/hello_world/src/hello_world.gleam` (example app), `examples/hello_world/README.md`

**.github/workflows/ - CI/CD:**
- Purpose: GitHub Actions automation for testing, releasing, and publishing
- Contains: YAML workflow files for continuous integration and deployment
- Key files: `ci.yml` (format/check/test/build), `release.yml` (versioning), `publish.yml` (Hex.pm)

## Key File Locations

**Entry Points:**
- `src/my_gleam_project.gleam`: Primary library entry point; defines public API surface
- `examples/hello_world/src/hello_world.gleam`: Example application entry point; demonstrates library usage
- `test/my_gleam_project_test.gleam`: Test suite entry point; contains main() and test functions

**Configuration:**
- `gleam.toml`: Project manifest defining name, version, dependencies, compiler settings
- `justfile`: Task automation; defines build, test, format, and CI commands
- `manifest.toml`: Dependency lock file (auto-generated, do not edit)
- `.commitlintrc.json`: Conventional commit validation rules

**Core Logic:**
- `src/my_gleam_project.gleam`: Library implementation and public API
- `src/my_gleam_project/*.gleam`: Future feature modules (optional substructure)

**Testing:**
- `test/my_gleam_project_test.gleam`: Test cases for library functions
- `test/test_helpers.gleam`: Reusable test fixtures and helper functions
- `examples/hello_world/test/hello_world_test.gleam`: Example project tests

## Naming Conventions

**Files:**
- Main library module: `{project_name}.gleam` (e.g., `my_gleam_project.gleam`)
- Submodules: `{project_name}/{feature}.gleam` (e.g., `my_gleam_project/parser.gleam`)
- Test files: `{module_name}_test.gleam` (e.g., `my_gleam_project_test.gleam`)
- Test helpers: `test_helpers.gleam`
- Examples: Descriptive names in `examples/{example_name}/src/{example_name}.gleam`

**Directories:**
- Source: `src/` (top-level modules), `src/{project_name}/` (submodules)
- Tests: `test/` (flat structure at project level)
- Examples: `examples/{example_name}/` (separate Gleam projects)
- Internal: `src/{project_name}/internal/` (private implementation modules)

## Where to Add New Code

**New Feature:**
- Primary code: Create `src/my_gleam_project/{feature}.gleam` for new feature module
- Tests: Create corresponding `test/{feature}_test.gleam` test module
- Re-export: Add `pub use {feature}` to `src/my_gleam_project.gleam` if public
- Mark internal: Add path to `internal_modules` in `gleam.toml` if private

**New Component/Module:**
- Implementation: `src/my_gleam_project/{component}.gleam`
- Public API: Export via `pub use` in main module or re-export selectively
- Internal implementation: `src/my_gleam_project/internal/{detail}.gleam` for implementation details
- Documentation: Add JSDoc-style comments (///) with examples

**Utilities:**
- Shared test helpers: Add to `test/test_helpers.gleam`
- Library-level utilities: Create `src/my_gleam_project/util.gleam` or similar
- Internal utilities: Place in `src/my_gleam_project/internal/util.gleam`

**New Example:**
- Create `examples/{example_name}/` directory as independent Gleam project
- Configure path dependency in `examples/{example_name}/gleam.toml`: `{project_name} = { path = "../.." }`
- Add README documenting purpose and running instructions
- Include test file to validate example behavior

## Special Directories

**.github/workflows/:**
- Purpose: GitHub Actions CI/CD automation
- Generated: No (manually created and maintained)
- Committed: Yes (checked into repository)
- Key files: `ci.yml` (format/check/test/build), `release.yml` (version bumps), `publish.yml` (Hex.pm)

**.changes/:**
- Purpose: Changelog management via changie tool
- Generated: Yes (changelog entries auto-created)
- Committed: Yes (fragment files committed, merged into CHANGELOG.md)
- Usage: `just change` creates new entry, `just changelog` merges into CHANGELOG.md

**build/:**
- Purpose: Compiled output and build artifacts
- Generated: Yes (created by `gleam build`)
- Committed: No (in .gitignore)
- Usage: Contains compiled Erlang/JavaScript code; safe to delete

**examples/{example_name}/**
- Purpose: Standalone Gleam project demonstrating library usage
- Generated: No (manually created projects)
- Committed: Yes (entire example project structure)
- Uses path dependency to main library for development/testing

---

*Structure analysis: 2026-02-28*
