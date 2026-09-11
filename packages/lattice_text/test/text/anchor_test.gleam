import gleam/json
import lattice_core/replica_id
import lattice_sequence/sequence.{After, Before}
import lattice_text/text

fn rid(id: String) {
  replica_id.new(id)
}

fn doc(value: String) {
  text.new(rid("A"))
  |> text.insert(0, value)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
}

pub fn start_and_end_anchors_resolve_test() {
  let d = doc("abc")

  text.resolve_anchor(d, text.start_anchor())
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 0
  }
  text.resolve_anchor(d, text.end_anchor())
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 3
  }
  text.resolve_anchor(
    text.append(d, "de")
      |> fn(result) {
        let assert Ok(value) = result
        value
      },
    text.end_anchor(),
  )
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 5
  }
}

pub fn anchor_shifts_with_insert_before_it_test() {
  let d = doc("hello")
  let anchor =
    text.anchor_at(d, 5, After)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.resolve_anchor(
    text.insert(d, 0, "say ")
      |> fn(result) {
        let assert Ok(value) = result
        value
      },
    anchor,
  )
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 9
  }
}

pub fn try_anchor_at_out_of_bounds_returns_error_test() {
  doc("abc")
  |> text.anchor_at(4, Before)
  |> fn(actual) {
    assert actual == Error(sequence.AnchorIndexOutOfBounds(index: 4, length: 3))
  }
}

pub fn try_resolve_anchor_unknown_target_returns_error_test() {
  let alice = doc("abc")
  let bob =
    text.merge(text.new(rid("B")), alice, rid("B"))
    |> text.insert(1, "x")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let anchor =
    text.anchor_at(bob, 1, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.resolve_anchor(alice, anchor)
  |> fn(actual) {
    assert actual == Error(sequence.UnknownAnchorTarget)
  }
  text.resolve_anchor(text.merge(alice, bob, rid("A")), anchor)
  |> fn(actual) {
    assert actual == Ok(1)
  }
}

pub fn anchor_counts_graphemes_not_codepoints_test() {
  // "👍" and "é" are single graphemes.
  let d = doc("a👍é")
  let anchor =
    text.anchor_at(d, 3, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.resolve_anchor(d, anchor)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 3
  }
  text.resolve_anchor(
    text.insert(d, 0, "🎉🎉")
      |> fn(result) {
        let assert Ok(value) = result
        value
      },
    anchor,
  )
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 5
  }
}

pub fn multi_grapheme_insert_at_gap_respects_bias_test() {
  let d = doc("ab")
  let before =
    text.anchor_at(d, 1, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let after =
    text.anchor_at(d, 1, After)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let updated =
    text.insert(d, 1, "👍👍👍")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.resolve_anchor(updated, before)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 4
  }
  text.resolve_anchor(updated, after)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 1
  }
}

pub fn delete_range_spanning_anchor_collapses_it_test() {
  let d = doc("abcdef")
  let anchor =
    text.anchor_at(d, 3, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let updated =
    text.delete_range(d, 1, 5)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  // "d" was deleted; the anchor collapses to the gap left behind.
  text.resolve_anchor(updated, anchor)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 1
  }
}

pub fn replace_range_spanning_anchor_test() {
  let d = doc("abcdef")
  let anchor =
    text.anchor_at(d, 3, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let updated =
    text.replace_range(d, 1, 5, "XY")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  // The anchored grapheme "d" is gone; the anchor lands inside the
  // replacement region, still within bounds.
  let resolved =
    text.resolve_anchor(updated, anchor)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  assert resolved >= 0 && resolved <= text.length(updated)
}

pub fn delete_range_before_anchor_shifts_it_left_test() {
  let d = doc("abcdef")
  let anchor =
    text.anchor_at(d, 4, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.resolve_anchor(
    text.delete_range(d, 0, 3)
      |> fn(result) {
        let assert Ok(value) = result
        value
      },
    anchor,
  )
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 1
  }
}

pub fn anchor_survives_merge_of_concurrent_edits_test() {
  let base = doc("abc")
  let anchor =
    text.anchor_at(base, 2, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let alice =
    text.merge(text.new(rid("alice")), base, rid("alice"))
    |> text.insert(0, "x")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let bob =
    text.merge(text.new(rid("bob")), base, rid("bob"))
    |> text.delete(0)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let merged = text.merge(alice, bob, rid("A"))

  // Wherever "c" ends up after the merge, the anchor still points at it.
  let resolved =
    text.resolve_anchor(merged, anchor)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  text.substring(merged, resolved, resolved + 1)
  |> fn(actual) {
    assert actual == "c"
  }
}

pub fn unicode_order_anchor_before_concurrent_first_insert_test() {
  let bmp =
    text.new(rid("\u{e000}"))
    |> text.insert(0, "b")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let supplementary =
    text.new(rid("\u{10000}"))
    |> text.insert(0, "s")
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let anchor =
    text.anchor_at(bmp, 0, Before)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }

  text.resolve_anchor(text.merge(bmp, supplementary, rid("observer")), anchor)
  |> fn(actual) {
    assert actual == Ok(0)
  }
  text.resolve_anchor(text.merge(supplementary, bmp, rid("observer")), anchor)
  |> fn(actual) {
    assert actual == Ok(0)
  }
}

pub fn anchor_json_round_trip_test() {
  let d = doc("abc")
  let anchor =
    text.anchor_at(d, 2, After)
    |> fn(result) {
      let assert Ok(value) = result
      value
    }
  let assert Ok(decoded) =
    text.anchor_from_json(json.to_string(text.anchor_to_json(anchor)))

  text.resolve_anchor(d, decoded)
  |> fn(result) {
    let assert Ok(value) = result
    value
  }
  |> fn(actual) {
    assert actual == 2
  }
  decoded
  |> fn(actual) {
    assert actual == anchor
  }
}
