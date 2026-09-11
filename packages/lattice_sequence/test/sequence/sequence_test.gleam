import gleam/dynamic/decode
import gleam/json
import gleam/list
import lattice_core/replica_id
import lattice_sequence/sequence

fn rid(id: String) {
  replica_id.new(id)
}

pub fn new_values_is_empty_test() {
  sequence.new(rid("A"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { [] }
  }
}

pub fn new_length_is_zero_test() {
  sequence.new(rid("A"))
  |> sequence.length()
  |> fn(actual) {
    assert actual == { 0 }
  }
}

pub fn insert_integer_into_empty_sequence_test() {
  {
    let assert Ok(asserted_129) =
      sequence.new(rid("A"))
      |> sequence.insert(0, 42)
    asserted_129
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { [42] }
  }
}

pub fn insert_appends_at_end_test() {
  {
    let assert Ok(asserted_127) =
      {
        let assert Ok(asserted_128) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "h")
        asserted_128
      }
      |> sequence.insert(1, "i")
    asserted_127
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["h", "i"] }
  }
}

pub fn ten_thousand_items_insert_run_and_merge_delta_preserve_order_and_ids_test() {
  let values = list.repeat(0, 10_000) |> list.index_map(fn(_, index) { index })
  let assert Ok(base) = sequence.insert_many(sequence.new(rid("A")), 0, values)
  let assert Ok(old_anchor) = sequence.anchor_at(base, 9999, sequence.Before)
  let assert Ok(#(updated, delta)) =
    sequence.insert_many_with_delta(base, 9999, [-1, -2])
  let expected = list.append(list.take(values, 9999), [-1, -2, 9999])
  sequence.values(updated)
  |> fn(actual) {
    assert actual == { expected }
  }
  sequence.values(delta)
  |> fn(actual) {
    assert actual == { [-1, -2] }
  }
  sequence.resolve(updated, old_anchor)
  |> fn(actual) {
    assert actual == { Ok(10_001) }
  }
  sequence.anchor_at(updated, 10_001, sequence.Before)
  |> fn(actual) {
    assert actual == { Ok(old_anchor) }
  }
  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { updated }
  }
  sequence.merge(delta, base, rid("A"))
  |> fn(actual) {
    assert actual == { updated }
  }

  let assert Ok(#(appended, append_delta)) =
    sequence.insert_with_delta(updated, 10_002, -3)
  sequence.values(appended)
  |> fn(actual) {
    assert actual == { list.append(expected, [-3]) }
  }
  sequence.length(append_delta)
  |> fn(actual) {
    assert actual == { 1 }
  }
  sequence.merge(updated, append_delta, rid("A"))
  |> fn(actual) {
    assert actual == { appended }
  }
}

pub fn insert_in_middle_test() {
  {
    let assert Ok(asserted_124) =
      {
        let assert Ok(asserted_125) =
          {
            let assert Ok(asserted_126) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_126
          }
          |> sequence.insert(1, "c")
        asserted_125
      }
      |> sequence.insert(1, "b")
    asserted_124
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "b", "c"] }
  }
}

pub fn try_insert_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert_with_delta(-1, "x")
  |> fn(actual) {
    assert actual == { Error(sequence.IndexOutOfBounds(index: -1, length: 0)) }
  }
}

pub fn try_insert_past_end_returns_error_test() {
  {
    let assert Ok(asserted_123) =
      sequence.new(rid("A"))
      |> sequence.insert(0, "a")
    asserted_123
  }
  |> sequence.insert_with_delta(2, "x")
  |> fn(actual) {
    assert actual == { Error(sequence.IndexOutOfBounds(index: 2, length: 1)) }
  }
}

pub fn delete_removes_visible_item_test() {
  {
    let assert Ok(asserted_119) =
      {
        let assert Ok(asserted_120) =
          {
            let assert Ok(asserted_121) =
              {
                let assert Ok(asserted_122) =
                  sequence.new(rid("A"))
                  |> sequence.insert(0, "a")
                asserted_122
              }
              |> sequence.insert(1, "b")
            asserted_121
          }
          |> sequence.insert(2, "c")
        asserted_120
      }
      |> sequence.delete(1)
    asserted_119
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "c"] }
  }
}

pub fn try_delete_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.delete_with_delta(-1)
  |> fn(actual) {
    assert actual
      == { Error(sequence.DeleteIndexOutOfBounds(index: -1, length: 0)) }
  }
}

