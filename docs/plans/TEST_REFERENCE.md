# Lattice — Test Case Reference

Compiled from existing CRDT implementations to ensure comprehensive coverage.  
**Primary sources:** rust-crdt (Apache 2.0), lasp-lang/types (Apache 2.0)  
**Structural reference:** organicdesign/crdt-tests (GPL-3.0 — approach only, not code)

---

## 1. Universal CRDT Properties (Every Type Must Pass)

These property-based tests apply to ALL CRDT types in Lattice. They verify the semilattice laws.

### 1.1 Merge Laws

| Property | Test | Source |
|----------|------|--------|
| **Commutativity** | `merge(a, b) == merge(b, a)` for arbitrary states | lasp, rust-crdt |
| **Associativity** | `merge(merge(a, b), c) == merge(a, merge(b, c))` | lasp, rust-crdt |
| **Idempotency** | `merge(a, a) == a` | lasp, rust-crdt |
| **Convergence** | After all-to-all exchange, all replicas produce identical `value()` | rust-crdt |
| **Bottom identity** | `merge(a, new()) == a` for any state a | lasp |

### 1.2 Ordering / Inflation (from lasp-lang)

| Property | Test |
|----------|------|
| **is_bottom** | `new()` is bottom; any mutated state is not bottom |
| **is_inflation** | After any update, new state >= old state in lattice order |
| **is_strict_inflation** | After a *meaningful* update, new state > old state strictly |
| **monotonicity** | `value(merge(a, b)) >= value(a)` and `value(merge(a, b)) >= value(b)` |

### 1.3 Serialization Round-Trip

| Property | Test |
|----------|------|
| **encode_decode** | `from_json(to_json(state)) == state` for arbitrary states |
| **cross-target** | State encoded on Erlang target decodes identically on JS target |

---

## 2. G-Counter

### 2.1 Basic Operations (rust-crdt, lasp)

```
test "starts at zero"
  new(rid) |> value == 0

test "increment by one"
  new(rid) |> increment(1) |> value == 1

test "increment by many"
  new(rid) |> increment(5) |> increment(3) |> value == 8

test "multiple replicas sum correctly"
  a = new("A") |> increment(5)
  b = new("B") |> increment(3)
  merge(a, b) |> value == 8
```

### 2.2 Merge Scenarios (lasp)

```
test "merge idempotent"
  a = new("A") |> increment(1)
  b = new("B") |> increment(13)
  c = new("C") |> increment(1)
  counter = {A: 1, B: 13, C: 1}  // value = 15
  merge(counter, counter) |> value == 15

test "merge commutative"
  counter1 = {A: 1, B: 13, C: 1}
  counter2 = {B: 2, C: 13, D: 2}
  merge(counter1, counter2) == merge(counter2, counter1)
  // result: {A: 1, B: 13, C: 13, D: 2} => value = 29

test "merge same replica id, takes max"
  a = new("X") |> increment(5)
  b = new("X") |> increment(3)
  merge(a, b) |> value == 5  // max(5, 3), NOT sum

test "merge deltas"
  // Delta from increment is just the single replica's contribution
  // Merging delta into remote produces same result as full merge
```

### 2.3 Property Tests (rust-crdt)

```
prop "merge converges across interleavings"
  // Apply random ops to different subsets of replicas
  // Merge all together → should always produce same result
  // regardless of merge order
```

---

## 3. PN-Counter

### 3.1 Basic Operations (rust-crdt, lasp)

```
test "starts at zero"
  new(rid) |> value == 0

test "increment and decrement"
  new(rid) |> increment(10) |> decrement(3) |> value == 7

test "can go negative"
  new(rid) |> decrement(5) |> value == -5

test "multiple replicas"
  a = new("A") |> increment(10)
  b = new("B") |> decrement(3)
  merge(a, b) |> value == 7
```

### 3.2 Merge Scenarios (lasp)

