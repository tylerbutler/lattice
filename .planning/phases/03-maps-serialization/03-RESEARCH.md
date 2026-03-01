# Phase 3: Maps & Serialization - Research

**Researched:** 2026-03-01
**Domain:** CRDT maps (LWW-Map, OR-Map), gleam_json serialization, cross-target compatibility
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Serialization Packaging**
- Same package — to_json/from_json functions live directly on each CRDT module (e.g., g_counter.to_json, g_counter.from_json)
- gleam_json becomes a runtime dependency (acceptable — serialization is a core CRDT library feature)
- Error type: use gleam/json.DecodeError directly (standard, composable, carries path info)

**JSON Format Design**
- Self-describing format with type tag and version: `{"type": "g_counter", "v": 1, "state": {...}}`
- Transparent internals — serialize actual internal structure for full fidelity and debuggability
- Generic dispatch decoder: lattice/crdt.gleam provides from_json(json) that reads "type" field and dispatches to the correct type-specific decoder
- Returns tagged union enum: `pub type Crdt { CrdtGCounter(GCounter) | CrdtPnCounter(PnCounter) | ... }`

**OR-Map Nested CRDT Design**
- OR-Map stores values as the Crdt union enum (same tagged union from serialization)
- Homogeneous: all keys store the same CRDT type, specified at construction
- Auto-create from type tag: if key doesn't exist on update(), create a default value from the map's CRDT type and replica_id
- The Crdt union type and generic merge/dispatch functions live in `lattice/crdt.gleam` (dedicated module)

### Claude's Discretion

- Exact JSON field names and nesting structure for each CRDT type
- LWW-Map internal representation (Dict of timestamped entries vs separate value/timestamp dicts)
- OR-Map internal causal context tracking approach
- Cross-target test strategy details

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

## Summary

Phase 3 delivers two new CRDT map types (LWW-Map and OR-Map) plus JSON serialization for all 10 CRDT types in the lattice library. The serialization story is well-constrained by user decisions: gleam_json 3.1.0 (already in the manifest as a transitive dependency) becomes a direct runtime dependency, each module gets `to_json/from_json` functions, and a new `lattice/crdt.gleam` module provides the tagged union type that serves dual purpose as OR-Map value storage and generic JSON dispatch target.

The gleam_json API (v3.1.0) is clean and verified: encoding uses `json.object`, `json.array`, `json.dict`, `json.int`, `json.string`, `json.bool` composably, with `json.to_string` for final output. Decoding uses `gleam/dynamic/decode` with the `use` monadic syntax and `json.parse`. The key insight for serialization is that all 8 existing CRDT types have non-opaque record types with directly accessible fields, making to_json straightforward. The OR-Map is the hardest piece: it requires the `Crdt` union for type-tagged merge dispatch, and tracking which CRDT type the map holds at construction time.

The self-describing JSON format `{"type": "...", "v": 1, "state": {...}}` enables the generic dispatcher in `lattice/crdt.gleam` to read the "type" field and route to the correct type-specific decoder without any information loss. Cross-target compatibility (Erlang/JS) is guaranteed as long as no BEAM-specific types (atoms, bitstrings, tuples) appear in the JSON encoding — using only JSON primitives (strings, ints, arrays, objects) ensures portability.

