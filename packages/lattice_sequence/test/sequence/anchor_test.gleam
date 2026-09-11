import lattice_core/replica_id
import lattice_sequence/sequence.{After, Before}

fn rid(id: String) {
  replica_id.new(id)
}

fn abc() {
  {
    let assert Ok(asserted_65) =
      {
        let assert Ok(asserted_66) =
          {
            let assert Ok(asserted_67) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_67
          }
          |> sequence.insert(1, "b")
        asserted_66
      }
      |> sequence.insert(2, "c")
    asserted_65
  }
}

pub fn start_anchor_resolves_to_zero_test() {
  let seq = abc()
  {
    let assert Ok(asserted_64) = sequence.resolve(seq, sequence.start_anchor())
    asserted_64
  }
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn start_anchor_stays_at_zero_after_insert_at_front_test() {
  let seq = {
    let assert Ok(asserted_63) = abc() |> sequence.insert(0, "x")
    asserted_63
  }
  {
    let assert Ok(asserted_62) = sequence.resolve(seq, sequence.start_anchor())
    asserted_62
  }
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn end_anchor_tracks_growth_test() {
  let anchor = sequence.end_anchor()
  let seq = abc()

  {
    let assert Ok(asserted_61) = sequence.resolve(seq, anchor)
    asserted_61
  }
  |> fn(actual) {
    assert actual == { 3 }
  }
  {
    let assert Ok(asserted_59) =
      sequence.resolve(
        {
          let assert Ok(asserted_60) = sequence.insert(seq, 3, "d")
          asserted_60
        },
        anchor,
      )
    asserted_59
  }
  |> fn(actual) {
    assert actual == { 4 }
  }
  {
    let assert Ok(asserted_58) =
      sequence.resolve(sequence.new(rid("A")), anchor)
    asserted_58
  }
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn try_anchor_at_negative_index_returns_error_test() {
  abc()
  |> sequence.anchor_at(-1, Before)
  |> fn(actual) {
    assert actual
      == { Error(sequence.AnchorIndexOutOfBounds(index: -1, length: 3)) }
  }
}

pub fn try_anchor_at_past_length_returns_error_test() {
  abc()
  |> sequence.anchor_at(4, After)
  |> fn(actual) {
    assert actual
      == { Error(sequence.AnchorIndexOutOfBounds(index: 4, length: 3)) }
  }
}

pub fn try_anchor_at_length_is_valid_test() {
  let seq = abc()
  let assert Ok(anchor) = sequence.anchor_at(seq, 3, Before)
  {
    let assert Ok(asserted_57) = sequence.resolve(seq, anchor)
    asserted_57
  }
  |> fn(actual) {
    assert actual == { 3 }
  }
}

pub fn anchor_at_length_with_before_bias_degrades_to_end_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_56) = sequence.anchor_at(seq, 3, Before)
    asserted_56
  }
  {
    let assert Ok(asserted_54) =
      // A true End sentinel tracks growth at the tail.
      sequence.resolve(
        {
          let assert Ok(asserted_55) = sequence.insert(seq, 3, "d")
          asserted_55
        },
        anchor,
      )
    asserted_54
  }
  |> fn(actual) {
    assert actual == { 4 }
  }
}