```
test "merge idempotent"
  // Same as G-Counter pattern but with P and N vectors

test "merge commutative"
  // P = {A:1, B:13, C:1}, N = {A:0, B:5, C:0}
  // Value = sum(P) - sum(N)

test "merge same id takes max of both P and N"
  a_inc = new("X") |> increment(5)
  b_inc = new("X") |> increment(3)
  merge(a, b) P-value for X == 5 (max)
```

### 3.3 Property Tests (rust-crdt)

```
prop "merge converges"
  // Generate random (actor, amount, is_increment) triples
  // Apply to multiple replicas in different orders
  // All merged results should be equal
```

---

## 4. G-Set

### 4.1 Basic Operations (lasp, crdt-tests)

```
test "starts empty"
  new() |> value == set.new()

test "add elements"
  new() |> add("a") |> add("b") |> value == set.from_list(["a", "b"])

test "add is idempotent"
  new() |> add("a") |> add("a") |> value == set.from_list(["a"])

test "contains"
  s = new() |> add("a")
  contains(s, "a") == True
  contains(s, "b") == False
```

### 4.2 Merge Scenarios (lasp)

```
test "merge is union"
  a = new() |> add("x") |> add("y")
  b = new() |> add("y") |> add("z")
  merge(a, b) |> value == set.from_list(["x", "y", "z"])

test "merge commutative"
  merge(a, b) == merge(b, a)

test "merge idempotent"
  merge(a, a) == a

test "merge with empty"
  merge(a, new()) == a

test "merge deltas"
  // Delta of add("x") is just {x}
  // Applying delta to remote = union
```

---

## 5. 2P-Set

### 5.1 Basic Operations

```
test "add and contains"
  new() |> add("a") |> contains("a") == True

test "remove makes element absent"
  new() |> add("a") |> remove("a") |> contains("a") == False

test "tombstone is permanent"
  s = new() |> add("a") |> remove("a") |> add("a")
  contains(s, "a") == False  // cannot re-add!

test "remove of non-member is no-op"
  new() |> remove("a") |> add("a") |> contains("a") == False
  // "a" was in tombstone set before add, so add has no effect
```

### 5.2 Merge Scenarios

```
test "merge respects tombstones from either side"
  a = new() |> add("x")
  b = new() |> add("x") |> remove("x")
  merge(a, b) |> contains("x") == False

test "value is add_set minus remove_set"
  // Both add and remove sets merge via union
```

---

## 6. OR-Set (ORSWOT) — Most Critical Test Coverage

### 6.1 Basic Operations (lasp, rust-crdt)

```
test "add and contains"
  new(rid) |> add("a") |> contains("a") == True

test "remove after add"
  new(rid) |> add("a") |> remove("a") |> contains("a") == False

test "re-add after remove" (key difference from 2P-Set!)
  new(rid) |> add("a") |> remove("a") |> add("a") |> contains("a") == True

test "add_all and remove_all" (lasp)
  s = new(rid) |> add_all(["a", "b", "c"])
  s |> remove_all(["a", "c"]) |> value == set.from_list(["b"])
```

### 6.2 Concurrent Conflict Scenarios (rust-crdt — ported from riak_dt)