**Primary recommendation:** Implement in dependency order — (1) LWW-Map, (2) lattice/crdt.gleam union + JSON for simple types, (3) OR-Map with Crdt union values, (4) JSON for composite/map types, (5) round-trip and convergence property tests.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MAP-01 | LWW-Map: new() -> t | `Dict(String, #(value, Int))` — each entry is `#(value, timestamp)` tuple |
| MAP-02 | LWW-Map: set(map, key, value, timestamp) -> map | Insert/update entry; keep existing if timestamp is not strictly greater |
| MAP-03 | LWW-Map: get(map, key) -> Result(value, Nil) | `dict.get` then extract value from tuple |
| MAP-04 | LWW-Map: remove(map, key, timestamp) -> map | Insert tombstone entry with timestamp and Nil/sentinel value, OR delete key (tombstone approach preferred for LWW semantics) |
| MAP-05 | LWW-Map: keys(map) -> List(key) | `dict.keys` on internal dict |
| MAP-06 | LWW-Map: values(map) -> List(value) | `dict.values` then extract value fields |
| MAP-07 | LWW-Map: merge(a, b) -> map (per-key LWW) | For each key in union of both key sets, keep entry with higher timestamp (pairwise LWW) |
| MAP-08 | OR-Map: new(replica_id, crdt_spec) -> t | `crdt_spec` is a tag from `Crdt` enum; OR-Set for key tracking reusing or_set.gleam patterns |
| MAP-09 | OR-Map: update(map, key, fn(crdt) -> crdt) -> map | Apply fn to existing CRDT value (auto-create default if absent), update OR-Set key tracking |
| MAP-10 | OR-Map: get(map, key) -> Result(crdt, Nil) | Look up key in values dict; return Error if key not in OR-Set |
| MAP-11 | OR-Map: remove(map, key) -> map | Remove key from OR-Set; leave value in values dict (will be GC'd on next merge if key not re-added) |
| MAP-12 | OR-Map: keys(map) -> List(key) | `or_set.value` (which gives active keys) then convert to list |
| MAP-13 | OR-Map: values(map) -> List(crdt) | Filter values dict to only active keys per OR-Set |
| MAP-14 | OR-Map: merge(a, b) -> map (add-wins keys, CRDT-merge values) | Merge key OR-Sets (add-wins); for each key present in merged OR-Set, merge the CRDT values using type-dispatch via Crdt union |
| JSON-01 | JSON encoder for G-Counter | `json.object([#("type", json.string("g_counter")), #("v", json.int(1)), #("state", encode_state)])` where state has `self_id` and `dict` |
| JSON-02 | JSON decoder for G-Counter | `decode.field("state", ...)` → construct `GCounter` |
| JSON-03 | JSON encoder for PN-Counter | Encode `positive` and `negative` G-Counter states |
| JSON-04 | JSON decoder for PN-Counter | Decode two nested G-Counter state objects |
| JSON-05 | JSON encoder for LWW-Register | Encode `value` (String — type parameter constraint) and `timestamp` |
| JSON-06 | JSON decoder for LWW-Register | Decode `value` and `timestamp` fields |
| JSON-07 | JSON encoder for MV-Register | Encode `replica_id`, `entries` (list of tag+value pairs), `vclock` (as dict) |
| JSON-08 | JSON decoder for MV-Register | Reconstruct `Tag` records, entries dict, and VersionVector |
| JSON-09 | JSON encoder for G-Set | Encode `elements` as JSON array |
| JSON-10 | JSON decoder for G-Set | Decode array, reconstruct `set.Set` via `set.from_list` |
| JSON-11 | JSON encoder for 2P-Set | Encode `added` and `removed` as JSON arrays |
| JSON-12 | JSON decoder for 2P-Set | Decode two arrays, reconstruct both `set.Set` fields |
| JSON-13 | JSON encoder for OR-Set | Encode `replica_id`, `counter`, `entries` (dict of element → list of tags) |
| JSON-14 | JSON decoder for OR-Set | Reconstruct entries dict with `set.Set(Tag)` values |
| JSON-15 | JSON encoder for LWW-Map | Encode entries dict as list of `#(key, #(value, timestamp))` objects |
| JSON-16 | JSON decoder for LWW-Map | Reconstruct entries dict |
| JSON-17 | JSON encoder for OR-Map | Encode key OR-Set + values dict (each value as a nested typed CRDT JSON) |
| JSON-18 | JSON decoder for OR-Map | Decode OR-Set, then decode each value using the generic CRDT decoder |
| JSON-19 | JSON encoder for Version Vector | `json.dict(vv.dict, keys: fn(k) -> k, values: json.int)` |
| JSON-20 | JSON decoder for Version Vector | `decode.dict(decode.string, decode.int)` → wrap in VersionVector |

</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `gleam_json` | 3.1.0 (in manifest) | JSON encoding and decoding | Only gleam JSON library; already resolved as transitive dep |
| `gleam_stdlib` | 0.68.1 (installed) | `gleam/dict`, `gleam/set`, `gleam/list`, `gleam/dynamic/decode` | All CRDT internals + decoder composition |
| `startest` | 0.8.0 (installed) | `startest/expect` for assertions | Established in all existing tests |
| `qcheck` | 1.0.4 (installed) | Property-based round-trip tests | Established; use `small_test_config()` pattern |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `lattice/or_set` | (project) | OR-Map key tracking reuses OR-Set semantics | OR-Map key CRDT is functionally an OR-Set of String keys |
| `lattice/version_vector` | (project) | Serialized in JSON-19/JSON-20; reused in MV-Register encoding | VersionVector's internal `dict.Dict(String, Int)` maps cleanly to JSON |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `json.dict` for version vector | `json.array` of `#(key, val)` pairs | `json.dict` requires String keys — VersionVector uses String keys so `json.dict` is exactly right |
| `set.to_list` then `json.array` for G-Set | Custom encoding | Clean and direct; `set.to_list` gives a List that `json.array` accepts |
| `Crdt` union enum for OR-Map values | Separate type per map | Union enables type-dispatch during merge and JSON decode without type-unsafe casting |

**Installation required:** Move `gleam_json` from dev-dependency (not currently in `[dependencies]`) to `[dependencies]` in gleam.toml:

```bash
gleam add gleam_json
```

Note: `gleam_json` 3.1.0 is already in `manifest.toml` as a transitive dependency of `gleam_community_colour` (which is a startest dependency). Adding it as a direct dependency makes the dep explicit and ensures it stays at 3.1.0+ in the runtime.

## Architecture Patterns

### Recommended Project Structure
```
src/
└── lattice/
    ├── g_counter.gleam        # Existing — add to_json, from_json
    ├── pn_counter.gleam       # Existing — add to_json, from_json
    ├── version_vector.gleam   # Existing — add to_json, from_json
    ├── lww_register.gleam     # Existing — add to_json, from_json
    ├── mv_register.gleam      # Existing — add to_json, from_json
    ├── g_set.gleam            # Existing — add to_json, from_json
    ├── two_p_set.gleam        # Existing — add to_json, from_json
    ├── or_set.gleam           # Existing — add to_json, from_json
    ├── crdt.gleam             # NEW: Crdt union + generic encode/decode + merge dispatch
    ├── lww_map.gleam          # NEW: LWW-Map CRDT
    └── or_map.gleam           # NEW: OR-Map CRDT (uses Crdt union from crdt.gleam)
test/
├── counter/                   # Existing
├── clock/                     # Existing
├── register/                  # Existing
├── set/                       # Existing
├── map/
│   ├── lww_map_test.gleam     # NEW: LWW-Map unit tests
│   └── or_map_test.gleam      # NEW: OR-Map unit tests
├── serialization/
│   ├── g_counter_json_test.gleam    # NEW: JSON round-trip tests per type
│   ├── pn_counter_json_test.gleam
│   ├── lww_register_json_test.gleam
│   ├── mv_register_json_test.gleam
│   ├── g_set_json_test.gleam
│   ├── two_p_set_json_test.gleam
│   ├── or_set_json_test.gleam
│   ├── lww_map_json_test.gleam
│   ├── or_map_json_test.gleam
│   └── version_vector_json_test.gleam
└── property/
    └── serialization_property_test.gleam  # NEW: round-trip + convergence property tests
```

### Pattern 1: gleam_json Encoding (Verified API)
**What:** Each module's `to_json(t) -> json.Json` produces the self-describing wrapper
**When to use:** Every CRDT module needs this pattern
**Example:**
```gleam
// Source: https://hexdocs.pm/gleam_json/gleam/json.html (verified 2026-03-01)
import gleam/json
import gleam/dict

// Encoding a G-Counter
pub fn to_json(counter: GCounter) -> json.Json {
  let GCounter(d, self_id) = counter
  json.object([
    #("type", json.string("g_counter")),
    #("v", json.int(1)),
    #("state", json.object([
      #("self_id", json.string(self_id)),
      #("counts", json.dict(d, keys: fn(k) -> k, values: json.int)),
    ])),
  ])
}

// Encoding a VersionVector (JSON-19)
pub fn to_json(vv: VersionVector) -> json.Json {
  let VersionVector(d) = vv
  json.object([
    #("type", json.string("version_vector")),
    #("v", json.int(1)),
    #("state", json.object([
      #("clocks", json.dict(d, keys: fn(k) -> k, values: json.int)),
    ])),
  ])
}

// Final string output
json.to_string(counter.to_json(my_counter))
```

### Pattern 2: gleam/dynamic/decode Decoding (Verified API)
**What:** `from_json(json_string) -> Result(T, json.DecodeError)` using `use` monadic syntax
**When to use:** Every CRDT module's `from_json` function
**Example:**
```gleam
// Source: https://hexdocs.pm/gleam_stdlib/gleam/dynamic/decode.html (verified 2026-03-01)
import gleam/json
import gleam/dynamic/decode

// Decoding a G-Counter (JSON-02)
pub fn from_json(json_string: String) -> Result(GCounter, json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", decode.string)
      use counts <- decode.field("counts", decode.dict(decode.string, decode.int))
      decode.success(GCounter(dict: counts, self_id: self_id))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}

// Decoding a VersionVector (JSON-20)
pub fn from_json(json_string: String) -> Result(VersionVector, json.DecodeError) {
  let decoder = {
    use state <- decode.field("state", {
      use clocks <- decode.field("clocks", decode.dict(decode.string, decode.int))
      decode.success(VersionVector(dict: clocks))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}
```

### Pattern 3: Crdt Union Type and Generic Dispatcher
**What:** Central `lattice/crdt.gleam` defines the tagged union and dispatches encoding/decoding
**When to use:** Generic JSON decode, OR-Map value merge dispatch
**Example:**
```gleam
// Source: Derived from user decisions in 03-CONTEXT.md
import gleam/json
import gleam/dynamic/decode
import lattice/g_counter.{type GCounter}
import lattice/pn_counter.{type PNCounter}
import lattice/lww_register.{type LWWRegister}
import lattice/mv_register.{type MVRegister}
import lattice/g_set.{type GSet}
import lattice/two_p_set.{type TwoPSet}
import lattice/or_set.{type ORSet}
import lattice/lww_map.{type LWWMap}
import lattice/or_map.{type ORMap}

pub type Crdt {
  CrdtGCounter(GCounter)
  CrdtPnCounter(PNCounter)
  CrdtLwwRegister(LWWRegister(String))  // note: type param needs resolution — see Open Questions
  CrdtMvRegister(MVRegister(String))
  CrdtGSet(GSet(String))
  CrdtTwoPSet(TwoPSet(String))
  CrdtOrSet(ORSet(String))
  CrdtLwwMap(LWWMap)
  CrdtOrMap(ORMap)
}

// Generic encoder: reads the tag and dispatches
pub fn to_json(crdt: Crdt) -> json.Json {
  case crdt {
    CrdtGCounter(c) -> g_counter.to_json(c)
    CrdtPnCounter(c) -> pn_counter.to_json(c)
    // ...
  }
}

// Generic decoder: reads "type" field and dispatches
pub fn from_json(json_string: String) -> Result(Crdt, json.DecodeError) {
  let type_decoder = {
    use type_tag <- decode.field("type", decode.string)
    decode.success(type_tag)
  }
  case json.parse(from: json_string, using: type_decoder) {
    Error(e) -> Error(e)
    Ok("g_counter") ->
      json.parse(from: json_string, using: g_counter_crdt_decoder())
    Ok("pn_counter") ->
      json.parse(from: json_string, using: pn_counter_crdt_decoder())
    // ...
    Ok(unknown) ->
      Error(json.UnableToDecode([]))  // or a meaningful error
  }
}

// Generic merge: dispatch to type-specific merge
pub fn merge(a: Crdt, b: Crdt) -> Crdt {
  case a, b {
    CrdtGCounter(ca), CrdtGCounter(cb) -> CrdtGCounter(g_counter.merge(ca, cb))
    CrdtPnCounter(ca), CrdtPnCounter(cb) -> CrdtPnCounter(pn_counter.merge(ca, cb))
    // ...
    _, _ -> a  // mismatched types: take first (or panic — see Open Questions)
  }
}
```

### Pattern 4: LWW-Map Internal Representation
**What:** A dict where each entry stores both the value and a timestamp together
**When to use:** LWW-Map — Claude's discretion area
**Recommended approach:** `Dict(String, #(String, Int))` — tuple of (value, timestamp) per key
**Example:**
```gleam
// Recommended internal representation
pub type LWWMap {
  LWWMap(entries: dict.Dict(String, #(String, Int)))
}

pub fn new() -> LWWMap {
  LWWMap(entries: dict.new())
}

pub fn set(map: LWWMap, key: String, value: String, timestamp: Int) -> LWWMap {
  let LWWMap(entries) = map
  let should_update = case dict.get(entries, key) {
    Error(_) -> True
    Ok(#(_, existing_ts)) -> timestamp > existing_ts
  }
  case should_update {
    True -> LWWMap(entries: dict.insert(entries, key, #(value, timestamp)))
    False -> map
  }
}

pub fn get(map: LWWMap, key: String) -> Result(String, Nil) {
  let LWWMap(entries) = map
  case dict.get(entries, key) {
    Ok(#(value, _)) -> Ok(value)
    Error(_) -> Error(Nil)
  }
}

pub fn merge(a: LWWMap, b: LWWMap) -> LWWMap {
  let LWWMap(entries_a) = a
  let LWWMap(entries_b) = b
  let all_keys =
    list.unique(list.append(dict.keys(entries_a), dict.keys(entries_b)))
  let merged =
    list.fold(all_keys, dict.new(), fn(acc, key) {
      let entry_a = dict.get(entries_a, key)
      let entry_b = dict.get(entries_b, key)
      let winner = case entry_a, entry_b {
        Ok(#(_, ts_a) as ea), Ok(#(_, ts_b)) ->
          case ts_a >= ts_b { True -> ea  False -> result.unwrap(entry_b, ea) }
        Ok(ea), Error(_) -> ea
        Error(_), Ok(eb) -> eb
        Error(_), Error(_) -> #("", 0)  // unreachable
      }
      dict.insert(acc, key, winner)
    })
  LWWMap(entries: merged)
}
```

Note: LWW-Map uses `String` keys and `String` values for simplicity in v1. The internal type can be generalized later. This is consistent with the OR-Set of String keys used for OR-Map.

### Pattern 5: OR-Map Design
**What:** Combines OR-Set (for key tracking with add-wins semantics) and a Dict (for CRDT values)
**When to use:** OR-Map — the most complex type in this phase
**Recommended approach:**
```gleam
import lattice/or_set.{type ORSet}
import lattice/crdt.{type Crdt}

pub type CrdtSpec {
  GCounterSpec
  PnCounterSpec
  LwwRegisterSpec
  MvRegisterSpec
  GSetSpec
  TwoPSetSpec
  OrSetSpec
}

pub type ORMap {
  ORMap(
    replica_id: String,
    crdt_spec: CrdtSpec,    // what kind of CRDT to auto-create for new keys
    key_set: ORSet(String), // OR-Set for add-wins key semantics
    values: dict.Dict(String, Crdt),  // actual CRDT values per key
  )
}

pub fn new(replica_id: String, crdt_spec: CrdtSpec) -> ORMap {
  ORMap(
    replica_id: replica_id,
    crdt_spec: crdt_spec,
    key_set: or_set.new(replica_id),
    values: dict.new(),
  )
}

pub fn update(map: ORMap, key: String, f: fn(Crdt) -> Crdt) -> ORMap {
  let ORMap(replica_id, crdt_spec, key_set, values) = map
  // Auto-create if key doesn't exist
  let current = case dict.get(values, key) {
    Ok(crdt) -> crdt
    Error(_) -> default_crdt(crdt_spec, replica_id)
  }
  let updated = f(current)
  ORMap(
    replica_id: replica_id,
    crdt_spec: crdt_spec,
    key_set: or_set.add(key_set, key),
    values: dict.insert(values, key, updated),
  )
}

pub fn remove(map: ORMap, key: String) -> ORMap {
  let ORMap(replica_id, crdt_spec, key_set, values) = map
  ORMap(
    replica_id: replica_id,
    crdt_spec: crdt_spec,
    key_set: or_set.remove(key_set, key),
    values: values,  // keep value in dict — will be excluded from keys()/values() output
  )
}

pub fn merge(a: ORMap, b: ORMap) -> ORMap {
  let ORMap(replica_id, crdt_spec, key_set_a, values_a) = a
  let ORMap(_, _, key_set_b, values_b) = b
  let merged_key_set = or_set.merge(key_set_a, key_set_b)
  // For each key in union of both values dicts, merge the CRDT values
  let all_value_keys =
    list.unique(list.append(dict.keys(values_a), dict.keys(values_b)))
  let merged_values =
    list.fold(all_value_keys, dict.new(), fn(acc, key) {
      let merged_crdt = case dict.get(values_a, key), dict.get(values_b, key) {
        Ok(ca), Ok(cb) -> crdt.merge(ca, cb)
        Ok(ca), Error(_) -> ca
        Error(_), Ok(cb) -> cb
        Error(_), Error(_) -> panic  // unreachable
      }
      dict.insert(acc, key, merged_crdt)
    })
  ORMap(
    replica_id: replica_id,
    crdt_spec: crdt_spec,
    key_set: merged_key_set,
    values: merged_values,
  )
}

// keys() and values() only return active keys (those in the OR-Set)
pub fn keys(map: ORMap) -> List(String) {
  let ORMap(_, _, key_set, _) = map
  set.to_list(or_set.value(key_set))
}

pub fn values(map: ORMap) -> List(Crdt) {
  let ORMap(_, _, key_set, values) = map
  let active_keys = or_set.value(key_set)
  dict.filter(values, fn(key, _) { set.contains(active_keys, key) })
  |> dict.values
}
```

### Pattern 6: OR-Set/G-Set JSON Encoding (set.Set round-trip)
**What:** `gleam/set.Set` is not directly JSON-serializable; must convert to/from list
**When to use:** G-Set, 2P-Set, any type with `set.Set` internals
**Example:**
```gleam
// Encoding set.Set
import gleam/set
import gleam/json

pub fn encode_set(s: set.Set(String)) -> json.Json {
  json.array(set.to_list(s), of: json.string)
}

// Decoding set.Set
import gleam/dynamic/decode

pub fn set_decoder() -> decode.Decoder(set.Set(String)) {
  decode.map(decode.list(decode.string), set.from_list)
}
```

### Pattern 7: OR-Set Tags JSON Encoding
**What:** `set.Set(Tag)` where `Tag` is `Tag(replica_id: String, counter: Int)` — must encode as list of objects
**When to use:** OR-Set `entries` field (Dict(a, set.Set(Tag))), MV-Register entries
**Example:**
```gleam
// Encoding a single Tag
pub fn encode_tag(tag: or_set.Tag) -> json.Json {
  let or_set.Tag(replica_id, counter) = tag
  json.object([
    #("r", json.string(replica_id)),
    #("c", json.int(counter)),
  ])
}

// Decoding a Tag
pub fn tag_decoder() -> decode.Decoder(or_set.Tag) {
  use replica_id <- decode.field("r", decode.string)
  use counter <- decode.field("c", decode.int)
  decode.success(or_set.Tag(replica_id: replica_id, counter: counter))
}

// Encoding entries: Dict(element, set.Set(Tag)) — for OR-Set
// Since keys can be any comparable type but in practice are String:
pub fn encode_entries(entries: dict.Dict(String, set.Set(or_set.Tag))) -> json.Json {
  json.dict(
    entries,
    keys: fn(k) -> k,
    values: fn(tag_set) {
      json.array(set.to_list(tag_set), of: encode_tag)
    },
  )
}
```

### Pattern 8: Round-Trip Property Test
**What:** `from_json(json.to_string(to_json(x)))` should equal `Ok(x)`
**When to use:** TEST-07 — serialization round-trip tests for all types
**Example:**
```gleam
// Source: Derived from existing property test patterns in test/property/
import qcheck
import startest/expect

fn small_test_config() -> qcheck.Config {
  qcheck.config(test_count: 10, max_retries: 3, seed: qcheck.seed(42))
}

pub fn g_counter_round_trip__test() {
  qcheck.run(
    small_test_config(),
    qcheck.map2(
      qcheck.small_non_negative_int(),
      qcheck.small_non_negative_int(),
      fn(a_delta, b_delta) { #(a_delta, b_delta) },
    ),
    fn(pair) {
      let #(a_delta, b_delta) = pair
      let original =
        g_counter.new("A")
        |> g_counter.increment(a_delta)
      let encoded = json.to_string(g_counter.to_json(original))
      let decoded = g_counter.from_json(encoded)
      decoded |> expect.to_equal(Ok(original))
      Nil
    },
  )
}
```

### Anti-Patterns to Avoid
- **Serializing `gleam/set.Set` directly:** Sets must be converted to lists first (`set.to_list`), then decoded back with `set.from_list`. JSON has no native set type.
- **Using `json.to_string_tree` when `json.to_string` is expected:** `to_string_tree` returns `StringTree`, not `String`. Use `json.to_string` for the `from_json(json_string: String)` function signature.
- **Forgetting the type wrapper in nested CRDT JSON:** The OR-Map stores CRDT values as nested typed JSON. Each nested CRDT must include its `"type"` tag so the generic decoder can dispatch correctly.
- **Circular module dependencies:** `lattice/crdt.gleam` imports all CRDT modules; those modules must NOT import `lattice/crdt.gleam`. The `Crdt` union is only needed by `or_map.gleam` and `crdt.gleam` itself. Keep imports one-directional.
- **LWW-Map remove semantics:** Two approaches exist — (a) delete the key (simplest, but merge can resurrect deleted keys if the other side still has them), (b) keep a tombstone entry with a high timestamp. Approach (b) is correct for LWW semantics: a delete at timestamp T should win over any set at timestamp < T.
- **OR-Map mismatched CRDT type merge:** When merging two OR-Maps, if both have a value for key "x" but one is `CrdtGCounter` and the other `CrdtPnCounter`, the `crdt.merge` dispatch will hit a type mismatch. This shouldn't happen if both maps were created with the same `crdt_spec`, but the merge function should handle the mismatch gracefully (e.g., prefer the first argument's value).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON serialization | Custom string builder | `gleam_json` (3.1.0) | Handles escaping, numeric formatting, cross-target compat |
| Set encoding | Custom set → JSON | `set.to_list` + `json.array` | Single line; set.to_list is stdlib |
| Dict encoding | Manual iteration | `json.dict(d, keys: fn(k) -> k, values: json.int)` | Direct API, String-keyed dicts map exactly |
| Decoder composition | Nested case matching | `use` syntax with `decode.field` | Monadic chaining; automatic error propagation |
| Key union for LWW-Map merge | Custom dedup | `list.unique(list.append(dict.keys(a), dict.keys(b)))` | Established pattern from g_counter.gleam |
| OR-Set key management in OR-Map | Custom tag tracking | Reuse `lattice/or_set.gleam` directly | Already correct and tested |

