/// Test helper utilities.
///
/// This module provides common utilities for testing, including:
/// - Sample data generators
/// - Assertion helpers
/// - Test fixtures
/// Creates sample test data.
///
/// ## Examples
///
/// ```gleam
/// let data = sample_data()
/// // -> "test_value"
/// ```
pub fn sample_data() -> String {
  "test_value"
}

/// Creates a list of sample strings for testing.
///
/// ## Examples
///
/// ```gleam
/// let items = sample_list()
/// // -> ["alpha", "beta", "gamma"]
/// ```
pub fn sample_list() -> List(String) {
  ["alpha", "beta", "gamma"]
}

/// Wraps a value in Ok for easier test assertions.
///
/// ## Examples
///
/// ```gleam
/// ok_result("value")
/// // -> Ok("value")
/// ```
pub fn ok_result(value: a) -> Result(a, b) {
  Ok(value)
}

/// Creates an error result for testing error cases.
///
/// ## Examples
///
/// ```gleam
/// error_result("error message")
/// // -> Error("error message")
/// ```
pub fn error_result(error: e) -> Result(a, e) {
  Error(error)
}