pub fn try_delete_at_end_returns_error_test() {
  {
    let assert Ok(asserted_118) =
      sequence.new(rid("A"))
      |> sequence.insert(0, "a")
    asserted_118
  }
  |> sequence.delete_with_delta(1)
  |> fn(actual) {
    assert actual
      == { Error(sequence.DeleteIndexOutOfBounds(index: 1, length: 1)) }
  }
}

pub fn merge_concurrent_insert_same_position_is_deterministic_test() {
  let base = {
    let assert Ok(asserted_116) =
      {
        let assert Ok(asserted_117) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_117
      }
      |> sequence.insert(1, "c")
    asserted_116
  }
  let alice = {
    let assert Ok(asserted_115) =
      sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
      |> sequence.insert(1, "b")
    asserted_115
  }
  let bob = {
    let assert Ok(asserted_114) =
      sequence.merge(sequence.new(rid("bob")), base, rid("bob"))
      |> sequence.insert(1, "X")
    asserted_114
  }

  let ab = sequence.merge(alice, bob, rid("A")) |> sequence.values()
  let ba = sequence.merge(bob, alice, rid("A")) |> sequence.values()

  ab
  |> fn(actual) {
    assert actual == { ba }
  }
  ab
  |> fn(actual) {
    assert actual == { ["a", "b", "X", "c"] }
  }
}

pub fn unicode_order_concurrent_first_inserts_and_deltas_test() {
  // UTF-8 orders U+E000 before U+10000, unlike UTF-16 code units.
  let #(bmp, bmp_delta) = {
    let assert Ok(asserted_113) =
      sequence.new(rid("\u{e000}"))
      |> sequence.insert_with_delta(0, "b")
    asserted_113
  }
  let #(supplementary, supplementary_delta) = {
    let assert Ok(asserted_112) =
      sequence.new(rid("\u{10000}"))
      |> sequence.insert_with_delta(0, "s")
    asserted_112
  }

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
  ])
  sequence.merge(pair.0, pair.1, rid("observer"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["b", "s"] }
  }
}

pub fn merge_delete_and_insert_after_deleted_anchor_test() {
  let base = {
    let assert Ok(asserted_109) =
      {
        let assert Ok(asserted_110) =
          {
            let assert Ok(asserted_111) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_111
          }
          |> sequence.insert(1, "b")
        asserted_110
      }
      |> sequence.insert(2, "c")
    asserted_109
  }

  let alice = {
    let assert Ok(asserted_108) = base |> sequence.delete(1)
    asserted_108
  }
  let bob = {
    let assert Ok(asserted_107) =
      sequence.merge(sequence.new(rid("B")), base, rid("B"))
      |> sequence.insert(2, "Y")
    asserted_107
  }

  sequence.merge(alice, bob, rid("A"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "Y", "c"] }
  }
}

pub fn merge_concurrent_runs_do_not_interleave_for_forward_typing_test() {
  let base = {
    let assert Ok(asserted_106) =
      sequence.new(rid("base")) |> sequence.insert(0, "_")
    asserted_106
  }
  let alice = {
    let assert Ok(asserted_103) =
      {
        let assert Ok(asserted_104) =
          {
            let assert Ok(asserted_105) =
              sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
              |> sequence.insert(1, "m")
            asserted_105
          }
          |> sequence.insert(2, "o")
        asserted_104
      }
      |> sequence.insert(3, "m")
    asserted_103
  }
  let bob = {
    let assert Ok(asserted_100) =
      {
        let assert Ok(asserted_101) =
          {
            let assert Ok(asserted_102) =
              sequence.merge(sequence.new(rid("bob")), base, rid("bob"))
              |> sequence.insert(1, "d")
            asserted_102
          }
          |> sequence.insert(2, "a")
        asserted_101
      }
      |> sequence.insert(3, "d")
    asserted_100
  }

  sequence.merge(alice, bob, rid("A"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["_", "m", "o", "m", "d", "a", "d"] }
  }
}

pub fn merge_applies_insert_delta_test() {
  let base = sequence.new(rid("A"))
  let #(updated, delta) = {
    let assert Ok(asserted_99) = sequence.insert_with_delta(base, 0, "x")
    asserted_99
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { updated }
  }
}