pub fn anchor_at_zero_with_after_bias_degrades_to_start_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_53) = sequence.anchor_at(seq, 0, After)
    asserted_53
  }
  {
    let assert Ok(asserted_51) =
      // A true Start sentinel stays at 0 even when content is inserted at 0.
      sequence.resolve(
        {
          let assert Ok(asserted_52) = sequence.insert(seq, 0, "x")
          asserted_52
        },
        anchor,
      )
    asserted_51
  }
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn anchor_on_empty_sequence_resolves_to_zero_test() {
  let seq = sequence.new(rid("A"))

  {
    let assert Ok(asserted_49) =
      sequence.resolve(seq, {
        let assert Ok(asserted_50) = sequence.anchor_at(seq, 0, Before)
        asserted_50
      })
    asserted_49
  }
  |> fn(actual) {
    assert actual == { 0 }
  }
  {
    let assert Ok(asserted_47) =
      sequence.resolve(seq, {
        let assert Ok(asserted_48) = sequence.anchor_at(seq, 0, After)
        asserted_48
      })
    asserted_47
  }
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn create_then_resolve_is_identity_test() {
  let seq = abc()

  {
    let assert Ok(asserted_45) =
      sequence.resolve(seq, {
        let assert Ok(asserted_46) = sequence.anchor_at(seq, 0, Before)
        asserted_46
      })
    asserted_45
  }
  |> fn(actual) {
    assert actual == { 0 }
  }
  {
    let assert Ok(asserted_43) =
      sequence.resolve(seq, {
        let assert Ok(asserted_44) = sequence.anchor_at(seq, 1, Before)
        asserted_44
      })
    asserted_43
  }
  |> fn(actual) {
    assert actual == { 1 }
  }
  {
    let assert Ok(asserted_41) =
      sequence.resolve(seq, {
        let assert Ok(asserted_42) = sequence.anchor_at(seq, 1, After)
        asserted_42
      })
    asserted_41
  }
  |> fn(actual) {
    assert actual == { 1 }
  }
  {
    let assert Ok(asserted_39) =
      sequence.resolve(seq, {
        let assert Ok(asserted_40) = sequence.anchor_at(seq, 2, After)
        asserted_40
      })
    asserted_39
  }
  |> fn(actual) {
    assert actual == { 2 }
  }
  {
    let assert Ok(asserted_37) =
      sequence.resolve(seq, {
        let assert Ok(asserted_38) = sequence.anchor_at(seq, 3, After)
        asserted_38
      })
    asserted_37
  }
  |> fn(actual) {
    assert actual == { 3 }
  }
}

pub fn insert_before_anchor_shifts_it_right_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_36) = sequence.anchor_at(seq, 2, Before)
    asserted_36
  }

  {
    let assert Ok(asserted_34) =
      sequence.resolve(
        {
          let assert Ok(asserted_35) = sequence.insert(seq, 0, "x")
          asserted_35
        },
        anchor,
      )
    asserted_34
  }
  |> fn(actual) {
    assert actual == { 3 }
  }
}

pub fn delete_before_anchor_shifts_it_left_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_33) = sequence.anchor_at(seq, 2, Before)
    asserted_33
  }

  {
    let assert Ok(asserted_31) =
      sequence.resolve(
        {
          let assert Ok(asserted_32) = sequence.delete(seq, 0)
          asserted_32
        },
        anchor,
      )
    asserted_31
  }
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn insert_after_anchor_does_not_move_it_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_30) = sequence.anchor_at(seq, 1, After)
    asserted_30
  }

  {
    let assert Ok(asserted_28) =
      sequence.resolve(
        {
          let assert Ok(asserted_29) = sequence.insert(seq, 2, "x")
          asserted_29
        },
        anchor,
      )
    asserted_28
  }
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn bias_diverges_for_insert_exactly_at_the_gap_test() {
  let seq = abc()
  let before = {
    let assert Ok(asserted_27) = sequence.anchor_at(seq, 1, Before)
    asserted_27
  }
  let after = {
    let assert Ok(asserted_26) = sequence.anchor_at(seq, 1, After)
    asserted_26
  }
  let updated = {
    let assert Ok(asserted_25) = sequence.insert(seq, 1, "x")
    asserted_25
  }

  // Before stays glued to "b", which was pushed right.
  let assert Ok(before_index) = sequence.resolve(updated, before)
  assert before_index == 2

  // After stays glued to "a", so the insert lands after the anchor.
  let assert Ok(after_index) = sequence.resolve(updated, after)
  assert after_index == 1
}

pub fn anchor_survives_deletion_of_its_item_test() {
  let seq = abc()
  let before = {
    let assert Ok(asserted_22) = sequence.anchor_at(seq, 1, Before)
    asserted_22
  }
  let after = {
    let assert Ok(asserted_21) = sequence.anchor_at(seq, 2, After)
    asserted_21
  }
  // Both anchors bind to "b"; delete it.
  let updated = {
    let assert Ok(asserted_20) = sequence.delete(seq, 1)
    asserted_20
  }
  {
    let assert Ok(asserted_19) =
      // Both biases collapse to the gap where "b" used to be.
      sequence.resolve(updated, before)
    asserted_19
  }
  |> fn(actual) {
    assert actual == { 1 }
  }
  {
    let assert Ok(asserted_18) = sequence.resolve(updated, after)
    asserted_18
  }
  |> fn(actual) {
    assert actual == { 1 }
  }
}

