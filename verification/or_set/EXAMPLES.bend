import Base
import ./MODEL.bend as Model

def original() -> Model.State:
  Model.Snapshot{0n, 1n, [Model.Live{0n, Model.Tag{0n, 0n}}], [], []}

def stable_live() -> Model.State:
  Model.Snapshot{0n, 1n, [Model.Live{0n, Model.Tag{0n, 0n}}], [], [Model.Clock{0n, 1n}]}

def removed() -> Model.State:
  Model.Snapshot{1n, 1n, [], [Model.Tag{0n, 0n}], []}

def pruned_removal() -> Model.State:
  Model.Snapshot{0n, 1n, [], [], [Model.Clock{0n, 1n}]}

def covered_tombstone() -> Model.State:
  Model.Snapshot{0n, 1n, [], [Model.Tag{0n, 0n}], [Model.Clock{0n, 1n}]}

def empty() -> Model.State:
  Model.Snapshot{2n, 0n, [], [], []}

def fresh_delta() -> Model.State:
  Model.Snapshot{0n, 2n, [Model.Live{0n, Model.Tag{0n, 1n}}], [], []}

def fresh_remove_delta() -> Model.State:
  Model.Snapshot{0n, 2n, [], [Model.Tag{0n, 1n}], []}

law reject_zombie:
  {Model.observe(Model.merge(pruned_removal(), original()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, False{}, True{}} : Model.Point} &
  {Model.observe(Model.merge(original(), pruned_removal()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, False{}, True{}} : Model.Point}

def reject_zombie():
  ({==}, {==})

law retain_stable_live_tag:
  {Model.observe(Model.merge(stable_live(), empty()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{True{}, False{}, True{}} : Model.Point} &
  {Model.observe(Model.merge(empty(), stable_live()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{True{}, False{}, True{}} : Model.Point}

def retain_stable_live_tag():
  ({==}, {==})

# The sparse removed snapshot is also the remove delta for this one-tag case.
law later_removal:
  {Model.observe(Model.merge(stable_live(), removed()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, False{}, True{}} : Model.Point} &
  {Model.observe(Model.merge(removed(), stable_live()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, False{}, True{}} : Model.Point}

def later_removal():
  ({==}, {==})

law stale_replay:
  {Model.observe(Model.merge(Model.merge(stable_live(), removed()), original()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, False{}, True{}} : Model.Point} &
  {Model.observe(Model.merge(original(), Model.merge(removed(), stable_live())), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, False{}, True{}} : Model.Point}

def stale_replay():
  ({==}, {==})

law normalize_covered_tombstone:
  {Model.observe(covered_tombstone(), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, True{}, True{}} : Model.Point} &
  {Model.observe(Model.merge(covered_tombstone(), covered_tombstone()), 0n, Model.Tag{0n, 0n}) ==
    Model.Point{False{}, False{}, True{}} : Model.Point} &
  {Model.knowledge(Model.observe(covered_tombstone(), 0n, Model.Tag{0n, 0n})) ==
    Model.knowledge(Model.observe(Model.merge(covered_tombstone(), covered_tombstone()), 0n, Model.Tag{0n, 0n})) : Model.Knowledge}

def normalize_covered_tombstone():
  ({==}, {==}, {==})

law fresh_delta_above_frontier:
  {Model.observe(Model.merge(Model.merge(stable_live(), removed()), fresh_delta()), 0n, Model.Tag{0n, 1n}) ==
    Model.Point{True{}, False{}, False{}} : Model.Point} &
  {Model.observe(Model.merge(stable_live(), Model.merge(removed(), fresh_delta())), 0n, Model.Tag{0n, 1n}) ==
    Model.Point{True{}, False{}, False{}} : Model.Point}

def fresh_delta_above_frontier():
  ({==}, {==})

law retain_remove_delta_above_frontier:
  {Model.observe(Model.merge(pruned_removal(), fresh_remove_delta()), 0n, Model.Tag{0n, 1n}) ==
    Model.Point{False{}, True{}, False{}} : Model.Point} &
  {Model.observe(Model.merge(Model.merge(pruned_removal(), fresh_remove_delta()), fresh_delta()), 0n, Model.Tag{0n, 1n}) ==
    Model.Point{False{}, True{}, False{}} : Model.Point}

def retain_remove_delta_above_frontier():
  ({==}, {==})

law concurrent_add_wins:
  {Model.observe(Model.merge(removed(),
    Model.Snapshot{1n, 1n, [Model.Live{0n, Model.Tag{1n, 0n}}], [], []}), 0n, Model.Tag{1n, 0n}) ==
    Model.Point{True{}, False{}, False{}} : Model.Point}

def concurrent_add_wins():
  {==}

law counter_uses_other_replica_frontier:
  {Model.counter(Model.merge(Model.Snapshot{0n, 1n, [], [], [Model.Clock{9n, 7n}]},
    Model.Snapshot{1n, 5n, [], [], []})) == 7n : Nat}

def counter_uses_other_replica_frontier():
  {==}