pub fn merge_applies_delete_delta_test() {
  let base = {
    let assert Ok(asserted_98) =
      sequence.new(rid("A")) |> sequence.insert(0, "x")
    asserted_98
  }
  let #(updated, delta) = {
    let assert Ok(asserted_97) = sequence.delete_with_delta(base, 0)
    asserted_97
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { updated }
  }
}

pub fn insert_after_delete_at_same_index_is_canonically_ordered_test() {
  // Regression: a local insert whose position is preceded by tombstones must
  // produce the same item order as merge/from_json normalization, so that
  // merge(base, delta, local) structurally equals the directly updated state.
  let base = {
    let assert Ok(asserted_94) =
      {
        let assert Ok(asserted_95) =
          {
            let assert Ok(asserted_96) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_96
          }
          |> sequence.insert(1, "b")
        asserted_95
      }
      |> sequence.delete(0)
    asserted_94
  }
  let #(updated, delta) = {
    let assert Ok(asserted_93) = sequence.insert_with_delta(base, 0, "x")
    asserted_93
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { updated }
  }
  sequence.values(updated)
  |> fn(actual) {
    assert actual == { ["x", "b"] }
  }
}

pub fn insert_many_into_empty_test() {
  {
    let assert Ok(asserted_92) =
      sequence.new(rid("A"))
      |> sequence.insert_many(0, ["a", "b", "c"])
    asserted_92
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "b", "c"] }
  }
}

pub fn insert_many_in_middle_test() {
  {
    let assert Ok(asserted_89) =
      {
        let assert Ok(asserted_90) =
          {
            let assert Ok(asserted_91) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_91
          }
          |> sequence.insert(1, "d")
        asserted_90
      }
      |> sequence.insert_many(1, ["b", "c"])
    asserted_89
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "b", "c", "d"] }
  }
}

pub fn insert_many_empty_list_is_noop_test() {
  let base = {
    let assert Ok(asserted_88) =
      sequence.new(rid("A")) |> sequence.insert(0, "a")
    asserted_88
  }
  {
    let assert Ok(asserted_87) =
      base
      |> sequence.insert_many(1, [])
    asserted_87
  }
  |> fn(actual) {
    assert actual == { base }
  }
}

pub fn try_insert_many_negative_index_returns_error_test() {
  sequence.new(rid("A"))
  |> sequence.insert_many_with_delta(-1, ["x"])
  |> fn(actual) {
    assert actual == { Error(sequence.IndexOutOfBounds(index: -1, length: 0)) }
  }
}

pub fn try_insert_many_past_end_returns_error_test() {
  {
    let assert Ok(asserted_86) =
      sequence.new(rid("A"))
      |> sequence.insert(0, "a")
    asserted_86
  }
  |> sequence.insert_many_with_delta(2, ["x"])
  |> fn(actual) {
    assert actual == { Error(sequence.IndexOutOfBounds(index: 2, length: 1)) }
  }
}

pub fn insert_many_delta_merges_to_direct_state_test() {
  // The batched delta applied via merge on a peer must structurally equal the
  // directly-updated state — the same invariant single inserts uphold.
  let base = {
    let assert Ok(asserted_84) =
      {
        let assert Ok(asserted_85) =
          sequence.new(rid("A"))
          |> sequence.insert(0, "a")
        asserted_85
      }
      |> sequence.insert(1, "d")
    asserted_84
  }
  let #(direct, delta) = {
    let assert Ok(asserted_83) =
      sequence.insert_many_with_delta(base, 1, ["b", "c"])
    asserted_83
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { direct }
  }
}

pub fn insert_many_equivalent_to_looped_inserts_test() {
  // A single batched insert must produce a state structurally identical to
  // inserting the same values one at a time.
  let looped = {
    let assert Ok(asserted_79) =
      {
        let assert Ok(asserted_80) =
          {
            let assert Ok(asserted_81) =
              {
                let assert Ok(asserted_82) =
                  sequence.new(rid("A"))
                  |> sequence.insert(0, "a")
                asserted_82
              }
              |> sequence.insert(1, "d")
            asserted_81
          }
          |> sequence.insert(1, "b")
        asserted_80
      }
      |> sequence.insert(2, "c")
    asserted_79
  }
  let batched = {
    let assert Ok(asserted_76) =
      {
        let assert Ok(asserted_77) =
          {
            let assert Ok(asserted_78) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_78
          }
          |> sequence.insert(1, "d")
        asserted_77
      }
      |> sequence.insert_many(1, ["b", "c"])
    asserted_76
  }

  batched
  |> fn(actual) {
    assert actual == { looped }
  }
}

