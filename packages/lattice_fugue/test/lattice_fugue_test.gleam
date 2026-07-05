import lattice_core/replica_id
import lattice_fugue/sequence
import startest
import startest/expect

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn package_smoke_test() {
  sequence.new(replica_id.new("A"))
  |> expect.to_equal(sequence.new(replica_id.new("A")))
}
