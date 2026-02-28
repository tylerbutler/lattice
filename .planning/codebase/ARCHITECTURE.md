# Architecture

**Analysis Date:** 2026-02-28

## Pattern Overview

**Overall:** Gleam Library Package with Runnable Examples

**Key Characteristics:**
- Functional programming with exhaustive pattern matching
- Compile-to-Erlang (BEAM target) with type safety
- Result types for explicit error handling
- Modular structure with public API layer and optional submodules
- Immutable data and pure functions as primary paradigm

## Layers

**Public API Layer:**
- Purpose: Expose library functions to external consumers
- Location: `src/my_gleam_project.gleam`
- Contains: Public functions with complete type signatures and documentation
- Depends on: Internal modules (future), gleam_stdlib
- Used by: Example projects, external libraries that import this package

**Submodules (Future):**
- Purpose: Feature-specific implementations and internal logic
- Location: `src/my_gleam_project/*.gleam`
- Contains: Internal functions, domain-specific types, helper logic
- Depends on: gleam_stdlib, potentially other submodules
- Used by: Main module via selective re-exports

**Internal Modules (Optional):**
- Purpose: Private implementation details not exposed in public API
- Location: `src/my_gleam_project/internal/*.gleam`
- Contains: Low-level operations, shared utilities, implementation details
- Depends on: Other internal modules, gleam_stdlib
- Used by: Parent submodules only
- Configuration: Marked in `gleam.toml` via `internal_modules` directive

**Test Infrastructure:**
- Purpose: Testing library functionality and providing test utilities
- Location: `test/`
- Contains: Test suites, test helpers, fixtures, sample data
- Depends on: gleeunit testing framework, library under test
- Used by: CI pipeline, local development testing

**Example Projects:**
- Purpose: Demonstrate library usage and test integration scenarios
- Location: `examples/hello_world/`
- Contains: Standalone Gleam applications using the library as dependency
- Depends on: Main library via path dependency, gleam_stdlib
- Used by: Documentation, onboarding, integration verification

## Data Flow

**Library Usage Flow:**

1. Consumer imports main module: `import my_gleam_project`
2. Consumer calls public function: `my_gleam_project.hello("name")`
3. Function processes input using pattern matching and pure functions
4. Function returns result via Result type or direct value
5. Consumer handles success/error cases explicitly

**Example Execution Flow:**

1. Example project declares path dependency: `my_gleam_project = { path = "../.." }`
2. Example imports library: `import my_gleam_project`
3. Example calls library function in main(): `my_gleam_project.hello("World")`
4. Output printed via `gleam/io` module: `io.println(greeting)`

**Testing Flow:**

1. Test module imports: `import gleeunit`, `import gleeunit/should`, `import my_gleam_project`
2. Test function invokes library code
3. Test assertions via should pipeline: `result |> should.equal(expected)`
4. gleeunit framework aggregates and reports results

**State Management:**
- No mutable state: All functions are pure and immutable
- Values passed through function pipelines using pipe operator `|>`
- Result types encapsulate success/error states explicitly
- No global state or side effects in library functions

## Key Abstractions

**Result Type:**
- Purpose: Explicit error handling without exceptions
- Examples: `Result(String, Error)` for fallible operations
- Pattern: All functions that can fail return Result type
- Usage: Case expressions or piping to Result-aware functions

**Public API Boundary:**
- Purpose: Separate public interface from private implementation
- Examples: `pub fn hello(name: String) -> String`
- Pattern: Public functions fully documented with JSDoc-style comments, private modules marked in gleam.toml
- Usage: Consumers interact only with pub-decorated functions

**Test Helper Functions:**
- Purpose: Provide reusable test fixtures and assertion utilities
- Examples: `ok_result()`, `error_result()`, `sample_data()`, `sample_list()`
- Pattern: Located in `test/test_helpers.gleam`, exported as public test utilities
- Usage: Imported in test files to setup test data consistently

**Type Signatures:**
- Purpose: Document and enforce function contracts
- Examples: `fn(String) -> String`, `fn(String) -> Result(Value, Error)`
- Pattern: All functions include explicit type annotations
- Usage: Compiler enforces compatibility; documentation ensures correctness

## Entry Points

**Main Library Module:**
- Location: `src/my_gleam_project.gleam`
- Triggers: Import statement from external code
- Responsibilities: Expose public API, re-export submodules, provide documentation

**Example Application:**
- Location: `examples/hello_world/src/hello_world.gleam`
- Triggers: `gleam run -m hello_world` command
- Responsibilities: Demonstrate library usage, invoke main() function, print results to console

**Test Suite:**
- Location: `test/my_gleam_project_test.gleam`
- Triggers: `gleam test` command or CI pipeline
- Responsibilities: Validate library functionality, execute assertions, report coverage

## Error Handling

**Strategy:** Explicit Result types for all fallible operations

**Patterns:**
- Functions return `Result(SuccessType, ErrorType)` for operations that can fail
- Callers must explicitly handle both Ok and Error branches via case expressions
- Test helpers provide `ok_result()` and `error_result()` constructors for test scenarios
- No exceptions or panics; all error paths are tracked in type system

## Cross-Cutting Concerns

**Logging:** Not currently implemented; use `gleam/io` for console output if needed

**Validation:** Implemented via type system and pattern matching; invalid states are unrepresentable

**Authentication:** Not applicable for library; handled by consuming applications

**Documentation:** Triple-slash (///) comments on all public functions with examples; Gleam docs build via `gleam docs build`

---

*Architecture analysis: 2026-02-28*
