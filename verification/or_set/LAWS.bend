import Base
import ./MODEL.bend as Model

law commutative:
  for +a: Model.State
  for +b: Model.State
  Model.same(Model.merge(a, b), Model.merge(b, a))

law associative:
  for +a: Model.State
  for +b: Model.State
  for +c: Model.State
  Model.same(Model.merge(Model.merge(a, b), c), Model.merge(a, Model.merge(b, c)))

law idempotent:
  for +a: Model.State
  Model.same(Model.merge(a, a), a)

law closure:
  for +a: Model.State
  for +b: Model.State
  Model.valid(Model.merge(a, b))

law normalization_preserves_live:
  for +a: Model.State
  for valid: Model.valid(a)
  Model.same_live(Model.merge(a, a), a)

law congruence:
  for +a: Model.State
  for +b: Model.State
  for +c: Model.State
  for +d: Model.State
  for first: Model.same(a, c)
  for second: Model.same(b, d)
  Model.same(Model.merge(a, b), Model.merge(c, d))

law same_preserves_live:
  for +a: Model.State
  for +b: Model.State
  for valid_a: Model.valid(a)
  for valid_b: Model.valid(b)
  for equal: Model.same(a, b)
  Model.same_live(a, b)

law normalization_preserves_knowledge:
  for a: Model.State
  for element: Nat
  for tag: Model.Tag
  {Model.knowledge(Model.normalize_point(Model.observe(a, element, tag))) ==
    Model.knowledge(Model.observe(a, element, tag)) : Model.Knowledge}

law normalization_retains_tombstones:
  for +a: Model.State
  for +element: Nat
  for +tag: Model.Tag
  {Model.normalized_tombstone(Model.knowledge(Model.observe(a, element, tag))) ==
    (Model.point_tombstone(Model.observe(a, element, tag)) && Bool.not(Model.point_covered(Model.observe(a, element, tag)))) : Bool}

law counter_covers_pruning:
  for +a: Model.State
  {Nat.is_ge(Model.counter(a), Model.pruning_floor(a)) == True{} : Bool}

law counter_step:
  for +a: Model.State
  for +b: Model.State
  {Model.counter(Model.merge(a, b)) ==
    Nat.max(Nat.max(Model.counter(a), Model.counter(b)), Model.pruning_floor(Model.merge(a, b))) : Nat}

law frontier_coverage:
  for +a: Model.State
  for +element: Nat
  for +replica: Nat
  for +previous: Nat
  {Model.point_covered(Model.observe(a, element, Model.Tag{replica, previous})) ==
    Nat.is_ge(Model.frontier(a, replica), 1n+previous) : Bool}

law keeps_left_writer:
  for +a: Model.State
  for b: Model.State
  {Model.writer(Model.merge(a, b)) == Model.writer(a) : Nat}