```
test "concurrent add wins" (THE defining OR-Set property)
  base = new("A") |> add("x")
  // Fork:
  a = base |> remove("x")   // Alice removes
  b = base |> add("x")      // Bob re-adds concurrently (different replica)
  merge(a, b) |> contains("x") == True  // ADD WINS

test "disjoint merge" (riak_dt port)
  a = new("A") |> add(0)     // {0}
  b = new("B") |> add(1)     // {1}
  c = merge(a, b)            // {0, 1}
  a2 = a |> remove(0)        // {}
  merge(a2, c) |> value == {1}  // 0 removed, 1 preserved

test "weird highlight: same witness, different elements" (rust-crdt)
  // When two orswots have identical clocks but different elements,
  // non-common elements will be dropped
  a = new() with actor "A" adds 1
  b = new() with actor "A" adds 2  // SAME actor, fresh orswot
  merge(a, b) |> value == {}  // both dropped!
  // This highlights: don't reuse witnesses across copies

test "adds don't destroy causality" (rust-crdt)
  a, b, c = clone of empty set
  c |> add("element") via actor A
  c |> add("element") via actor B
  // c's element has clock {A:1, B:1}
  a |> add("element") via actor C
  b |> remove_from_c("element")  // removes {A:1, B:1}
  a |> add("element") via actor A again  // A:2
  merge(a, b) |> contains("element") == True  // A:2 survived

test "merge clocks of identical entries" (rust-crdt quickcheck bug)
  // Same element added with different witnesses must merge clocks
  a adds 1 via actor A  → clock for element 1 = {A:1}
  b adds 1 via actor B  → clock for element 1 = {B:1}
  merge(a, b) → element 1 exists with clock {A:1, B:1}

test "no dots left" (riak_dt EQC bug)
  // Complex scenario:
  a adds 0 via A, b adds 0 via B
  a removes 0 (only removes A's dot)
  merge(a, b) → 0 present (B's dot survives)
  b removes 0 (only removes B's dot)
  merge(b, clone_of_a_before_remove) → 0 present (A's old dot)
  merge everything together → 0 ABSENT
  // Both dots were eventually removed

test "dead node update" (riak_dt)
  // Node b adds element, gets context, then goes down forever
  // Node a uses b's context to remove element
  // Element should still be removed because dots carry the info
  a adds 0 via A
  b = clone(a), b adds 1 via B
  b_context = read(b)  // {A:1, B:1}
  a removes 0 using b_context
  a |> contains(0) == False

test "reset remove semantics" (rust-crdt)
  // Map containing OR-Set: concurrent remove-key vs update-key
  map has key 101 → OR-Set containing {1}
  m1: remove key 101
  m2: add 2 to set at key 101 → {1, 2}
  merge(m1, m2) → key 101 exists with set {2}
  // Key removal beats the old element 1, but concurrent add of 2 wins
```

### 6.3 Property Tests (rust-crdt)

```
prop "validate_op"
  // Random sequence of ops, then a new op:
  // If op's dot <= clock → op is valid (but may be no-op)
  // If op's dot == clock.inc(actor) → op is valid and applied
  // If op's dot > clock.inc(actor) → op is invalid (gap)

prop "validate_merge"
  // If validate_merge(a, b) is OK, then validate_merge(b, a) is also OK
  // After merge, any element present in a but not in merged
  //   must have been fully removed by ops in b

prop "merge converges"
  // Apply random ops to 2..11 witness replicas
  // Merge all witnesses together
  // Result must be identical regardless of number of witnesses
```

---

## 7. LWW-Register

### 7.1 Basic Operations (lasp, rust-crdt)

```
test "set and query"
  new("initial", timestamp: 1000) |> value == "initial"

test "later timestamp wins"
  r = new("a", timestamp: 1)
  r = set(r, "b", timestamp: 2)
  value(r) == "b"

test "earlier timestamp is ignored"
  r = new("a", timestamp: 2)
  r = set(r, "b", timestamp: 1)
  value(r) == "a"  // timestamp 2 > 1, old value kept
```

### 7.2 Merge Scenarios (lasp, rust-crdt)

```
test "merge keeps higher timestamp"
  r1 = new("alice", timestamp: 100)
  r2 = new("bob", timestamp: 200)
  merge(r1, r2) |> value == "bob"

test "merge idempotent"
  merge(r, r) == r

test "merge commutative"
  merge(r1, r2) == merge(r2, r1)
```

### 7.3 Property Tests (rust-crdt)

```
prop "associative"
  // For any three registers r1, r2, r3:
  // merge(merge(r1, r2), r3) == merge(r1, merge(r2, r3))

prop "commutative"
  // merge(r1, r2) == merge(r2, r1) for any r1, r2

prop "idempotent"
  // merge(r, r) == r for any r
```

### 7.4 Edge Cases

```
test "equal timestamps with tiebreaker"
  // When timestamps are equal, need deterministic tiebreaker
  // Options: compare values, compare replica IDs, or keep both
  // DECISION NEEDED: document chosen behavior

test "default/bottom value"
  new() with no initial value → value is Option(None) or empty
```

