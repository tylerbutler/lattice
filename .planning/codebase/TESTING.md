# Testing Patterns

**Analysis Date:** 2026-02-28

## Test Framework

**Runner:**
- `gleeunit` 1.0.0+ (dev dependency in `gleam.toml`)
- Config: Configured in `gleam.toml` under `[dev-dependencies]`
- Gleam's built-in test runner integrated with gleeunit

**Assertion Library:**
- `gleeunit/should` module provides assertion DSL
- Fluent assertion syntax using pipe operator

**Run Commands:**
```bash
just test                  # Run all tests
gleam test                 # Direct gleam command
just format-check          # Check formatting (part of test suite)
just check                 # Type check (part of test suite)
just ci                    # Full CI suite: format-check, check, test, build-strict
```

## Test File Organization

**Location:**
- Co-located with source code in `test/` directory at project root
- Example structure:
  - `test/my_gleam_project_test.gleam` - Tests main module
  - `test/test_helpers.gleam` - Shared test utilities
  - `examples/{example_name}/test/{example_name}_test.gleam` - Example-specific tests

**Naming:**
- Test files: `{module}_test.gleam`
- Test functions: `{description}_test()`
- Main test entry point: `main() -> Nil { gleeunit.main() }`

**Structure:**
```
test/
├── my_gleam_project_test.gleam    # Module tests
├── hello_world_test.gleam         # Additional test files
└── test_helpers.gleam             # Shared fixtures/helpers
```

## Test Structure

**Suite Organization:**

From `test/my_gleam_project_test.gleam`:
```gleam
import gleeunit
import gleeunit/should
import my_gleam_project

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn hello_test() {
  my_gleam_project.hello("World")
  |> should.equal("Hello, World!")
}

pub fn hello_gleam_test() {
  my_gleam_project.hello("Gleam")
  |> should.equal("Hello, Gleam!")
}
```

**Patterns:**

**Setup Pattern:**
- No explicit setup/teardown needed for simple tests
- State passed through function parameters
- Immutable data from fixtures (see test helpers)

**Assertion Pattern:**
```gleam
import gleeunit/should

pub fn example_test() {
  actual_value
  |> should.equal(expected_value)
}
```

**Multiple Assertions:**
- Chain assertions using pattern matching or multiple test functions
- Each assertion wrapped in its own test function for clarity

## Test Fixtures and Factories

**Test Data:**

From `test/test_helpers.gleam`:
```gleam
/// Creates sample test data.
pub fn sample_data() -> String {
  "test_value"
}

/// Creates a list of sample strings for testing.
pub fn sample_list() -> List(String) {
  ["alpha", "beta", "gamma"]
}

/// Wraps a value in Ok for easier test assertions.
pub fn ok_result(value: a) -> Result(a, b) {
  Ok(value)
}

/// Creates an error result for testing error cases.
pub fn error_result(error: e) -> Result(a, e) {
  Error(error)
}
```

**Location:**
- Centralized in `test/test_helpers.gleam`
- Imported into test modules as needed: `import test_helpers`
- All public (pub) for easy access in any test file

**Purpose:**
- Sample data generators for common test values
- Result type helpers for testing error handling patterns
- Reusable test fixtures across multiple test modules

## Test Types

**Unit Tests:**
- Scope: Individual functions
- Approach: Direct function calls with assertions
- Example: Testing `hello()` function with different inputs
- Files: `test/my_gleam_project_test.gleam`, `test/hello_world_test.gleam`

**Integration Tests:**
- Not explicitly organized; unit tests verify library usage
- Example-based integration: `examples/hello_world/test/hello_world_test.gleam` tests real usage
- Verifies functions work correctly when imported and used

**E2E Tests:**
- Not used in this project
- Could be implemented using CLI testing if needed

## Error Handling Testing

**Pattern:**
```gleam
pub fn error_result(error: e) -> Result(a, e) {
  Error(error)
}
```

Test error cases by:
1. Creating error Results using `error_result()` helper
2. Pattern matching on Result type
3. Asserting error behavior with `should` assertions

Example from test structure:
- Tests verify both Ok and Error path through Result types
- Exhaustive pattern matching enforced by Gleam compiler

## Coverage

**Requirements:** None enforced

**Approach:**
- All tests run as part of CI pipeline
- Code review process ensures adequate coverage
- Gleam's type system catches many issues at compile time

**View Results:**
```bash
just test              # Run tests and view results in terminal
```

## CI/CD Integration

**CI Pipeline:** `.github/workflows/ci.yml`

**Test Execution:**
```yaml
- name: Run tests
  run: just test
```

**Steps Before Testing:**
1. Check formatting: `just format-check`
2. Type check: `just check`
3. Build with warnings as errors: `just build-strict`
4. Run tests: `just test`
5. Build documentation: `just docs`

**PR Validation:** `.github/workflows/pr.yml`
- Validates conventional commit format in PR title
- Checks for changelog entries using changie
- Blocks merge if tests fail (ci.yml workflow)

## Mocking

**Strategy:**
- Gleam's Result types enable testing without mocking
- Pure functions with explicit dependencies
- Test helpers provide fixture data instead of mocks

**No Mocking Library Used:**
- Dependency injection through function parameters
- Result types eliminate need for exception mocking
- Pure function design makes mocking unnecessary

**What NOT to Mock:**
- Standard library functions
- Pure functions (use actual implementations)
- Type system already prevents many mock-requiring errors

## Common Test Patterns

**Testing Pure Functions:**
```gleam
pub fn hello_test() {
  my_gleam_project.hello("World")
  |> should.equal("Hello, World!")
}
```

**Testing with Fixtures:**
```gleam
import test_helpers

pub fn with_sample_data_test() {
  test_helpers.sample_data()
  |> should.equal("test_value")
}
```

**Testing Result Types:**
```gleam
import test_helpers

pub fn result_test() {
  test_helpers.ok_result("value")
  |> should.equal(Ok("value"))
}
```

---

*Testing analysis: 2026-02-28*