pub fn insert_many_delta_merges_after_tombstone_test() {
  // A batched insert whose position is preceded by tombstones must still
  // reconcile structurally with merge, mirroring the single-insert regression.
  let base = {
    let assert Ok(asserted_73) =
      {
        let assert Ok(asserted_74) =
          {
            let assert Ok(asserted_75) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_75
          }
          |> sequence.insert(1, "b")
        asserted_74
      }
      |> sequence.delete(0)
    asserted_73
  }
  let #(direct, delta) = {
    let assert Ok(asserted_72) =
      sequence.insert_many_with_delta(base, 0, ["x", "y"])
    asserted_72
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { direct }
  }
  sequence.values(direct)
  |> fn(actual) {
    assert actual == { ["x", "y", "b"] }
  }
}

pub fn insert_after_move_delta_merges_to_direct_state_test() {
  // With a live move record present the fast path falls back to a full
  // rebuild; the delta must still reconcile structurally with merge.
  let base = {
    let assert Ok(asserted_68) =
      {
        let assert Ok(asserted_69) =
          {
            let assert Ok(asserted_70) =
              {
                let assert Ok(asserted_71) =
                  sequence.new(rid("A"))
                  |> sequence.insert(0, "a")
                asserted_71
              }
              |> sequence.insert(1, "b")
            asserted_70
          }
          |> sequence.insert(2, "c")
        asserted_69
      }
      |> sequence.move(0, 2)
    asserted_68
  }
  let #(direct, delta) = {
    let assert Ok(asserted_67) = sequence.insert_with_delta(base, 1, "x")
    asserted_67
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { direct }
  }
  sequence.values(direct)
  |> fn(actual) {
    assert actual == { ["b", "x", "c", "a"] }
  }
}

pub fn insert_many_after_move_delta_merges_to_direct_state_test() {
  let base = {
    let assert Ok(asserted_63) =
      {
        let assert Ok(asserted_64) =
          {
            let assert Ok(asserted_65) =
              {
                let assert Ok(asserted_66) =
                  sequence.new(rid("A"))
                  |> sequence.insert(0, "a")
                asserted_66
              }
              |> sequence.insert(1, "b")
            asserted_65
          }
          |> sequence.insert(2, "c")
        asserted_64
      }
      |> sequence.move(0, 2)
    asserted_63
  }
  let #(direct, delta) = {
    let assert Ok(asserted_62) =
      sequence.insert_many_with_delta(base, 1, ["x", "y"])
    asserted_62
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { direct }
  }
  sequence.values(direct)
  |> fn(actual) {
    assert actual == { ["b", "x", "y", "c", "a"] }
  }
}

pub fn move_reorders_visible_item_test() {
  {
    let assert Ok(asserted_58) =
      {
        let assert Ok(asserted_59) =
          {
            let assert Ok(asserted_60) =
              {
                let assert Ok(asserted_61) =
                  sequence.new(rid("A"))
                  |> sequence.insert(0, "a")
                asserted_61
              }
              |> sequence.insert(1, "b")
            asserted_60
          }
          |> sequence.insert(2, "c")
        asserted_59
      }
      |> sequence.move(0, 2)
    asserted_58
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["b", "c", "a"] }
  }
}

pub fn try_move_from_index_out_of_bounds_test() {
  {
    let assert Ok(asserted_57) =
      sequence.new(rid("A"))
      |> sequence.insert(0, "a")
    asserted_57
  }
  |> sequence.move_with_delta(1, 0)
  |> fn(actual) {
    assert actual
      == { Error(sequence.MoveFromIndexOutOfBounds(index: 1, length: 1)) }
  }
}

pub fn try_move_to_index_out_of_bounds_test() {
  {
    let assert Ok(asserted_56) =
      sequence.new(rid("A"))
      |> sequence.insert(0, "a")
    asserted_56
  }
  |> sequence.move_with_delta(0, 2)
  |> fn(actual) {
    assert actual
      == {
        Error(sequence.MoveToIndexOutOfBounds(index: 2, length_after_removal: 0))
      }
  }
}