---

## 8. MV-Register

### 8.1 Basic Operations (lasp, rust-crdt)

```
test "set and query"
  new(rid) |> set("a") |> value == ["a"]

test "sequential sets replace"
  new(rid) |> set("a") |> set("b") |> value == ["b"]

test "concurrent sets preserve both" (defining property)
  a = new("A") |> set("alice")
  b = new("B") |> set("bob")
  merge(a, b) |> value == ["alice", "bob"]  // both preserved!

test "write after merge resolves"
  merged = merge(a, b)  // ["alice", "bob"]
  merged |> set("resolved") |> value == ["resolved"]
```

### 8.2 Merge Scenarios (lasp)

```
test "merge idempotent"
  merge(r, r) == r

test "merge commutative"
  merge(r1, r2) |> value has same elements as merge(r2, r1) |> value

test "causally dominated values are dropped"
  a = new("A") |> set("v1")
  b = merge(a, new("B")) |> set("v2")  // b has seen a's v1
  merge(a, b) |> value == ["v2"]  // v1 is causally dominated
```

### 8.3 Complex Scenarios (lasp)

```
test "three-way concurrent"
  a = new("A") |> set("x")
  b = new("B") |> set("y")
  c = new("C") |> set("z")
  merged = merge(merge(a, b), c) |> value == ["x", "y", "z"]

test "causal chain"
  a sets "v1"
  b merges a, then sets "v2" (supersedes "v1")
  c merges b, then sets "v3" (supersedes "v2")
  merge(a, merge(b, c)) |> value == ["v3"]
```

---

## 9. Version Vector

### 9.1 Basic Operations (rust-crdt)

```
test "starts empty"
  new() |> get("A") == 0

test "increment"
  new() |> increment("A") |> get("A") == 1
  new() |> increment("A") |> increment("A") |> get("A") == 2
```

### 9.2 Ordering (rust-crdt — comprehensive)

```
test "empty equals empty"
  VClock::new() == VClock::new()

test "dominates"
  a = {A: 2}, b = {A: 1}
  compare(a, b) == After  // a dominates b

test "is dominated"
  a = {A: 2}, b = {A: 3}
  compare(a, b) == Before

test "concurrent (disjoint keys)"
  a = {A: 2, B: 1}, b = {A: 3}
  compare(a, b) == Concurrent

test "concurrent (mixed)"
  a = {A: 3, B: 1}, b = {A: 3, B: 2}
  compare(a, b) == Before  // b dominates

test "equal"
  a = {A: 3, B: 2}, b = {A: 3, B: 2}
  compare(a, b) == Equal
```

### 9.3 Merge (rust-crdt)

```
test "merge takes pairwise max"
  a = {1: 1, 4: 4}, b = {3: 3, 4: 3}
  merge(a, b) == {1: 1, 3: 3, 4: 4}

test "merge asymmetric sizes (left smaller)"
  a = {5: 5}, b = {6: 6, 7: 7}
  merge(a, b) == {5: 5, 6: 6, 7: 7}

test "merge asymmetric sizes (right smaller)"
  a = {6: 6, 7: 7}, b = {5: 5}
  merge(a, b) == {5: 5, 6: 6, 7: 7}

test "merge overlapping ids"
  a = {1: 1, 2: 1}, b = {1: 1, 3: 1}
  merge(a, b) == {1: 1, 2: 1, 3: 1}
```

### 9.4 Property Tests (rust-crdt)

```
prop "from_iter is commutative over dots"
  // Reversing dot order produces same clock

prop "from_iter is idempotent"
  // Doubling dots produces same clock

prop "glb(a, a) == a" (greatest lower bound)

prop "glb commutes"
  glb(a, b) == glb(b, a)

prop "reset_remove with empty is nop"
  reset_remove(a, empty) == a

prop "reset_remove self is empty"
  reset_remove(a, a) == empty

prop "reset_remove empty implies dominated"
  if reset_remove(a, b) is empty → a <= b
```

---

## 10. LWW-Map

### 10.1 Basic Operations (crdt-tests structure)

