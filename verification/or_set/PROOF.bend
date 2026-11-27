import Base
import ./MODEL.bend as Model
import ./LAWS.bend as Laws
import ./EXAMPLES.bend as Examples

def or_commutative(+a: Bool, +b: Bool) -> {a || b == b || a : Bool}:
  match a b:
    case False{} False{}:
      {==}
    case False{} True{}:
      {==}
    case True{} False{}:
      {==}
    case True{} True{}:
      {==}

def or_associative(+a: Bool, +b: Bool, +c: Bool) -> {(a || b) || c == a || (b || c) : Bool}:
  match a b c:
    case False{} False{} False{}:
      {==}
    case False{} False{} True{}:
      {==}
    case False{} True{} False{}:
      {==}
    case False{} True{} True{}:
      {==}
    case True{} False{} False{}:
      {==}
    case True{} False{} True{}:
      {==}
    case True{} True{} False{}:
      {==}
    case True{} True{} True{}:
      {==}

def or_idempotent(+a: Bool) -> {a || a == a : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def max_zero(+a: Nat) -> {Nat.max(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      {==}

def max_commutative(+a: Nat, +b: Nat) -> {Nat.max(a, b) == Nat.max(b, a) : Nat}:
  match a b:
    case 0n _:
      Equal.sym(Nat, Nat.max(b, 0n), b, max_zero(b))
    case 1n+ap 0n:
      {==}
    case 1n+ap 1n+bp:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.max(ap, bp), Nat.max(bp, ap), max_commutative(ap, bp))

def max_associative(+a: Nat, +b: Nat, +c: Nat) -> {Nat.max(Nat.max(a, b), c) == Nat.max(a, Nat.max(b, c)) : Nat}:
  match a b c:
    case 0n _ _:
      {==}
    case 1n+ap 0n _:
      {==}
    case 1n+ap 1n+bp 0n:
      %max_zero(Nat.max(a, b)) : {_ == Nat.max(a, Nat.max(b, 0n)) : Nat}
      %max_zero(b) : {Nat.max(a, b) == Nat.max(a, _) : Nat}
      {==}
    case 1n+ap 1n+bp 1n+cp:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.max(Nat.max(ap, bp), cp), Nat.max(ap, Nat.max(bp, cp)), max_associative(ap, bp, cp))

def max_idempotent(+a: Nat) -> {Nat.max(a, a) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      Equal.cong(Nat, Nat, x => 1n+x, Nat.max(p, p), p, max_idempotent(p))

def knowledge_equal(-as: Bool, -ar: Bool, -ap: Bool, -bs: Bool, -br: Bool, -bp: Bool,
  seen: {as == bs : Bool}, removed: {ar == br : Bool}, covered: {ap == bp : Bool})
  -> {Model.Knowledge{as, ar, ap} == Model.Knowledge{bs, br, bp} : Model.Knowledge}:
  %seen : {Model.Knowledge{as, ar, ap} == Model.Knowledge{_, br, bp} : Model.Knowledge}
  %removed : {Model.Knowledge{as, ar, ap} == Model.Knowledge{as, _, bp} : Model.Knowledge}
  %covered : {Model.Knowledge{as, ar, ap} == Model.Knowledge{as, ar, _} : Model.Knowledge}
  {==}

def knowledge_commutative(+a: Model.Knowledge, +b: Model.Knowledge)
  -> {Model.join_knowledge(a, b) == Model.join_knowledge(b, a) : Model.Knowledge}:
  Model.Knowledge{+as, +ar, +ap} = a
  Model.Knowledge{+bs, +br, +bp} = b
  knowledge_equal(as || bs, ar || br, ap || bp, bs || as, br || ar, bp || ap,
    or_commutative(as, bs), or_commutative(ar, br), or_commutative(ap, bp))

def knowledge_associative(+a: Model.Knowledge, +b: Model.Knowledge, +c: Model.Knowledge)
  -> {Model.join_knowledge(Model.join_knowledge(a, b), c) == Model.join_knowledge(a, Model.join_knowledge(b, c)) : Model.Knowledge}:
  Model.Knowledge{+as, +ar, +ap} = a
  Model.Knowledge{+bs, +br, +bp} = b
  Model.Knowledge{+cs, +cr, +cp} = c
  knowledge_equal((as || bs) || cs, (ar || br) || cr, (ap || bp) || cp,
    as || (bs || cs), ar || (br || cr), ap || (bp || cp),
    or_associative(as, bs, cs), or_associative(ar, br, cr), or_associative(ap, bp, cp))

def knowledge_idempotent(+a: Model.Knowledge)
  -> {Model.join_knowledge(a, a) == a : Model.Knowledge}:
  Model.Knowledge{+seen, +removed, +covered} = a
  knowledge_equal(seen || seen, removed || removed, covered || covered,
    seen, removed, covered, or_idempotent(seen), or_idempotent(removed), or_idempotent(covered))

# Case analysis covers the complete per-tag Boolean domain, not bounded histories.
def point_merge_bits(+al: Bool, +at: Bool, +ap: Bool, +bl: Bool, +bt: Bool, +bp: Bool)
  -> {Model.knowledge(Model.join_point(Model.Point{al, at, ap}, Model.Point{bl, bt, bp})) ==
    Model.join_knowledge(Model.knowledge(Model.Point{al, at, ap}), Model.knowledge(Model.Point{bl, bt, bp})) : Model.Knowledge}:
  match al at ap bl bt bp:
    case False{} False{} False{} False{} False{} False{}:
      {==}
    case False{} False{} False{} False{} False{} True{}:
      {==}
    case False{} False{} False{} False{} True{} False{}:
      {==}
    case False{} False{} False{} False{} True{} True{}:
      {==}
    case False{} False{} False{} True{} False{} False{}:
      {==}
    case False{} False{} False{} True{} False{} True{}:
      {==}
    case False{} False{} False{} True{} True{} False{}:
      {==}
    case False{} False{} False{} True{} True{} True{}:
      {==}
    case False{} False{} True{} False{} False{} False{}:
      {==}
    case False{} False{} True{} False{} False{} True{}:
      {==}
    case False{} False{} True{} False{} True{} False{}:
      {==}
    case False{} False{} True{} False{} True{} True{}:
      {==}
    case False{} False{} True{} True{} False{} False{}:
      {==}
    case False{} False{} True{} True{} False{} True{}:
      {==}
    case False{} False{} True{} True{} True{} False{}:
      {==}
    case False{} False{} True{} True{} True{} True{}:
      {==}
    case False{} True{} False{} False{} False{} False{}:
      {==}
    case False{} True{} False{} False{} False{} True{}:
      {==}
    case False{} True{} False{} False{} True{} False{}:
      {==}
    case False{} True{} False{} False{} True{} True{}:
      {==}
    case False{} True{} False{} True{} False{} False{}:
      {==}
    case False{} True{} False{} True{} False{} True{}:
      {==}
    case False{} True{} False{} True{} True{} False{}:
      {==}
    case False{} True{} False{} True{} True{} True{}:
      {==}
    case False{} True{} True{} False{} False{} False{}:
      {==}
    case False{} True{} True{} False{} False{} True{}:
      {==}
    case False{} True{} True{} False{} True{} False{}:
      {==}
    case False{} True{} True{} False{} True{} True{}:
      {==}
    case False{} True{} True{} True{} False{} False{}:
      {==}
    case False{} True{} True{} True{} False{} True{}:
      {==}
    case False{} True{} True{} True{} True{} False{}:
      {==}
    case False{} True{} True{} True{} True{} True{}:
      {==}
    case True{} False{} False{} False{} False{} False{}:
      {==}
    case True{} False{} False{} False{} False{} True{}:
      {==}
    case True{} False{} False{} False{} True{} False{}:
      {==}
    case True{} False{} False{} False{} True{} True{}:
      {==}
    case True{} False{} False{} True{} False{} False{}:
      {==}
    case True{} False{} False{} True{} False{} True{}:
      {==}
    case True{} False{} False{} True{} True{} False{}:
      {==}
    case True{} False{} False{} True{} True{} True{}:
      {==}
    case True{} False{} True{} False{} False{} False{}:
      {==}
    case True{} False{} True{} False{} False{} True{}:
      {==}
    case True{} False{} True{} False{} True{} False{}:
      {==}
    case True{} False{} True{} False{} True{} True{}:
      {==}
    case True{} False{} True{} True{} False{} False{}:
      {==}
    case True{} False{} True{} True{} False{} True{}:
      {==}
    case True{} False{} True{} True{} True{} False{}:
      {==}
    case True{} False{} True{} True{} True{} True{}:
      {==}
    case True{} True{} False{} False{} False{} False{}:
      {==}
    case True{} True{} False{} False{} False{} True{}:
      {==}
    case True{} True{} False{} False{} True{} False{}:
      {==}
    case True{} True{} False{} False{} True{} True{}:
      {==}
    case True{} True{} False{} True{} False{} False{}:
      {==}
    case True{} True{} False{} True{} False{} True{}:
      {==}
    case True{} True{} False{} True{} True{} False{}:
      {==}
    case True{} True{} False{} True{} True{} True{}:
      {==}
    case True{} True{} True{} False{} False{} False{}:
      {==}
    case True{} True{} True{} False{} False{} True{}:
      {==}
    case True{} True{} True{} False{} True{} False{}:
      {==}
    case True{} True{} True{} False{} True{} True{}:
      {==}
    case True{} True{} True{} True{} False{} False{}:
      {==}
    case True{} True{} True{} True{} False{} True{}:
      {==}
    case True{} True{} True{} True{} True{} False{}:
      {==}
    case True{} True{} True{} True{} True{} True{}:
      {==}

def point_merge(+a: Model.Point, +b: Model.Point)
  -> {Model.knowledge(Model.join_point(a, b)) == Model.join_knowledge(Model.knowledge(a), Model.knowledge(b)) : Model.Knowledge}:
  Model.Point{al, at, ap} = a
  Model.Point{bl, bt, bp} = b
  point_merge_bits(al, at, ap, bl, bt, bp)

def point_commutative(+a: Model.Point, +b: Model.Point)
  -> {Model.knowledge(Model.join_point(a, b)) == Model.knowledge(Model.join_point(b, a)) : Model.Knowledge}:
  %Equal.sym(Model.Knowledge, Model.knowledge(Model.join_point(b, a)),
    Model.join_knowledge(Model.knowledge(b), Model.knowledge(a)), point_merge(b, a))
    : {Model.knowledge(Model.join_point(a, b)) == _ : Model.Knowledge}
  %knowledge_commutative(Model.knowledge(a), Model.knowledge(b))
    : {Model.knowledge(Model.join_point(a, b)) == _ : Model.Knowledge}
  point_merge(a, b)

def point_associative(+a: Model.Point, +b: Model.Point, +c: Model.Point)
  -> {Model.knowledge(Model.join_point(Model.join_point(a, b), c)) ==
    Model.knowledge(Model.join_point(a, Model.join_point(b, c))) : Model.Knowledge}:
  %Equal.sym(Model.Knowledge, Model.knowledge(Model.join_point(a, Model.join_point(b, c))),
    Model.join_knowledge(Model.knowledge(a), Model.knowledge(Model.join_point(b, c))),
    point_merge(a, Model.join_point(b, c)))
    : {Model.knowledge(Model.join_point(Model.join_point(a, b), c)) == _ : Model.Knowledge}
  %Equal.sym(Model.Knowledge, Model.knowledge(Model.join_point(b, c)),
    Model.join_knowledge(Model.knowledge(b), Model.knowledge(c)), point_merge(b, c))
    : {Model.knowledge(Model.join_point(Model.join_point(a, b), c)) ==
      Model.join_knowledge(Model.knowledge(a), _) : Model.Knowledge}
  %knowledge_associative(Model.knowledge(a), Model.knowledge(b), Model.knowledge(c))
    : {Model.knowledge(Model.join_point(Model.join_point(a, b), c)) == _ : Model.Knowledge}
  %point_merge(a, b)
    : {Model.knowledge(Model.join_point(Model.join_point(a, b), c)) ==
      Model.join_knowledge(_, Model.knowledge(c)) : Model.Knowledge}
  point_merge(Model.join_point(a, b), c)

def point_idempotent(+a: Model.Point)
  -> {Model.knowledge(Model.join_point(a, a)) == Model.knowledge(a) : Model.Knowledge}:
  Equal.trans(Model.Knowledge, Model.knowledge(Model.join_point(a, a)),
    Model.join_knowledge(Model.knowledge(a), Model.knowledge(a)), Model.knowledge(a),
    point_merge(a, a), knowledge_idempotent(Model.knowledge(a)))

def max_equal(-a: Nat, -b: Nat, -c: Nat, -d: Nat,
  first: {a == c : Nat}, second: {b == d : Nat})
  -> {Nat.max(a, b) == Nat.max(c, d) : Nat}:
  %first : {Nat.max(a, b) == Nat.max(_, d) : Nat}
  %second : {Nat.max(a, b) == Nat.max(a, _) : Nat}
  {==}

def max_swap_inside(+a: Nat, +b: Nat, +c: Nat)
  -> {Nat.max(a, Nat.max(b, c)) == Nat.max(b, Nat.max(a, c)) : Nat}:
  %max_associative(b, a, c) : {Nat.max(a, Nat.max(b, c)) == _ : Nat}
  %max_commutative(a, b) : {Nat.max(a, Nat.max(b, c)) == Nat.max(_, c) : Nat}
  Equal.sym(Nat, Nat.max(Nat.max(a, b), c), Nat.max(a, Nat.max(b, c)), max_associative(a, b, c))

def max_interchange(+a: Nat, +b: Nat, +c: Nat, +d: Nat)
  -> {Nat.max(Nat.max(a, b), Nat.max(c, d)) == Nat.max(Nat.max(a, c), Nat.max(b, d)) : Nat}:
  %Equal.sym(Nat, Nat.max(Nat.max(a, c), Nat.max(b, d)),
    Nat.max(a, Nat.max(c, Nat.max(b, d))), max_associative(a, c, Nat.max(b, d)))
    : {Nat.max(Nat.max(a, b), Nat.max(c, d)) == _ : Nat}
  %Equal.sym(Nat, Nat.max(c, Nat.max(b, d)), Nat.max(b, Nat.max(c, d)), max_swap_inside(c, b, d))
    : {Nat.max(Nat.max(a, b), Nat.max(c, d)) == Nat.max(a, _) : Nat}
  max_associative(a, b, Nat.max(c, d))

def max_absorb(+a: Nat, +b: Nat) -> {Nat.max(Nat.max(a, b), b) == Nat.max(a, b) : Nat}:
  %max_idempotent(b)
    : {Nat.max(Nat.max(a, b), b) == Nat.max(a, _) : Nat}
  max_associative(a, b, b)

def counter_step_bits(+a: Nat, +b: Nat, +p: Nat, +q: Nat)
  -> {Nat.max(Nat.max(a, b), Nat.max(p, q)) ==
    Nat.max(Nat.max(Nat.max(a, p), Nat.max(b, q)), Nat.max(p, q)) : Nat}:
  %Equal.sym(Nat, Nat.max(Nat.max(a, p), Nat.max(b, q)),
    Nat.max(Nat.max(a, b), Nat.max(p, q)), max_interchange(a, p, b, q))
    : {Nat.max(Nat.max(a, b), Nat.max(p, q)) == Nat.max(_, Nat.max(p, q)) : Nat}
  Equal.sym(Nat, Nat.max(Nat.max(Nat.max(a, b), Nat.max(p, q)), Nat.max(p, q)),
    Nat.max(Nat.max(a, b), Nat.max(p, q)), max_absorb(Nat.max(a, b), Nat.max(p, q)))

def Laws.counter_step(a, b):
  counter_step_bits(Model.allocation(a), Model.allocation(b), Model.pruning_floor(a), Model.pruning_floor(b))

def Laws.commutative(a, b):
  (+element => +tag => point_commutative(Model.observe(a, element, tag), Model.observe(b, element, tag)),
    +replica => max_commutative(Model.frontier(a, replica), Model.frontier(b, replica)),
    max_equal(Nat.max(Model.allocation(a), Model.allocation(b)),
      Nat.max(Model.pruning_floor(a), Model.pruning_floor(b)),
      Nat.max(Model.allocation(b), Model.allocation(a)),
      Nat.max(Model.pruning_floor(b), Model.pruning_floor(a)),
      max_commutative(Model.allocation(a), Model.allocation(b)),
      max_commutative(Model.pruning_floor(a), Model.pruning_floor(b))))

def Laws.associative(a, b, c):
  (+element => +tag => point_associative(Model.observe(a, element, tag), Model.observe(b, element, tag), Model.observe(c, element, tag)),
    +replica => max_associative(Model.frontier(a, replica), Model.frontier(b, replica), Model.frontier(c, replica)),
    max_equal(Nat.max(Nat.max(Model.allocation(a), Model.allocation(b)), Model.allocation(c)),
      Nat.max(Nat.max(Model.pruning_floor(a), Model.pruning_floor(b)), Model.pruning_floor(c)),
      Nat.max(Model.allocation(a), Nat.max(Model.allocation(b), Model.allocation(c))),
      Nat.max(Model.pruning_floor(a), Nat.max(Model.pruning_floor(b), Model.pruning_floor(c))),
      max_associative(Model.allocation(a), Model.allocation(b), Model.allocation(c)),
      max_associative(Model.pruning_floor(a), Model.pruning_floor(b), Model.pruning_floor(c))))

def Laws.idempotent(a):
  (+element => +tag => point_idempotent(Model.observe(a, element, tag)),
    +replica => max_idempotent(Model.frontier(a, replica)),
    max_equal(Nat.max(Model.allocation(a), Model.allocation(a)),
      Nat.max(Model.pruning_floor(a), Model.pruning_floor(a)),
      Model.allocation(a), Model.pruning_floor(a),
      max_idempotent(Model.allocation(a)), max_idempotent(Model.pruning_floor(a))))

def and_false(+a: Bool) -> {a && False{} == False{} : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def filtered_disjoint(+live: Bool, +removed: Bool, +zombies: Bool, +covered: Bool)
  -> {((live && Bool.not(removed) && Bool.not(zombies)) && (removed && Bool.not(covered))) == False{} : Bool}:
  match removed:
    case False{}:
      and_false((live && True{}) && Bool.not(zombies))
    case True{}:
      %Equal.sym(Bool, live && False{}, False{}, and_false(live))
        : {((_ && Bool.not(zombies)) && Bool.not(covered)) == False{} : Bool}
      {==}

def point_closure(+a: Model.Point, +b: Model.Point) -> Model.disjoint(Model.join_point(a, b)):
  Model.Point{+al, +at, +ap} = a
  Model.Point{+bl, +bt, +bp} = b
  filtered_disjoint(al || bl, at || bt, (ap && Bool.not(al)) || (bp && Bool.not(bl)), ap || bp)

def Laws.closure(a, b):
  +element => +tag => point_closure(Model.observe(a, element, tag), Model.observe(b, element, tag))

def point_live_self(+a: Model.Point, valid: Model.disjoint(a))
  -> {Model.point_live(Model.join_point(a, a)) == Model.point_live(a) : Bool}:
  Model.Point{+live, +tombstone, +covered} = a
  match live tombstone covered:
    case False{} False{} False{}:
      {==}
    case False{} False{} True{}:
      {==}
    case False{} True{} False{}:
      {==}
    case False{} True{} True{}:
      {==}
    case True{} False{} False{}:
      {==}
    case True{} False{} True{}:
      {==}
    case True{} True{} False{}:
      Equal.sym(Bool, True{}, False{}, valid)
    case True{} True{} True{}:
      Equal.sym(Bool, True{}, False{}, valid)

def Laws.normalization_preserves_live(a, valid):
  +element => +tag => point_live_self(Model.observe(a, element, tag), valid(element, tag))

def or_false(+a: Bool) -> {a || False{} == a : Bool}:
  match a:
    case False{}:
      {==}
    case True{}:
      {==}

def or_equal(-a: Bool, -b: Bool, -c: Bool, -d: Bool,
  first: {a == c : Bool}, second: {b == d : Bool}) -> {a || b == c || d : Bool}:
  %first : {a || b == _ || d : Bool}
  %second : {a || b == a || _ : Bool}
  {==}

def max_coverage(+a: Nat, +b: Nat, +c: Nat)
  -> {Nat.is_ge(Nat.max(a, b), c) == Nat.is_ge(a, c) || Nat.is_ge(b, c) : Bool}:
  match a b c:
    case 0n 0n 0n:
      {==}
    case 0n 0n 1n+cp:
      {==}
    case 0n 1n+bp 0n:
      {==}
    case 0n 1n+bp 1n+cp:
      {==}
    case 1n+ap 0n 0n:
      {==}
    case 1n+ap 0n 1n+cp:
      Equal.sym(Bool, Nat.is_ge(ap, cp) || False{}, Nat.is_ge(ap, cp), or_false(Nat.is_ge(ap, cp)))
    case 1n+ap 1n+bp 0n:
      {==}
    case 1n+ap 1n+bp 1n+cp:
      max_coverage(ap, bp, cp)

def point_cover_join(+a: Model.Point, +b: Model.Point)
  -> {Model.point_covered(Model.join_point(a, b)) == Model.point_covered(a) || Model.point_covered(b) : Bool}:
  Model.Point{al, at, ap} = a
  Model.Point{bl, bt, bp} = b
  {==}

def covered_point(+a: Model.State, +element: Nat, +replica: Nat, +previous: Nat)
  -> {Model.point_covered(Model.observe(a, element, Model.Tag{replica, previous})) ==
    Nat.is_ge(Model.frontier(a, replica), 1n+previous) : Bool}:
  match a:
    case Model.Snapshot{writer, allocation, entries, tombstones, clocks}:
      {==}
    case Model.Merged{+left, +right}:
      %Equal.sym(Bool, Nat.is_ge(Nat.max(Model.frontier(left, replica), Model.frontier(right, replica)), 1n+previous),
        Nat.is_ge(Model.frontier(left, replica), 1n+previous) || Nat.is_ge(Model.frontier(right, replica), 1n+previous),
        max_coverage(Model.frontier(left, replica), Model.frontier(right, replica), 1n+previous))
        : {Model.point_covered(Model.observe(a, element, Model.Tag{replica, previous})) == _ : Bool}
      Equal.trans(Bool,
        Model.point_covered(Model.join_point(Model.observe(left, element, Model.Tag{replica, previous}), Model.observe(right, element, Model.Tag{replica, previous}))),
        Model.point_covered(Model.observe(left, element, Model.Tag{replica, previous})) || Model.point_covered(Model.observe(right, element, Model.Tag{replica, previous})),
        Nat.is_ge(Model.frontier(left, replica), 1n+previous) || Nat.is_ge(Model.frontier(right, replica), 1n+previous),
        point_cover_join(Model.observe(left, element, Model.Tag{replica, previous}), Model.observe(right, element, Model.Tag{replica, previous})),
        or_equal(Model.point_covered(Model.observe(left, element, Model.Tag{replica, previous})),
          Model.point_covered(Model.observe(right, element, Model.Tag{replica, previous})),
          Nat.is_ge(Model.frontier(left, replica), 1n+previous),
          Nat.is_ge(Model.frontier(right, replica), 1n+previous),
          covered_point(left, element, replica, previous), covered_point(right, element, replica, previous)))

def Laws.frontier_coverage(a, element, replica, previous):
  covered_point(a, element, replica, previous)

def Laws.keeps_left_writer(a, b):
  {==}

def point_normalization(+a: Model.Point)
  -> {Model.knowledge(Model.normalize_point(a)) == Model.knowledge(a) : Model.Knowledge}:
  Model.Point{+live, +tombstone, +covered} = a
  match live tombstone covered:
    case False{} False{} False{}:
      {==}
    case False{} False{} True{}:
      {==}
    case False{} True{} False{}:
      {==}
    case False{} True{} True{}:
      {==}
    case True{} False{} False{}:
      {==}
    case True{} False{} True{}:
      {==}
    case True{} True{} False{}:
      {==}
    case True{} True{} True{}:
      {==}

def Laws.normalization_preserves_knowledge(a, element, tag):
  point_normalization(Model.observe(a, element, tag))

def retained_tombstone(+a: Model.Point)
  -> {Model.normalized_tombstone(Model.knowledge(a)) ==
    (Model.point_tombstone(a) && Bool.not(Model.point_covered(a))) : Bool}:
  Model.Point{+live, +tombstone, +covered} = a
  match live tombstone covered:
    case False{} False{} False{}:
      {==}
    case False{} False{} True{}:
      {==}
    case False{} True{} False{}:
      {==}
    case False{} True{} True{}:
      {==}
    case True{} False{} False{}:
      {==}
    case True{} False{} True{}:
      {==}
    case True{} True{} False{}:
      {==}
    case True{} True{} True{}:
      {==}

def Laws.normalization_retains_tombstones(a, element, tag):
  retained_tombstone(Model.observe(a, element, tag))

def live_normalization(+a: Model.Point, valid: Model.disjoint(a))
  -> {Model.normalized_live(Model.knowledge(a)) == Model.point_live(a) : Bool}:
  Model.Point{+live, +tombstone, +covered} = a
  match live tombstone covered:
    case False{} False{} False{}:
      {==}
    case False{} False{} True{}:
      {==}
    case False{} True{} False{}:
      {==}
    case False{} True{} True{}:
      {==}
    case True{} False{} False{}:
      {==}
    case True{} False{} True{}:
      {==}
    case True{} True{} False{}:
      Equal.sym(Bool, True{}, False{}, valid)
    case True{} True{} True{}:
      Equal.sym(Bool, True{}, False{}, valid)

def same_point_live(+a: Model.Point, +b: Model.Point, valid_a: Model.disjoint(a), valid_b: Model.disjoint(b),
  equal: {Model.knowledge(a) == Model.knowledge(b) : Model.Knowledge})
  -> {Model.point_live(a) == Model.point_live(b) : Bool}:
  %live_normalization(b, valid_b) : {Model.point_live(a) == _ : Bool}
  %equal : {Model.point_live(a) == Model.normalized_live(_) : Bool}
  Equal.sym(Bool, Model.normalized_live(Model.knowledge(a)), Model.point_live(a), live_normalization(a, valid_a))

def Laws.same_preserves_live(a, b, valid_a, valid_b, equal):
  (points, frontiers, counters) = equal
  +element => +tag => same_point_live(Model.observe(a, element, tag), Model.observe(b, element, tag),
    valid_a(element, tag), valid_b(element, tag), points(element, tag))

def point_congruence(+a: Model.Point, +b: Model.Point, +c: Model.Point, +d: Model.Point,
  first: {Model.knowledge(a) == Model.knowledge(c) : Model.Knowledge},
  second: {Model.knowledge(b) == Model.knowledge(d) : Model.Knowledge})
  -> {Model.knowledge(Model.join_point(a, b)) == Model.knowledge(Model.join_point(c, d)) : Model.Knowledge}:
  %Equal.sym(Model.Knowledge, Model.knowledge(Model.join_point(c, d)),
    Model.join_knowledge(Model.knowledge(c), Model.knowledge(d)), point_merge(c, d))
    : {Model.knowledge(Model.join_point(a, b)) == _ : Model.Knowledge}
  %first : {Model.knowledge(Model.join_point(a, b)) == Model.join_knowledge(_, Model.knowledge(d)) : Model.Knowledge}
  %second : {Model.knowledge(Model.join_point(a, b)) == Model.join_knowledge(Model.knowledge(a), _) : Model.Knowledge}
  point_merge(a, b)

def counter_join(+a: Model.State, +b: Model.State)
  -> {Model.counter(Model.merge(a, b)) == Nat.max(Model.counter(a), Model.counter(b)) : Nat}:
  max_interchange(Model.allocation(a), Model.allocation(b), Model.pruning_floor(a), Model.pruning_floor(b))

def counter_congruence(+a: Model.State, +b: Model.State, +c: Model.State, +d: Model.State,
  first: {Model.counter(a) == Model.counter(c) : Nat}, second: {Model.counter(b) == Model.counter(d) : Nat})
  -> {Model.counter(Model.merge(a, b)) == Model.counter(Model.merge(c, d)) : Nat}:
  %Equal.sym(Nat, Model.counter(Model.merge(c, d)), Nat.max(Model.counter(c), Model.counter(d)), counter_join(c, d))
    : {Model.counter(Model.merge(a, b)) == _ : Nat}
  %first : {Model.counter(Model.merge(a, b)) == Nat.max(_, Model.counter(d)) : Nat}
  %second : {Model.counter(Model.merge(a, b)) == Nat.max(Model.counter(a), _) : Nat}
  counter_join(a, b)

def Laws.congruence(a, b, c, d, first, second):
  (a_points, a_frontier, a_counter) = first
  (b_points, b_frontier, b_counter) = second
  (+element => +tag => point_congruence(Model.observe(a, element, tag), Model.observe(b, element, tag),
      Model.observe(c, element, tag), Model.observe(d, element, tag), a_points(element, tag), b_points(element, tag)),
    +replica => max_equal(Model.frontier(a, replica), Model.frontier(b, replica),
      Model.frontier(c, replica), Model.frontier(d, replica), a_frontier(replica), b_frontier(replica)),
    counter_congruence(a, b, c, d, a_counter, b_counter))

def Laws.counter_covers_pruning(a):
  Nat.max_ge_r(Model.allocation(a), Model.pruning_floor(a))
