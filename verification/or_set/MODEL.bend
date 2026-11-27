import Base

type Tag is Data:
  Tag{replica: Nat, previous: Nat}

type Live is Data:
  Live{element: Nat, tag: Tag}

type Clock is Data:
  Clock{replica: Nat, value: Nat}

type State is Data:
  Snapshot{writer: Nat, allocation: Nat, entries: List<&2, Live>, tombstones: List<&2, Tag>, clocks: List<&2, Clock>}
  Merged{left: State, right: State}

type Point is Data:
  Point{live: Bool, tombstone: Bool, covered: Bool}

type Knowledge is Data:
  Knowledge{seen: Bool, removed: Bool, covered: Bool}

def tag_equal(a: Tag, b: Tag) -> Bool:
  Tag{ar, ac} = a
  Tag{br, bc} = b
  Nat.is_eq(ar, br) && Nat.is_eq(ac, bc)

def has_tag(tags: List<&2, Tag>, +tag: Tag) -> Bool:
  match tags:
    case Nil{}:
      False{}
    case Con{head, tail}:
      tag_equal(head, tag) || has_tag(tail, tag)

def has_live(entries: List<&2, Live>, +element: Nat, +tag: Tag) -> Bool:
  match entries:
    case Nil{}:
      False{}
    case Con{Live{value, added}, tail}:
      (Nat.is_eq(value, element) && tag_equal(added, tag)) || has_live(tail, element, tag)

def clock_if(value: Nat, same: Bool) -> Nat:
  match same:
    case False{}:
      0n
    case True{}:
      value

def lookup(clocks: List<&2, Clock>, +replica: Nat) -> Nat:
  match clocks:
    case Nil{}:
      0n
    case Con{Clock{writer, value}, tail}:
      Nat.max(clock_if(value, Nat.is_eq(writer, replica)), lookup(tail, replica))

def maximum_clock(clocks: List<&2, Clock>) -> Nat:
  match clocks:
    case Nil{}:
      0n
    case Con{Clock{replica, value}, tail}:
      Nat.max(value, maximum_clock(tail))

def writer(state: State) -> Nat:
  match state:
    case Snapshot{id, allocation, entries, tombstones, clocks}:
      id
    case Merged{left, right}:
      writer(left)

def frontier(state: State, +replica: Nat) -> Nat:
  match state:
    case Snapshot{writer, allocation, entries, tombstones, clocks}:
      lookup(clocks, replica)
    case Merged{left, right}:
      Nat.max(frontier(left, replica), frontier(right, replica))

def pruning_floor(state: State) -> Nat:
  match state:
    case Snapshot{writer, allocation, entries, tombstones, clocks}:
      maximum_clock(clocks)
    case Merged{left, right}:
      Nat.max(pruning_floor(left), pruning_floor(right))

# Factor the pruning floor out of repeated merges; counter_step proves this
# equals applying counter_with_pruned_floor at each merge.
def allocation(state: State) -> Nat:
  match state:
    case Snapshot{writer, allocated, entries, tombstones, clocks}:
      allocated
    case Merged{left, right}:
      Nat.max(allocation(left), allocation(right))

def counter(+state: State) -> Nat:
  Nat.max(allocation(state), pruning_floor(state))

def point_live(point: Point) -> Bool:
  Point{live, tombstone, covered} = point
  live

def point_tombstone(point: Point) -> Bool:
  Point{live, tombstone, covered} = point
  tombstone

def point_covered(point: Point) -> Bool:
  Point{live, tombstone, covered} = point
  covered

def join_point(a: Point, b: Point) -> Point:
  Point{+al, +at, +ap} = a
  Point{+bl, +bt, +bp} = b
  +removed = at || bt
  +covered = ap || bp
  zombies = (ap && Bool.not(al)) || (bp && Bool.not(bl))
  Point{
    (al || bl) && Bool.not(removed) && Bool.not(zombies),
    removed && Bool.not(covered),
    covered
  }

def observe(state: State, +element: Nat, +tag: Tag) -> Point:
  match state:
    case Snapshot{writer, allocation, entries, tombstones, clocks}:
      Tag{+replica, +previous} = tag
      +query = {Tag{replica, previous} : Tag}
      Point{
        has_live(entries, element, query),
        has_tag(tombstones, query),
        Nat.is_ge(lookup(clocks, replica), 1n+previous)
      }
    case Merged{left, right}:
      join_point(observe(left, element, tag), observe(right, element, tag))

def merge(a: State, b: State) -> State:
  Merged{a, b}

# Below a frontier, absence records a removal even after its tombstone is gone.
def knowledge(point: Point) -> Knowledge:
  Point{+live, +tombstone, +covered} = point
  Knowledge{
    live || tombstone || covered,
    tombstone || (covered && Bool.not(live)),
    covered
  }

def join_knowledge(a: Knowledge, b: Knowledge) -> Knowledge:
  Knowledge{as, ar, ap} = a
  Knowledge{bs, br, bp} = b
  Knowledge{as || bs, ar || br, ap || bp}

def normalized_live(knowledge: Knowledge) -> Bool:
  Knowledge{seen, removed, covered} = knowledge
  seen && Bool.not(removed)

def normalized_tombstone(knowledge: Knowledge) -> Bool:
  Knowledge{seen, removed, covered} = knowledge
  removed && Bool.not(covered)

def normalize_point(+point: Point) -> Point:
  +known = knowledge(point)
  Point{normalized_live(known), normalized_tombstone(known), point_covered(point)}

def disjoint(+point: Point) -> Type:
  {point_live(point) && point_tombstone(point) == False{} : Bool}

def valid(-state: State) -> Type:
  @element: Nat -> @tag: Tag -> disjoint(observe(state, element, tag))

def same(-a: State, -b: State) -> Type:
  (@element: Nat -> @tag: Tag ->
    {knowledge(observe(a, element, tag)) == knowledge(observe(b, element, tag)) : Knowledge}) &
  (@replica: Nat -> {frontier(a, replica) == frontier(b, replica) : Nat}) &
  {counter(a) == counter(b) : Nat}

def same_live(-a: State, -b: State) -> Type:
  @element: Nat -> @tag: Tag ->
    {point_live(observe(a, element, tag)) == point_live(observe(b, element, tag)) : Bool}