pub fn move_delta_merges_to_direct_state_test() {
  let base = {
    let assert Ok(asserted_53) =
      {
        let assert Ok(asserted_54) =
          {
            let assert Ok(asserted_55) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_55
          }
          |> sequence.insert(1, "b")
        asserted_54
      }
      |> sequence.insert(2, "c")
    asserted_53
  }
  let #(direct, delta) = {
    let assert Ok(asserted_52) = sequence.move_with_delta(base, 0, 2)
    asserted_52
  }

  sequence.merge(base, delta, rid("A"))
  |> fn(actual) {
    assert actual == { direct }
  }
}

pub fn repeated_move_delta_is_idempotent_test() {
  let base = {
    let assert Ok(asserted_49) =
      {
        let assert Ok(asserted_50) =
          {
            let assert Ok(asserted_51) =
              sequence.new(rid("A"))
              |> sequence.insert(0, "a")
            asserted_51
          }
          |> sequence.insert(1, "b")
        asserted_50
      }
      |> sequence.insert(2, "c")
    asserted_49
  }
  let #(direct, delta) = {
    let assert Ok(asserted_48) = sequence.move_with_delta(base, 0, 2)
    asserted_48
  }

  sequence.merge(sequence.merge(base, delta, rid("A")), delta, rid("A"))
  |> fn(actual) {
    assert actual == { direct }
  }
}

pub fn concurrent_moves_of_same_item_converge_test() {
  let base = {
    let assert Ok(asserted_44) =
      {
        let assert Ok(asserted_45) =
          {
            let assert Ok(asserted_46) =
              {
                let assert Ok(asserted_47) =
                  sequence.new(rid("base"))
                  |> sequence.insert(0, "a")
                asserted_47
              }
              |> sequence.insert(1, "b")
            asserted_46
          }
          |> sequence.insert(2, "c")
        asserted_45
      }
      |> sequence.insert(3, "d")
    asserted_44
  }
  let alice = {
    let assert Ok(asserted_43) =
      sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
      |> sequence.move(1, 0)
    asserted_43
  }
  let bob = {
    let assert Ok(asserted_42) =
      sequence.merge(sequence.new(rid("bob")), base, rid("bob"))
      |> sequence.move(1, 2)
    asserted_42
  }

  let ab = sequence.merge(alice, bob, rid("A")) |> sequence.values()
  let ba = sequence.merge(bob, alice, rid("A")) |> sequence.values()

  ab
  |> fn(actual) {
    assert actual == { ba }
  }
  ab
  |> fn(actual) {
    assert actual == { ["a", "c", "b", "d"] }
  }
}

pub fn unicode_order_competing_moves_of_same_item_test() {
  let base = {
    let assert Ok(asserted_41) =
      sequence.new(rid("base"))
      |> sequence.insert_many(0, ["a", "b", "c", "d"])
    asserted_41
  }
  let #(bmp, bmp_delta) = {
    let assert Ok(asserted_40) =
      sequence.merge(sequence.new(rid("\u{e000}")), base, rid("\u{e000}"))
      |> sequence.move_with_delta(1, 0)
    asserted_40
  }
  let #(supplementary, supplementary_delta) = {
    let assert Ok(asserted_39) =
      sequence.merge(sequence.new(rid("\u{10000}")), base, rid("\u{10000}"))
      |> sequence.move_with_delta(1, 2)
    asserted_39
  }

  sequence.values(bmp)
  |> fn(actual) {
    assert actual == { ["b", "a", "c", "d"] }
  }
  sequence.values(supplementary)
  |> fn(actual) {
    assert actual == { ["a", "c", "b", "d"] }
  }
  let move_counters =
    decode.at(
      ["state", "segments"],
      decode.list(decode.at(["move", "op_id", "counter"], decode.int)),
    )
  list.each([bmp_delta, supplementary_delta], fn(delta) {
    sequence.to_json(delta, json.string)
    |> json.to_string()
    |> json.parse(move_counters)
    |> fn(actual) {
      assert actual == { Ok([5]) }
    }
  })

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
  ])
  sequence.merge(pair.0, pair.1, rid("observer"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "c", "b", "d"] }
  }
}

