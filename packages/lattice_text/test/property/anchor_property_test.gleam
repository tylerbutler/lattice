import lattice_core/replica_id
import lattice_sequence/sequence.{type Bias, After, Before}
import lattice_text/text
import qcheck

fn rid(id: String) {
  replica_id.new(id)
}

/// The workspace default. These ran at 10 cases, which is not enough sweep to
/// exercise the convergence laws they assert.
fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 1000, max_retries: 3, seed: qcheck.seed(42))
}

fn doc(value: String) {
  text.new(rid("A"))
  |> text.insert(0, value)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
}

fn bias_from_int(n: Int) -> Bias {
  case n % 2 {
    0 -> Before
    _ -> After
  }
}

pub fn anchor_resolution_stays_in_bounds__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 5),
      qcheck.bounded_int(0, 100),
      qcheck.bounded_int(0, 100),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(anchor_index, insert_seed, delete_seed) = triple
      let base = doc("abcde")
      let anchor =
        text.anchor_at(base, anchor_index, bias_from_int(insert_seed))
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
      let inserted =
        text.insert(base, insert_seed % 6, "xy")
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
      let updated =
        text.delete(inserted, delete_seed % text.length(inserted))
        |> fn(result) {
          let assert Ok(value) = result
          value
        }

      let resolved =
        text.resolve_anchor(updated, anchor)
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
      assert resolved >= 0 && resolved <= text.length(updated)
      Nil
    },
  )
}

pub fn before_anchor_on_live_grapheme_tracks_it__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 4),
      qcheck.bounded_int(0, 5),
      qcheck.bounded_int(0, 6),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(anchor_index, first_insert, second_insert) = triple
      let base = doc("abcde")
      let grapheme = text.substring(base, anchor_index, anchor_index + 1)
      let anchor =
        text.anchor_at(base, anchor_index, Before)
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
      let updated =
        base
        |> text.insert(first_insert, "xx")
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
        |> text.insert(second_insert, "y")
        |> fn(result) {
          let assert Ok(value) = result
          value
        }

      let resolved =
        text.resolve_anchor(updated, anchor)
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
      text.substring(updated, resolved, resolved + 1)
      |> fn(actual) {
        assert actual == grapheme
      }
      Nil
    },
  )
}

pub fn create_then_resolve_is_identity__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(qcheck.bounded_int(0, 5), qcheck.bounded_int(0, 1), fn(a, b) {
      #(a, b)
    }),
    fn(pair) {
      let #(index, bias_seed) = pair
      let base = doc("abcde")

      text.resolve_anchor(
        base,
        text.anchor_at(base, index, bias_from_int(bias_seed))
          |> fn(result) {
            let assert Ok(value) = result
            value
          },
      )
      |> fn(result) {
        let assert Ok(value) = result
        value
      }
      |> fn(actual) {
        assert actual == index
      }
      Nil
    },
  )
}

pub fn resolution_agrees_across_replicas_after_merge__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map3(
      qcheck.bounded_int(0, 5),
      qcheck.bounded_int(0, 5),
      qcheck.bounded_int(0, 5),
      fn(a, b, c) { #(a, b, c) },
    ),
    fn(triple) {
      let #(anchor_index, alice_insert, bob_insert) = triple
      let base = doc("abcde")
      let anchor =
        text.anchor_at(base, anchor_index, bias_from_int(alice_insert))
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
      let alice =
        text.merge(text.new(rid("alice")), base, rid("alice"))
        |> text.insert(alice_insert, "x")
        |> fn(result) {
          let assert Ok(value) = result
          value
        }
      let bob =
        text.merge(text.new(rid("bob")), base, rid("bob"))
        |> text.insert(bob_insert, "y")
        |> fn(result) {
          let assert Ok(value) = result
          value
        }

      text.resolve_anchor(text.merge(alice, bob, rid("A")), anchor)
      |> fn(result) {
        let assert Ok(value) = result
        value
      }
      |> fn(actual) {
        let assert Ok(expected) =
          text.resolve_anchor(text.merge(bob, alice, rid("A")), anchor)
        assert actual == expected
      }
      Nil
    },
  )
}
