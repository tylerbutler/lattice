//// Runs every example as the package's test suite, so `gleam test` (and
//// `trellis run test`) exercises the examples on both targets. An example
//// that crashes fails the suite.

import g_counter_example
import g_set_example
import lww_map_example
import lww_register_example
import mv_register_example
import or_map_delta_websocket_example
import or_map_example
import or_set_example
import pn_counter_example
import sequence_example
import text_example
import two_p_set_example
import version_vector_example

pub fn main() {
  g_counter_example.main()
  pn_counter_example.main()
  lww_register_example.main()
  mv_register_example.main()
  g_set_example.main()
  two_p_set_example.main()
  or_set_example.main()
  lww_map_example.main()
  or_map_example.main()
  or_map_delta_websocket_example.main()
  version_vector_example.main()
  sequence_example.main()
  text_example.main()
}
