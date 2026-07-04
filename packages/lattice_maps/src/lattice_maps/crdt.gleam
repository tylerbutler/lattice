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
//// import lattice_maps/crdt
//// import lattice_core/replica_id
//// import lattice_counters/g_counter
////
//// let a = crdt.CrdtGCounter(g_counter.new(replica_id.new("node-a")) |> g_counter.increment(1))
//// let b = crdt.CrdtGCounter(g_counter.new(replica_id.new("node-b")) |> g_counter.increment(2))
//// let assert Ok(merged) = crdt.merge(a, b)
//// ```

import gleam/dynamic/decode
import gleam/json
import lattice_core/replica_id.{type ReplicaId}
import lattice_core/version_vector.{type VersionVector}
import lattice_counters/g_counter.{type GCounter}
import lattice_counters/pn_counter.{type PNCounter}
import lattice_registers/lww_register.{type LWWRegister}
import lattice_registers/mv_register.{type MVRegister}
import lattice_sets/g_set.{type GSet}
import lattice_sets/or_set.{type ORSet}
import lattice_sets/two_p_set.{type TwoPSet}

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

/// Error returned when merging two `Crdt` values of different types.
///
/// The `expected` and `found` fields contain human-readable type names
/// (e.g., `"g_counter"`, `"or_set"`).
pub type MergeError {
  TypeMismatch(expected: String, found: String)
}

/// Return a human-readable type name for a wrapped `Crdt` value.
pub fn type_name(value: Crdt) -> String {
  case value {
    CrdtGCounter(_) -> "g_counter"
    CrdtPnCounter(_) -> "pn_counter"
    CrdtLwwRegister(_) -> "lww_register"
    CrdtMvRegister(_) -> "mv_register"
    CrdtGSet(_) -> "g_set"
    CrdtTwoPSet(_) -> "two_p_set"
    CrdtOrSet(_) -> "or_set"
    CrdtVersionVector(_) -> "version_vector"
  }
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
/// - `LwwRegisterSpec` — empty string `""` at timestamp `0` for `replica_id` (bottom element)
/// - `MvRegisterSpec` — new MV-Register for `replica_id`
/// - `GSetSpec` / `TwoPSetSpec` — empty set (no replica needed)
/// - `OrSetSpec` — new OR-Set for `replica_id`
pub fn default_crdt(spec: CrdtSpec, replica_id: ReplicaId) -> Crdt {
  case spec {
    GCounterSpec -> CrdtGCounter(g_counter.new(replica_id))
    PnCounterSpec -> CrdtPnCounter(pn_counter.new(replica_id))
    LwwRegisterSpec -> CrdtLwwRegister(lww_register.new("", 0, replica_id))
    MvRegisterSpec -> CrdtMvRegister(mv_register.new(replica_id))
    GSetSpec -> CrdtGSet(g_set.new())
    TwoPSetSpec -> CrdtTwoPSet(two_p_set.new())
    OrSetSpec -> CrdtOrSet(or_set.new(replica_id))
  }
}

/// Return `True` when a wrapped CRDT matches the expected `CrdtSpec`.
pub fn matches_spec(value: Crdt, spec: CrdtSpec) -> Bool {
  case value, spec {
    CrdtGCounter(_), GCounterSpec -> True
    CrdtPnCounter(_), PnCounterSpec -> True
    CrdtLwwRegister(_), LwwRegisterSpec -> True
    CrdtMvRegister(_), MvRegisterSpec -> True
    CrdtGSet(_), GSetSpec -> True
    CrdtTwoPSet(_), TwoPSetSpec -> True
    CrdtOrSet(_), OrSetSpec -> True
    _, _ -> False
  }
}

/// Return an empty/identity delta for the given spec.
///
/// An empty delta is the join-semilattice bottom: merging it into any state
/// returns that state unchanged. `ORMap` uses this when accumulating deltas
/// across multiple mutations and as the per-key default when no value-CRDT
/// change is needed.
///
/// For most types this is identical to `default_crdt`. The exception is
/// `LwwRegisterSpec`, where the bottom is the same `(value="", timestamp=0)`
/// register; the `merge` semantics ensure it is dominated by any subsequent
/// real write at any positive timestamp.
pub fn default_delta(spec: CrdtSpec, replica_id: ReplicaId) -> Crdt {
  default_crdt(spec, replica_id)
}

/// Return `True` when a wrapped CRDT carries no observable change relative
/// to the bottom (default) state for the given spec and replica.
///
/// Used by `ORMap` to decide whether a value-CRDT delta is worth packaging
/// into the surrounding map delta. An empty delta merged into a remote is a
/// no-op, so emitting it would just waste bandwidth.
///
/// Implementation: structural equality against `default_delta(spec, rid)`.
/// A delta from a no-op mutation may still appear "non-empty" (e.g. a
/// `GCounter` carrying `{self_id: 0}` is structurally distinct from the
/// fresh empty counter); such cases produce a small but harmless delta.
pub fn is_empty_delta(
  value value: Crdt,
  spec spec: CrdtSpec,
  replica_id replica_id: ReplicaId,
) -> Bool {
  value == default_delta(spec, replica_id)
}

/// Dispatch merge to the type-specific merge function for matching variants.
///
/// If `a` and `b` hold the same variant, their inner values are merged using
/// the type-specific merge function and returned as `Ok(merged)`.
///
/// If `a` and `b` hold different variants, returns
/// `Error(TypeMismatch(expected: ..., found: ...))` where `expected` is the
/// type name of `a` and `found` is the type name of `b`.
pub fn merge(a: Crdt, b: Crdt) -> Result(Crdt, MergeError) {
  case a, b {
    CrdtGCounter(ca), CrdtGCounter(cb) ->
      Ok(CrdtGCounter(g_counter.merge(ca, cb)))
    CrdtPnCounter(ca), CrdtPnCounter(cb) ->
      Ok(CrdtPnCounter(pn_counter.merge(ca, cb)))
    CrdtLwwRegister(ca), CrdtLwwRegister(cb) ->
      Ok(CrdtLwwRegister(lww_register.merge(ca, cb)))
    CrdtMvRegister(ca), CrdtMvRegister(cb) ->
      Ok(CrdtMvRegister(mv_register.merge(ca, cb)))
    CrdtGSet(ca), CrdtGSet(cb) -> Ok(CrdtGSet(g_set.merge(ca, cb)))
    CrdtTwoPSet(ca), CrdtTwoPSet(cb) -> Ok(CrdtTwoPSet(two_p_set.merge(ca, cb)))
    CrdtOrSet(ca), CrdtOrSet(cb) -> Ok(CrdtOrSet(or_set.merge(ca, cb)))
    CrdtVersionVector(ca), CrdtVersionVector(cb) ->
      Ok(CrdtVersionVector(version_vector.merge(ca, cb)))
    _, _ -> Error(TypeMismatch(expected: type_name(a), found: type_name(b)))
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
