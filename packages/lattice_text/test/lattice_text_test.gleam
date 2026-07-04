import lattice_core/replica_id
import lattice_text/text
import startest
import startest/expect

pub fn main() -> Nil {
  startest.run(startest.default_config())
}

pub fn package_smoke_test() {
  text.new(replica_id.new("A"))
  |> expect.to_equal(text.new(replica_id.new("A")))
}
