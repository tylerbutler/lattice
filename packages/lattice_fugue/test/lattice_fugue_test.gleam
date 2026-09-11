import gleeunit
import lattice_core/replica_id
import lattice_fugue/sequence

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn package_smoke_test() {
  assert sequence.new(replica_id.new("A")) == sequence.new(replica_id.new("A"))
}