pub fn anchor_follows_moved_item_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_17) = sequence.anchor_at(seq, 0, Before)
    asserted_17
  }
  // Move "a" to the end: "bca".
  let updated = {
    let assert Ok(asserted_16) = sequence.move(seq, 0, 2)
    asserted_16
  }

  {
    let assert Ok(asserted_15) = sequence.resolve(updated, anchor)
    asserted_15
  }
  |> fn(actual) {
    assert actual == { 2 }
  }
}

pub fn try_resolve_unknown_target_before_merge_errors_test() {
  let alice = abc()
  let bob = {
    let assert Ok(asserted_14) =
      sequence.merge(sequence.new(rid("B")), alice, rid("B"))
      |> sequence.insert(1, "x")
    asserted_14
  }
  let anchor = {
    let assert Ok(asserted_13) = sequence.anchor_at(bob, 1, Before)
    asserted_13
  }

  // Alice has never seen Bob's item.
  sequence.resolve(alice, anchor)
  |> fn(actual) {
    assert actual == { Error(sequence.UnknownAnchorTarget) }
  }

  // After merging Bob's state, the anchor resolves.
  sequence.resolve(sequence.merge(alice, bob, rid("A")), anchor)
  |> fn(actual) {
    assert actual == { Ok(1) }
  }
}

pub fn resolution_agrees_across_replicas_after_merge_test() {
  let base = abc()
  let anchor = {
    let assert Ok(asserted_12) = sequence.anchor_at(base, 2, Before)
    asserted_12
  }
  let alice = {
    let assert Ok(asserted_11) =
      sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
      |> sequence.insert(0, "x")
    asserted_11
  }
  let bob = {
    let assert Ok(asserted_10) =
      sequence.merge(sequence.new(rid("bob")), base, rid("bob"))
      |> sequence.insert(3, "y")
    asserted_10
  }

  {
    let assert Ok(asserted_9) =
      sequence.resolve(sequence.merge(alice, bob, rid("A")), anchor)
    asserted_9
  }
  |> fn(actual) {
    assert actual
      == {
        {
          let assert Ok(asserted_8) =
            sequence.resolve(sequence.merge(bob, alice, rid("A")), anchor)
          asserted_8
        }
      }
  }
}

pub fn unicode_order_anchor_before_concurrent_first_insert_test() {
  let bmp = {
    let assert Ok(asserted_7) =
      sequence.new(rid("\u{e000}"))
      |> sequence.insert(0, "b")
    asserted_7
  }
  let supplementary = {
    let assert Ok(asserted_6) =
      sequence.new(rid("\u{10000}"))
      |> sequence.insert(0, "s")
    asserted_6
  }
  let anchor = {
    let assert Ok(asserted_5) = sequence.anchor_at(bmp, 0, Before)
    asserted_5
  }

  sequence.resolve(sequence.merge(bmp, supplementary, rid("observer")), anchor)
  |> fn(actual) {
    assert actual == { Ok(0) }
  }
  sequence.resolve(sequence.merge(supplementary, bmp, rid("observer")), anchor)
  |> fn(actual) {
    assert actual == { Ok(0) }
  }
}

pub fn anchor_creation_and_resolution_do_not_mutate_state_test() {
  let seq = abc()
  let anchor = {
    let assert Ok(asserted_4) = sequence.anchor_at(seq, 1, Before)
    asserted_4
  }
  let _ = {
    let assert Ok(asserted_3) = sequence.resolve(seq, anchor)
    asserted_3
  }
  {
    let assert Ok(asserted_2) =
      // Creating and resolving anchors must not bump the counter or add items:
      // the next insert behaves exactly as it would on an untouched sequence.
      sequence.insert(seq, 1, "x")
    asserted_2
  }
  |> fn(actual) {
    assert actual
      == {
        {
          let assert Ok(asserted_1) = sequence.insert(abc(), 1, "x")
          asserted_1
        }
      }
  }
}