pub fn unicode_order_different_item_moves_into_same_gap_test() {
  let base = {
    let assert Ok(asserted_38) =
      sequence.new(rid("base"))
      |> sequence.insert_many(0, ["L", "R", "b", "s"])
    asserted_38
  }
  let #(bmp, bmp_delta) = {
    let assert Ok(asserted_37) =
      sequence.merge(sequence.new(rid("\u{e000}")), base, rid("\u{e000}"))
      |> sequence.move_with_delta(2, 1)
    asserted_37
  }
  let #(supplementary, supplementary_delta) = {
    let assert Ok(asserted_36) =
      sequence.merge(sequence.new(rid("\u{10000}")), base, rid("\u{10000}"))
      |> sequence.move_with_delta(3, 1)
    asserted_36
  }

  sequence.values(bmp)
  |> fn(actual) {
    assert actual == { ["L", "b", "R", "s"] }
  }
  sequence.values(supplementary)
  |> fn(actual) {
    assert actual == { ["L", "s", "R", "b"] }
  }
  let move_counters =
    decode.at(
      ["state", "segments"],
      decode.list(decode.at(["move", "op_id", "counter"], decode.int)),
    )
  list.each([bmp_delta, supplementary_delta], fn(delta) {
    sequence.to_json(delta, json.string)
    |> json.to_string()
    |> json.parse(move_counters)
    |> fn(actual) {
      assert actual == { Ok([5]) }
    }
  })

  use pair <- list.each([
    #(bmp, supplementary),
    #(supplementary, bmp),
    #(bmp, supplementary_delta),
    #(supplementary, bmp_delta),
  ])
  sequence.merge(pair.0, pair.1, rid("observer"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["L", "b", "s", "R"] }
  }
}

pub fn causal_later_move_wins_test() {
  let base = {
    let assert Ok(asserted_32) =
      {
        let assert Ok(asserted_33) =
          {
            let assert Ok(asserted_34) =
              {
                let assert Ok(asserted_35) =
                  sequence.new(rid("base"))
                  |> sequence.insert(0, "a")
                asserted_35
              }
              |> sequence.insert(1, "b")
            asserted_34
          }
          |> sequence.insert(2, "c")
        asserted_33
      }
      |> sequence.insert(3, "d")
    asserted_32
  }
  let first = {
    let assert Ok(asserted_31) =
      sequence.merge(sequence.new(rid("alice")), base, rid("alice"))
      |> sequence.move(1, 0)
    asserted_31
  }
  let later = {
    let assert Ok(asserted_30) =
      sequence.merge(sequence.new(rid("bob")), first, rid("bob"))
      |> sequence.move(0, 3)
    asserted_30
  }

  sequence.merge(first, later, rid("A"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "c", "d", "b"] }
  }
}

pub fn concurrent_move_and_delete_delete_wins_test() {
  let base = {
    let assert Ok(asserted_27) =
      {
        let assert Ok(asserted_28) =
          {
            let assert Ok(asserted_29) =
              sequence.new(rid("base"))
              |> sequence.insert(0, "a")
            asserted_29
          }
          |> sequence.insert(1, "b")
        asserted_28
      }
      |> sequence.insert(2, "c")
    asserted_27
  }
  let moved = {
    let assert Ok(asserted_26) =
      sequence.merge(sequence.new(rid("mover")), base, rid("mover"))
      |> sequence.move(1, 0)
    asserted_26
  }
  let deleted = {
    let assert Ok(asserted_25) =
      sequence.merge(sequence.new(rid("deleter")), base, rid("deleter"))
      |> sequence.delete(1)
    asserted_25
  }

  sequence.merge(moved, deleted, rid("A"))
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["a", "c"] }
  }
}

pub fn move_after_descendant_does_not_drop_items_test() {
  let base = {
    let assert Ok(asserted_22) =
      {
        let assert Ok(asserted_23) =
          {
            let assert Ok(asserted_24) =
              sequence.new(rid("base"))
              |> sequence.insert(0, "a")
            asserted_24
          }
          |> sequence.insert(1, "b")
        asserted_23
      }
      |> sequence.insert(2, "c")
    asserted_22
  }
  let moved = {
    let assert Ok(asserted_21) = base |> sequence.move(0, 1)
    asserted_21
  }

  moved
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["b", "a", "c"] }
  }
  sequence.length(moved)
  |> fn(actual) {
    assert actual == { 3 }
  }
}

pub fn merge_uses_explicit_identity_when_delta_is_first_test() {
  // Reversing delta application must not give A the sender's identity.
  let base = {
    let assert Ok(asserted_20) =
      sequence.new(rid("A")) |> sequence.insert(0, "a")
    asserted_20
  }
  let #(b_state, b_delta) = {
    let assert Ok(asserted_19) =
      sequence.merge(sequence.new(rid("B")), base, rid("B"))
      |> sequence.insert_with_delta(1, "b")
    asserted_19
  }

  let a_state = {
    let assert Ok(asserted_18) =
      sequence.merge(b_delta, base, rid("A"))
      |> sequence.insert(2, "x")
    asserted_18
  }
  let b_state = {
    let assert Ok(asserted_17) = sequence.insert(b_state, 2, "c")
    asserted_17
  }

  sequence.merge(a_state, b_state, rid("A"))
  |> sequence.length()
  |> fn(actual) {
    assert actual == { 4 }
  }
}

