//// A tagged union over all leaf CRDT types with dynamic dispatch.
////
//// The `Crdt` type wraps individual CRDTs (counters, registers, sets) so they
//// can be stored and merged uniformly — this is how `ORMap` holds heterogeneous
//// values. For direct use, prefer the individual modules (e.g., `g_counter`,
//// `or_set`) for type-safe access.
////
//// Maps (`LWWMap`, `ORMap`) are **not** included in this union to avoid circular
//// module dependencies.
////
//// ## Example
////
//// ```gleam
//// import lattice/crdt
//// import lattice/g_counter
////
//// let a = crdt.CrdtGCounter(g_counter.new("node-a") |> g_counter.increment(1))
//// let b = crdt.CrdtGCounter(g_counter.new("node-b") |> g_counter.increment(2))
//// let merged = crdt.merge(a, b)
//// ```

import gleam/dynamic/decode
import gleam/json
import lattice/g_counter.{type GCounter}
import lattice/g_set.{type GSet}
import lattice/lww_register.{type LWWRegister}
import lattice/mv_register.{type MVRegister}
import lattice/or_set.{type ORSet}
import lattice/pn_counter.{type PNCounter}
import lattice/two_p_set.{type TwoPSet}
import lattice/version_vector.{type VersionVector}

/// A tagged union wrapping every leaf CRDT type in this library.
///
/// Variants:
/// - `CrdtGCounter` — grow-only counter
/// - `CrdtPnCounter` — increment/decrement counter
/// - `CrdtLwwRegister` — last-writer-wins register (String)
/// - `CrdtMvRegister` — multi-value register (String)
/// - `CrdtGSet` — grow-only set (String)
/// - `CrdtTwoPSet` — two-phase set (String)
/// - `CrdtOrSet` — observed-remove set (String)
/// - `CrdtVersionVector` — version vector
///
/// Parameterized types are fixed to `String` for v1. Maps (`LWWMap`,
/// `ORMap`) are composite containers and are **not** included in this union
/// to avoid circular module dependencies.
pub type Crdt {
  CrdtGCounter(GCounter)
  CrdtPnCounter(PNCounter)
  CrdtLwwRegister(LWWRegister(String))
  CrdtMvRegister(MVRegister(String))
  CrdtGSet(GSet(String))
  CrdtTwoPSet(TwoPSet(String))
  CrdtOrSet(ORSet(String))
  CrdtVersionVector(VersionVector)
}

/// Specifies which leaf CRDT type an `ORMap` holds as its values.
///
/// When `or_map.update` is called on a key that does not yet exist, the map
/// uses this spec to auto-create a default value via `default_crdt`. Choosing
/// the right spec at `or_map.new` time is important because changing the
/// value type after the fact would require migrating all existing values.
pub type CrdtSpec {
  GCounterSpec
  PnCounterSpec
  LwwRegisterSpec
  MvRegisterSpec
  GSetSpec
  TwoPSetSpec
  OrSetSpec
}

/// Create a new default (bottom) value of the specified CRDT type.
///
/// The `replica_id` is passed to CRDT constructors that require it
/// (counters, registers, OR-Set). For types that don't use a replica
/// identifier (G-Set, 2P-Set), the argument is ignored.
///
/// Default values per spec:
/// - `GCounterSpec` / `PnCounterSpec` — new counter for `replica_id`
/// - `LwwRegisterSpec` — empty string `""` at timestamp `0` (bottom element)
/// - `MvRegisterSpec` — new MV-Register for `replica_id`
/// - `GSetSpec` / `TwoPSetSpec` — empty set (no replica needed)
/// - `OrSetSpec` — new OR-Set for `replica_id`
pub fn default_crdt(spec: CrdtSpec, replica_id: String) -> Crdt {
  case spec {
    GCounterSpec -> CrdtGCounter(g_counter.new(replica_id))
    PnCounterSpec -> CrdtPnCounter(pn_counter.new(replica_id))
    LwwRegisterSpec -> CrdtLwwRegister(lww_register.new("", 0))
    MvRegisterSpec -> CrdtMvRegister(mv_register.new(replica_id))
    GSetSpec -> CrdtGSet(g_set.new())
    TwoPSetSpec -> CrdtTwoPSet(two_p_set.new())
    OrSetSpec -> CrdtOrSet(or_set.new(replica_id))
  }
}

