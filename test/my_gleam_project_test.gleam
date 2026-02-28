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