**Key insight:** `gleam_json` handles all the cross-target (Erlang/JS) differences internally. Never use target-specific JSON (like Erlang's `jsx` or `jiffy`) directly — they won't work on JS target.

## Common Pitfalls

### Pitfall 1: LWW-Map Remove Semantics — Resurrection Bug
**What goes wrong:** `remove` deletes a key from the dict. But when merging with a peer that still has the key (at an older timestamp), the key reappears.
**Why it happens:** Delete-then-merge is not monotone. The delete information is lost.
**How to avoid:** Use timestamp-based tombstones. A remove at timestamp T inserts a sentinel entry `#(tombstone_sentinel, T)`. During merge, if both sides have the key, the higher-timestamp entry wins — including tombstones. Define a `Tombstone` variant or use a well-known sentinel string like `"__deleted__"` with a maximum possible timestamp.
**Warning signs:** Test `set at ts=5, remove, merge with peer that has ts=3` — removed key reappears after merge.

### Pitfall 2: gleam/set.Set Ordering and Equality in Round-Trip Tests
**What goes wrong:** `from_json(to_json(g_set))` succeeds but `expect.to_equal` fails because `set.from_list(set.to_list(s))` may not produce identical internal structure.
**Why it happens:** `set.to_list` order is implementation-defined. If the decoder reconstructs via `set.from_list`, the result should be structurally equal since `gleam/set` is likely a balanced BST — but if list order matters for reconstruction, equality may fail.
**How to avoid:** In round-trip tests, compare `set.to_list(value(original))` vs `set.to_list(value(decoded))` after sorting, rather than structural equality of the full CRDT record. Alternatively, test `value(from_json(to_json(x))) == value(x)` (observable equality, not structural equality).
**Warning signs:** `expect.to_equal` fails on round-trip despite correct JSON content.

### Pitfall 3: Dict Equality in Round-Trip Tests for G-Counter, VersionVector
**What goes wrong:** `GCounter(dict: d, self_id: "A")` reconstructed from JSON has identical content but `==` returns False.
**Why it happens:** Gleam's `gleam/dict.Dict` equality uses structural equality. If the internal tree structure differs (different insertion order), two dicts with same key-value pairs may not be `==`.
**How to avoid:** Gleam's `dict.Dict` is backed by a Erlang map / JS Map — equality is defined as content equality (same key-value pairs), not structural. This should work correctly. If tests fail, compare with `dict.to_list |> list.sort`.
**Warning signs:** Round-trip test fails on G-Counter or VersionVector despite correct values.

### Pitfall 4: MV-Register and OR-Set Tag Reconstruction
**What goes wrong:** After decoding from JSON, `Tag` records in `entries` dict are reconstructed but the `dict.Dict(Tag, value)` has different internal structure because dict key order changed.
**Why it happens:** `Tag` is a custom type used as a dict key. Gleam's dict uses structural comparison for custom type keys — this should work, but if the dict is encoded as a list and decoded, the insertion order may differ.
**How to avoid:** For MV-Register and OR-Set round-trip tests, compare observable values: `list.sort(value(original))` vs `list.sort(value(decoded))` rather than structural record equality.
**Warning signs:** MV-Register or OR-Set round-trip test fails despite correct JSON content.

### Pitfall 5: Gleam Type Parameters in Crdt Union
**What goes wrong:** `CrdtLwwRegister(LWWRegister(String))` — but the user's LWW-Register stores arbitrary `a`. If the OR-Map is typed over `LWWRegister(String)`, it can't hold `LWWRegister(Int)`.
**Why it happens:** Gleam is statically typed; the `Crdt` union must fix the type parameter for parameterized CRDTs.
**How to avoid:** For v1, the `Crdt` union constrains all parameterized types to `String`. This is explicitly a v1 simplification. Document this in the `Crdt` type's doc comment. OR-Map can only hold String-valued CRDTs in v1.
**Warning signs:** Gleam type error when trying to put `LWWRegister(Int)` into a `Crdt` union variant.

### Pitfall 6: Circular Imports Between crdt.gleam and Other Modules
**What goes wrong:** `lattice/crdt.gleam` imports `lattice/g_counter`, which imports `lattice/crdt` — cycle.
**Why it happens:** If any existing module imports `lattice/crdt` for the `Crdt` type, circular dependency occurs.
**How to avoid:** Only `lattice/or_map.gleam` and `lattice/crdt.gleam` should import the `Crdt` type. No existing CRDT module should import `lattice/crdt`. The data flows one way: crdt.gleam imports all leaf modules, not vice versa.
**Warning signs:** Gleam compiler error: "Circular dependency detected."

### Pitfall 7: qcheck Shrinking Timeout (Established Constraint from Phase 1)
**What goes wrong:** Property tests time out when qcheck tries to shrink failing cases.
**Why it happens:** Complex generators with nested structures cause deep shrinking search.
**How to avoid:** Always use `small_test_config()` with `test_count: 10, max_retries: 3, seed: qcheck.seed(42)`. Keep generators simple (bounded_int, small_non_negative_int). Do NOT generate full CRDT structures with qcheck — construct them deterministically in the test body.
**Warning signs:** `gleam test` hangs for > 30 seconds on a property test.

## Code Examples

Verified patterns from official sources and codebase:

### gleam_json Encoding — Complete Function Signatures
```gleam
// Source: https://hexdocs.pm/gleam_json/gleam/json.html (verified 2026-03-01)

// Primitive encoders
json.string(input: String) -> Json
json.int(input: Int) -> Json
json.float(input: Float) -> Json
json.bool(input: Bool) -> Json
json.null() -> Json

// Container encoders
json.object(entries: List(#(String, Json))) -> Json
json.array(from: List(a), of: fn(a) -> Json) -> Json
json.dict(dict: Dict(k, v), keys: fn(k) -> String, values: fn(v) -> Json) -> Json
json.nullable(from: Option(a), of: fn(a) -> Json) -> Json
json.preprocessed_array(from: List(Json)) -> Json

// Output
json.to_string(json: Json) -> String
json.to_string_tree(json: Json) -> StringTree  // higher perf, different return type
```

### gleam/dynamic/decode — Complete Decoder API
```gleam
// Source: https://hexdocs.pm/gleam_stdlib/gleam/dynamic/decode.html (verified 2026-03-01)

// Primitive decoders
decode.string  // Decoder(String)
decode.int     // Decoder(Int)
decode.float   // Decoder(Float)
decode.bool    // Decoder(Bool)

// Container decoders
decode.list(inner: Decoder(a)) -> Decoder(List(a))
decode.dict(key: Decoder(k), value: Decoder(v)) -> Decoder(Dict(k, v))
decode.optional(inner: Decoder(a)) -> Decoder(Option(a))

// Field access
decode.field(name: String, decoder: Decoder(a), next: fn(a) -> Decoder(b)) -> Decoder(b)
decode.optional_field(key: String, default: a, decoder: Decoder(a), next: fn(a) -> Decoder(b)) -> Decoder(b)

// Composition
decode.success(value: a) -> Decoder(a)
decode.failure(placeholder: a, expected: String) -> Decoder(a)
decode.map(decoder: Decoder(a), fn(a) -> b) -> Decoder(b)

// Entry point
json.parse(from: String, using: Decoder(t)) -> Result(t, DecodeError)
```

### dict.Dict(String, Int) Round-Trip (VersionVector Pattern)
```gleam
// Encoding — verified with json.dict API
import gleam/dict
import gleam/json

let d: dict.Dict(String, Int) = dict.from_list([#("A", 3), #("B", 1)])
let encoded: json.Json = json.dict(d, keys: fn(k) -> k, values: json.int)
// -> {"A":3,"B":1}

// Decoding
import gleam/dynamic/decode
let decoder = decode.field("clocks", decode.dict(decode.string, decode.int))
// Returns Dict(String, Int) directly — no list conversion needed
```

### set.Set Round-Trip Pattern
```gleam
// Encoding
import gleam/set
import gleam/json

let s = set.from_list(["alpha", "beta", "gamma"])
let encoded = json.array(set.to_list(s), of: json.string)

// Decoding
import gleam/dynamic/decode
let decoder = decode.map(decode.list(decode.string), set.from_list)
```

### Complete G-Counter JSON Example (JSON-01 + JSON-02)
```gleam
// to_json
pub fn to_json(counter: GCounter) -> json.Json {
  let GCounter(d, self_id) = counter
  json.object([
    #("type", json.string("g_counter")),
    #("v", json.int(1)),
    #("state", json.object([
      #("self_id", json.string(self_id)),
      #("counts", json.dict(d, keys: fn(k) -> k, values: json.int)),
    ])),
  ])
}

// from_json
pub fn from_json(json_string: String) -> Result(GCounter, json.DecodeError) {
  let decoder = {
    use _type <- decode.field("type", decode.string)
    use _v <- decode.field("v", decode.int)
    use state <- decode.field("state", {
      use self_id <- decode.field("self_id", decode.string)
      use counts <- decode.field("counts", decode.dict(decode.string, decode.int))
      decode.success(GCounter(dict: counts, self_id: self_id))
    })
    decode.success(state)
  }
  json.parse(from: json_string, using: decoder)
}

// Round-trip
let counter = g_counter.new("A") |> g_counter.increment(5)
let json_str = json.to_string(g_counter.to_json(counter))
// -> {"type":"g_counter","v":1,"state":{"self_id":"A","counts":{"A":5}}}
let result = g_counter.from_json(json_str)
// -> Ok(GCounter(dict: {"A": 5}, self_id: "A"))
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `gleam/dynamic` with `dynamic.field` | `gleam/dynamic/decode` with `use` syntax | gleam_stdlib ~0.34+ | Monadic decoder composition; no manual `result.try` chains |
| Custom JSON building with string concatenation | `gleam_json` library | Pre-library era | Correct escaping, cross-target support |
| Separate serialization package | `to_json/from_json` in each CRDT module | User decision (CONTEXT.md) | Simpler import graph; no companion package needed |
| qcheck with default config | `small_test_config()` with bounded shrinking | Discovered Phase 1 | Prevents timeout |

**Deprecated/outdated:**
- `gleam/dynamic.field`: The old `gleam/dynamic` module had direct field access functions. The new `gleam/dynamic/decode` module (used with `json.parse`) is the current API. Do NOT use the old `gleam/dynamic` approach.
- `json.decode`: Older API — the current API is `json.parse(from: ..., using: ...)`.

## Open Questions

1. **LWW-Map remove tombstone design**
   - What we know: Simple delete loses information across merges; timestamped tombstones are correct
   - What's unclear: Whether to use a separate tombstone set (like 2P-Set) or a sentinel value in the main dict
   - Recommendation (Claude's discretion): Use a sentinel in the main dict — `Dict(String, #(Option(String), Int))` where `None` means deleted. This keeps the dict as single source of truth. On `remove(key, timestamp)`, insert `#(None, timestamp)`. On `get`, return `Error(Nil)` if value is `None`. On `merge`, pairwise max timestamp wins (including tombstones).

2. **Crdt union type parameter fixation**
   - What we know: Gleam can't have `Crdt` hold `LWWRegister(a)` for polymorphic `a`; must fix `a`
   - What's unclear: Whether v1 restricts all parameterized CRDTs to `String` values
   - Recommendation: Yes, fix to `String` for v1. Document that OR-Map supports only String-valued CRDTs. This is consistent with the JSON-05 requirement (LWW-Register encoder for String values).

3. **Cross-target test strategy for TEST-08**
   - What we know: gleam_json is cross-target; any Gleam code that uses only gleam_stdlib + gleam_json is portable
   - What's unclear: How to actually verify Erlang-encoded JSON decodes on JS target in a single test run
   - Recommendation: The simplest form of TEST-08 is to encode a CRDT to JSON string on one target and decode it on the same target (proving the format is valid JSON). True cross-target testing requires running the test suite on both targets (`gleam test --target erlang` and `gleam test --target javascript`). For Phase 3, define the test as: "JSON produced by to_json is valid JSON that from_json can parse" — ensuring no BEAM-specific types leak into the encoding. Actual cross-target execution can be verified in CI.

4. **OR-Map `crdt_spec` vs carrying a `Crdt` default value**
   - What we know: The OR-Map needs to auto-create CRDT values for new keys
   - What's unclear: Whether `crdt_spec` should be a tag enum (as shown above) or a function `fn(replica_id) -> Crdt`
   - Recommendation: A tag enum `CrdtSpec` is simpler and serializable (can include in OR-Map JSON). A function would not be serializable. Use the enum approach.

## Validation Architecture

`workflow.nyquist_validation` is not present in `.planning/config.json` (config has `workflow.research`, `workflow.plan_check`, `workflow.verifier`, `workflow.auto_advance` but no `nyquist_validation` key) — skipping this section.

## Sources

### Primary (HIGH confidence)
- `https://hexdocs.pm/gleam_json/gleam/json.html` — Full gleam_json 3.1.0 API verified; all encoding functions confirmed
- `https://hexdocs.pm/gleam_stdlib/gleam/dynamic/decode.html` — Full decode API verified; field, list, dict, optional, success, map confirmed
- `/Volumes/Code/claude-workspace-ccl/lattice/manifest.toml` — gleam_json 3.1.0 confirmed in dependency graph
- `/Volumes/Code/claude-workspace-ccl/lattice/src/lattice/*.gleam` — All 8 existing CRDT modules read; internal types confirmed non-opaque
- Context7 `/gleam-lang/json` — API examples cross-verified with hexdocs

### Secondary (MEDIUM confidence)
- `/Volumes/Code/claude-workspace-ccl/lattice/.planning/phases/02-registers-sets/02-RESEARCH.md` — Established patterns (qcheck config, dict merge pattern) reused; verified against actual code
- OR-Map design derived from published CRDT literature (Shapiro et al. "A Comprehensive Study of CRDTs", 2011) adapted for the OR-Set-based key management pattern

### Tertiary (LOW confidence)
- OR-Map tombstone/remove design (keeping values dict after OR-Set remove): standard approach from distributed systems literature; not verified against a specific Gleam implementation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — gleam_json 3.1.0 API verified against hexdocs; all existing deps confirmed in manifest.toml
- Architecture: HIGH — Crdt union design follows directly from locked user decisions in CONTEXT.md; patterns derived from actual existing code
- Pitfalls: HIGH — type parameter fixation and circular import pitfalls are mathematical certainties in Gleam's type system; round-trip equality pitfall verified against gleam_json behavior; qcheck timeout confirmed Phase 1

**Research date:** 2026-03-01
**Valid until:** 2026-04-01 (gleam_json 3.1.0 is stable; decode API unlikely to change in this window)