/// Dispatch merge to the type-specific merge function for matching variants.
///
/// If `a` and `b` hold the same variant, their inner values are merged using
/// the type-specific merge function. On type mismatch (different variants),
/// `a` is returned unchanged. Type mismatches should not occur in a
/// well-formed system, but this behavior avoids a crash.
pub fn merge(a: Crdt, b: Crdt) -> Crdt {
  case a, b {
    CrdtGCounter(ca), CrdtGCounter(cb) -> CrdtGCounter(g_counter.merge(ca, cb))
    CrdtPnCounter(ca), CrdtPnCounter(cb) ->
      CrdtPnCounter(pn_counter.merge(ca, cb))
    CrdtLwwRegister(ca), CrdtLwwRegister(cb) ->
      CrdtLwwRegister(lww_register.merge(ca, cb))
    CrdtMvRegister(ca), CrdtMvRegister(cb) ->
      CrdtMvRegister(mv_register.merge(ca, cb))
    CrdtGSet(ca), CrdtGSet(cb) -> CrdtGSet(g_set.merge(ca, cb))
    CrdtTwoPSet(ca), CrdtTwoPSet(cb) -> CrdtTwoPSet(two_p_set.merge(ca, cb))
    CrdtOrSet(ca), CrdtOrSet(cb) -> CrdtOrSet(or_set.merge(ca, cb))
    CrdtVersionVector(ca), CrdtVersionVector(cb) ->
      CrdtVersionVector(version_vector.merge(ca, cb))
    _, _ -> a
    // Type mismatch: return first argument
  }
}

/// Dispatch `to_json` to the type-specific serializer for the wrapped CRDT.
///
/// Each variant delegates to its module's `to_json`. The resulting JSON
/// includes a `"type"` field (e.g., `"g_counter"`) that `from_json` uses
/// to select the correct decoder on deserialization.
pub fn to_json(crdt: Crdt) -> json.Json {
  case crdt {
    CrdtGCounter(c) -> g_counter.to_json(c)
    CrdtPnCounter(c) -> pn_counter.to_json(c)
    CrdtLwwRegister(c) -> lww_register.to_json(c)
    CrdtMvRegister(c) -> mv_register.to_json(c)
    CrdtGSet(c) -> g_set.to_json(c)
    CrdtTwoPSet(c) -> two_p_set.to_json(c)
    CrdtOrSet(c) -> or_set.to_json(c)
    CrdtVersionVector(c) -> version_vector.to_json(c)
  }
}

/// Decode a `Crdt` from a JSON string produced by `to_json`.
///
/// Reads the `"type"` field to determine which type-specific decoder to
/// use. Returns `Error` if the string is not valid JSON, the `"type"` field
/// is missing, or the type tag is not recognized.
pub fn from_json(json_string: String) -> Result(Crdt, json.DecodeError) {
  let type_decoder = {
    use type_tag <- decode.field("type", decode.string)
    decode.success(type_tag)
  }
  case json.parse(from: json_string, using: type_decoder) {
    Error(e) -> Error(e)
    Ok(type_tag) -> dispatch_decode(type_tag, json_string)
  }
}

fn dispatch_decode(
  type_tag: String,
  json_string: String,
) -> Result(Crdt, json.DecodeError) {
  case type_tag {
    "g_counter" ->
      case g_counter.from_json(json_string) {
        Ok(c) -> Ok(CrdtGCounter(c))
        Error(e) -> Error(e)
      }
    "pn_counter" ->
      case pn_counter.from_json(json_string) {
        Ok(c) -> Ok(CrdtPnCounter(c))
        Error(e) -> Error(e)
      }
    "lww_register" ->
      case lww_register.from_json(json_string) {
        Ok(c) -> Ok(CrdtLwwRegister(c))
        Error(e) -> Error(e)
      }
    "mv_register" ->
      case mv_register.from_json(json_string) {
        Ok(c) -> Ok(CrdtMvRegister(c))
        Error(e) -> Error(e)
      }
    "g_set" ->
      case g_set.from_json(json_string) {
        Ok(c) -> Ok(CrdtGSet(c))
        Error(e) -> Error(e)
      }
    "two_p_set" ->
      case two_p_set.from_json(json_string) {
        Ok(c) -> Ok(CrdtTwoPSet(c))
        Error(e) -> Error(e)
      }
    "or_set" ->
      case or_set.from_json(json_string) {
        Ok(c) -> Ok(CrdtOrSet(c))
        Error(e) -> Error(e)
      }
    "version_vector" ->
      case version_vector.from_json(json_string) {
        Ok(c) -> Ok(CrdtVersionVector(c))
        Error(e) -> Error(e)
      }
    _ ->
      Error(
        json.UnableToDecode([
          decode.DecodeError(
            expected: "known CRDT type",
            found: type_tag,
            path: ["type"],
          ),
        ]),
      )
  }
}
