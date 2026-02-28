import gleeunit
import gleeunit/should
import my_gleam_project

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn hello_from_example_test() {
  my_gleam_project.hello("Example")
  |> should.equal("Hello, Example!")
}
