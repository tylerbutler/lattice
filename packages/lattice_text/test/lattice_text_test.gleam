import gleeunit
import lattice_core/replica_id
import lattice_text/text

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_smoke_test() {
  assert text.new(replica_id.new("A")) == text.new(replica_id.new("A"))
}
