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

/// Tagged union for all leaf CRDT types.
/// Parameterized types are fixed to String for v1.
/// Maps (LWW-Map, OR-Map) are composite containers and NOT included
/// in this union to avoid circular module dependencies.
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

/// Specifies which CRDT type an OR-Map holds.
/// Used to auto-create default values for new keys.
pub type CrdtSpec {
  GCounterSpec
  PnCounterSpec
  LwwRegisterSpec
  MvRegisterSpec
  GSetSpec
  TwoPSetSpec
  OrSetSpec
}

/// Create a new empty CRDT of the specified type for the given replica.
/// LWW-Register default is new("", 0) — empty string at timestamp 0 (bottom element).
/// G-Set and 2P-Set don't require a replica_id.
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

/// Dispatch merge to the type-specific merge function for matching Crdt variants.
/// On type mismatch, returns the first argument unchanged.
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

/// Dispatch to_json to the type-specific serializer.
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

/// Decode a Crdt from a JSON string produced by to_json.
/// Reads the "type" field to determine which type-specific decoder to use.
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
