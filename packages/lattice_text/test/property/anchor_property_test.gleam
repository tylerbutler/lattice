import lattice_core/replica_id
import lattice_sequence/sequence.{type Bias, After, Before}
import lattice_text/text
import qcheck
import startest/expect

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
  |> expect.to_be_ok()
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
        |> expect.to_be_ok()
      let inserted =
        text.insert(base, insert_seed % 6, "xy") |> expect.to_be_ok()
      let updated =
        text.delete(inserted, delete_seed % text.length(inserted))
        |> expect.to_be_ok()

      let resolved = text.resolve_anchor(updated, anchor) |> expect.to_be_ok()
      expect.to_be_true(resolved >= 0 && resolved <= text.length(updated))
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
        text.anchor_at(base, anchor_index, Before) |> expect.to_be_ok()
      let updated =
        base
        |> text.insert(first_insert, "xx")
        |> expect.to_be_ok()
        |> text.insert(second_insert, "y")
        |> expect.to_be_ok()

      let resolved = text.resolve_anchor(updated, anchor) |> expect.to_be_ok()
      text.substring(updated, resolved, resolved + 1)
      |> expect.to_equal(grapheme)
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
          |> expect.to_be_ok(),
      )
      |> expect.to_be_ok()
      |> expect.to_equal(index)
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
        |> expect.to_be_ok()
      let alice =
        text.merge(text.new(rid("alice")), base, rid("alice"))
        |> text.insert(alice_insert, "x")
        |> expect.to_be_ok()
      let bob =
        text.merge(text.new(rid("bob")), base, rid("bob"))
        |> text.insert(bob_insert, "y")
        |> expect.to_be_ok()

      text.resolve_anchor(text.merge(alice, bob, rid("A")), anchor)
      |> expect.to_be_ok()
      |> expect.to_equal(
        text.resolve_anchor(text.merge(bob, alice, rid("A")), anchor)
        |> expect.to_be_ok(),
      )
      Nil
    },
  )
}
