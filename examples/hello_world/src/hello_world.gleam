/// A simple hello world example demonstrating basic library usage.
///
/// Run with: gleam run -m hello_world

import gleam/io
import my_gleam_project

/// Main entry point for the example.
pub fn main() {
  // Use the library's hello function
  let greeting = my_gleam_project.hello("World")
  io.println(greeting)

  // Try with different names
  io.println(my_gleam_project.hello("Gleam"))
  io.println(my_gleam_project.hello("Developer"))
}