pub fn merge_as_keeps_local_identity_whatever_the_argument_order_test() {
  let base = {
    let assert Ok(asserted_16) =
      sequence.new(rid("A")) |> sequence.insert(0, "a")
    asserted_16
  }
  let #(b_state, b_delta) = {
    let assert Ok(asserted_15) =
      sequence.merge(sequence.new(rid("B")), base, rid("B"))
      |> sequence.insert_with_delta(1, "b")
    asserted_15
  }

  // The alias has the same explicit-identity contract as canonical merge.
  let a_state = {
    let assert Ok(asserted_14) =
      sequence.merge_as(b_delta, base, rid("A"))
      |> sequence.insert(2, "x")
    asserted_14
  }
  let b_state = {
    let assert Ok(asserted_13) = sequence.insert(b_state, 2, "c")
    asserted_13
  }

  sequence.merge(a_state, b_state, rid("A"))
  |> sequence.length()
  |> fn(actual) {
    assert actual == { 4 }
  }
}

pub fn merge_as_is_argument_order_independent_test() {
  let base = {
    let assert Ok(asserted_12) =
      sequence.new(rid("A")) |> sequence.insert(0, "a")
    asserted_12
  }
  let #(_, b_delta) = {
    let assert Ok(asserted_11) =
      sequence.merge(sequence.new(rid("B")), base, rid("B"))
      |> sequence.insert_with_delta(1, "b")
    asserted_11
  }

  sequence.merge_as(base, b_delta, rid("A"))
  |> fn(actual) {
    assert actual == { sequence.merge_as(b_delta, base, rid("A")) }
  }
}

pub fn co_gap_movers_stack_in_op_order_across_resolution_paths_test() {
  // Three concurrent moves land in the same gap (between "L" and "R") but
  // resolve differently: the ones anchored on the later-moved "e" lose their
  // right boundary (it is itself a mover, stripped for this pass) and fall
  // back to the gap's left anchor, while the one anchored on "R" keeps its
  // right boundary. Whichever path each takes, they must stack left to right
  // in op order.
  let base = {
    let assert Ok(asserted_5) =
      {
        let assert Ok(asserted_6) =
          {
            let assert Ok(asserted_7) =
              {
                let assert Ok(asserted_8) =
                  {
                    let assert Ok(asserted_9) =
                      {
                        let assert Ok(asserted_10) =
                          sequence.new(rid("Z"))
                          |> sequence.insert(0, "L")
                        asserted_10
                      }
                      |> sequence.insert(1, "e")
                    asserted_9
                  }
                  |> sequence.insert(2, "R")
                asserted_8
              }
              |> sequence.insert(3, "c")
            asserted_7
          }
          |> sequence.insert(4, "d")
        asserted_6
      }
      |> sequence.insert(5, "b")
    asserted_5
  }

  // All three moves get the same counter, so replica id breaks the tie:
  // A ("c") < B ("d") < C ("b").
  let a = {
    let assert Ok(asserted_4) =
      sequence.merge(sequence.new(rid("A")), base, rid("A"))
      |> sequence.move(3, 1)
    asserted_4
  }
  let b = {
    let assert Ok(asserted_3) =
      sequence.merge(sequence.new(rid("B")), base, rid("B"))
      |> sequence.move(4, 2)
    asserted_3
  }
  let c = {
    let assert Ok(asserted_2) =
      sequence.merge(sequence.new(rid("C")), base, rid("C"))
      |> sequence.move(5, 1)
    asserted_2
  }
  {
    let assert Ok(asserted_1) =
      // Moving "e" last turns it into a mover, so it is no longer a usable right
      // boundary for the moves that anchored on it.
      sequence.merge(sequence.merge(a, b, rid("A")), c, rid("A"))
      |> sequence.move(3, 5)
    asserted_1
  }
  |> sequence.values()
  |> fn(actual) {
    assert actual == { ["L", "c", "d", "b", "R", "e"] }
  }
}