```
test "set and get"
  new() |> set("key", "value", ts: 1) |> get("key") == Ok("value")

test "get missing key"
  new() |> get("missing") == Error(Nil)

test "later timestamp wins per key"
  m = new() |> set("k", "old", ts: 1) |> set("k", "new", ts: 2)
  get(m, "k") == Ok("new")

test "remove key"
  m = new() |> set("k", "v", ts: 1) |> remove("k", ts: 2)
  get(m, "k") == Error(Nil)

test "set after remove"
  m = new() |> set("k", "v", ts: 1) |> remove("k", ts: 2) |> set("k", "v2", ts: 3)
  get(m, "k") == Ok("v2")
```

### 10.2 Merge Scenarios

```
test "merge takes per-key highest timestamp"
  a = set("x", "alice", ts: 1)
  b = set("x", "bob", ts: 2)
  merge(a, b) |> get("x") == Ok("bob")

test "merge preserves disjoint keys"
  a = set("x", "1", ts: 1)
  b = set("y", "2", ts: 1)
  m = merge(a, b)
  get(m, "x") == Ok("1")
  get(m, "y") == Ok("2")
```

---

## 11. OR-Map

### 11.1 Basic Operations

```
test "update and get"
  m = new(rid, counter_spec)
  m = update(m, "likes", fn(c) { increment(c, 1) })
  get(m, "likes") |> counter.value == 1

test "remove key"
  m = new(rid, counter_spec) |> update("k", inc) |> remove("k")
  get(m, "k") == Error(Nil)
```

### 11.2 Concurrent Conflict (rust-crdt reset-remove test)

```
test "concurrent update + remove: update wins"
  base has key "score" → counter at 5
  a: remove key "score"
  b: increment counter at "score" to 6
  merge(a, b) → key "score" exists, counter = 1
  // Only the concurrent increment (6-5=1 from B's perspective) survives
  // The pre-existing value (5) was covered by the remove context

test "nested CRDT values merge correctly"
  a has key "tags" → OR-Set with {"urgent"}
  b has key "tags" → OR-Set with {"important"}
  merge(a, b) → key "tags" → OR-Set with {"urgent", "important"}
```

---

## 12. Test Infrastructure Patterns

### 12.1 Property Test Generators

For property-based testing, generate:
- Random `ReplicaId` from small alphabet (3-5 replicas)
- Random operations (add, remove, increment, set) with random payloads
- Random operation sequences of length 1-50
- Random merge orderings

### 12.2 Convergence Test Pattern (from rust-crdt)

```
For any sequence of operations:
  1. Apply ops to N different replica subsets (N = 2..11)
  2. Merge all replicas together
  3. Result must be identical regardless of N and partition strategy
```

### 12.3 Inflation Test Pattern (from lasp-lang)

```
For every mutate operation:
  1. state_before = current state
  2. Apply mutation → state_after
  3. Assert: is_inflation(state_before, state_after) == True
  4. For meaningful mutations: is_strict_inflation(state_before, state_after) == True
```

### 12.4 Join Decomposition Pattern (from lasp-lang)

```
For any state S:
  1. Decompose S into irreducible components [c1, c2, ..., cn]
  2. merge(c1, merge(c2, ... merge(cn-1, cn))) == S
  3. Each ci is strictly inflated from bottom
```

---

## 13. Source Attribution

| Source | License | What to Port |
|--------|---------|-------------|
| **rust-crdt** (`rust-crdt/rust-crdt`) | Apache 2.0 | Scenario tests (riak_dt ports), property test strategies, quickcheck bug reproductions |
| **lasp-lang/types** (`lasp-lang/types`) | Apache 2.0 | Idempotency/commutativity/inflation/decomposition test patterns, delta merge tests |
| **organicdesign/crdt-tests** | GPL-3.0 | Test structure and approach only (cannot port code) |
| **riak_dt** (via rust-crdt ports) | Apache 2.0 | Bug regression tests (disjoint merge, no dots left, dead node) |

All Apache 2.0 sources can be freely adapted with attribution in test file headers.