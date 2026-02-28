# Coding Conventions

**Analysis Date:** 2026-02-28

## Naming Patterns

**Files:**
- Gleam source files: `snake_case.gleam` (e.g., `my_gleam_project.gleam`, `test_helpers.gleam`)
- Test files: `{module}_test.gleam` (e.g., `my_gleam_project_test.gleam`, `hello_world_test.gleam`)
- Example projects: `examples/{feature_name}/` directory structure

**Functions:**
- All lowercase with underscores: `snake_case`
- Example: `sample_data()`, `ok_result()`, `error_result()`, `sample_list()`
- Test functions use pattern `{description}_test()` (e.g., `hello_test()`, `hello_gleam_test()`)

**Variables:**
- All lowercase with underscores: `snake_case`
- Example: `test_value`, `sample_list`, `greeting`, `error_message`

**Types:**
- Use Result type for fallible operations (no exceptions)
- Error types should be descriptive: `Result(SuccessType, ErrorType)`
- Example: `Result(String, ParseError)`, `Result(a, b)` for generic helpers

## Code Style

**Formatting:**
- Auto-formatted with built-in `gleam format` command
- Run before all commits: `just format`
- Check formatting in CI: `just format-check`
- Line length: 100 characters (enforced for commit bodies)
- Header max length: 72 characters (commit messages)

**Linting:**
- Gleam compiler enforces type safety and exhaustive pattern matching
- Build with warnings as errors in strict mode: `gleam build --warnings-as-errors`
- All warnings must be resolved

## Import Organization

**Order:**
1. Standard library imports (gleam_stdlib)
2. External package imports
3. Internal module imports
4. Test framework imports (gleeunit in test files)

**Path Aliases:**
- No aliases used; direct module paths
- Example: `import gleam/io`, `import my_gleam_project`

**Barrel Files:**
- Main module `my_gleam_project.gleam` re-exports from submodules
- Keeps public API minimal and organized
- Defined in `gleam.toml` via internal_modules configuration

## Error Handling

**Patterns:**
- Use Result types for all operations that can fail
- Return `Result(Value, Error)` from public functions
- Example patterns from `test_helpers.gleam`:
  ```gleam
  pub fn ok_result(value: a) -> Result(a, b) {
    Ok(value)
  }

  pub fn error_result(error: e) -> Result(a, e) {
    Error(error)
  }
  ```
- Never use exceptions; Result is the idiomatic error handling mechanism
- Pattern match all Result types exhaustively in case expressions

**Error Case Handling:**
```gleam
case result {
  Ok(value) -> handle_success(value)
  Error(err) -> handle_error(err)
}
```

## Logging

**Framework:** No centralized logging framework in use

**Patterns:**
- Use `gleam/io` module for output (e.g., `io.println()`)
- Example from `examples/hello_world/src/hello_world.gleam`:
  ```gleam
  import gleam/io
  io.println(greeting)
  ```

## Comments

**When to Comment:**
- Use triple-slash `///` documentation comments for all public functions
- Include module overview at top of files
- Include examples section for public functions

**JSDoc/TSDoc:**
- Gleam uses `///` for documentation comments
- Documentation includes sections: description, examples
- Example from `src/my_gleam_project.gleam`:
  ```gleam
  /// A friendly greeting function.
  ///
  /// ## Examples
  ///
  /// ```gleam
  /// hello("World")
  /// // -> "Hello, World!"
  /// ```
  ```

## Function Design

**Size:**
- Keep functions small and focused
- Single responsibility principle

**Parameters:**
- Use explicit type annotations for all parameters
- Example: `pub fn hello(name: String) -> String`
- Generic functions use type variables: `pub fn ok_result(value: a) -> Result(a, b)`

**Return Values:**
- Always include explicit return type annotation
- Prefer Result types for operations that can fail
- Single statement functions are idiomatic
- Example: `"Hello, " <> name <> "!"`

## Module Design

**Exports:**
- All public functions use `pub` keyword
- Non-exported functions omitted (private by default)
- Main module serves as public API facade

**Submodules:**
- Organize by feature within `project_name/` directory
- Mark internal-only modules in `gleam.toml`:
  ```toml
  internal_modules = ["my_gleam_project/internal", "my_gleam_project/internal/*"]
  ```

## String Operations

**Concatenation:**
- Use `<>` operator for string concatenation
- Example: `"Hello, " <> name <> "!"`

## Conventional Commits

**Format:** `type(scope): description`

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `style` - Code style changes
- `refactor` - Code refactoring
- `perf` - Performance improvements
- `test` - Test additions or updates
- `build` - Build system changes
- `ci` - CI configuration changes
- `chore` - Miscellaneous changes
- `revert` - Revert previous commit

**Rules:**
- Scope must be lowercase: `scope-case`
- Subject must be lowercase: `subject-case`
- Subject must not be empty: `subject-empty`
- No period at end of subject: `subject-full-stop`
- Header max length: 72 characters
- Body max line length: 100 characters
- Configuration in `.commitlintrc.json` enforced by CI

---

*Convention analysis: 2026-02-28*
