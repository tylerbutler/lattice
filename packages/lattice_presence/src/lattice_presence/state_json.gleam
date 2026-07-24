//// State JSON — serialization and deserialization for the presence CRDT
////
//// Provides JSON encoding and decoding of the `State` type for cross-node
//// replication.

import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/set
import lattice_presence/presence_state.{
  type Entry, type State, type Tag, Entry, Tag,
}

const max_meta_depth = 64

/// Encode a CRDT State to JSON
pub fn to_json(state: State) -> json.Json {
  let #(replica, context, clouds, values) =
    presence_state.replicated_parts(state)
  json.object([
    #("replica", json.string(replica)),
    #("context", encode_context(context)),
    #("clouds", encode_clouds(clouds)),
    #("values", encode_values(values)),
  ])
}

/// Encode a State to a JSON string
pub fn to_json_string(state: State) -> String {
  to_json(state) |> json.to_string
}

/// Decode a JSON string into a State
pub fn from_json(json_string: String) -> Result(State, json.DecodeError) {
  json.parse(from: json_string, using: decoder())
}

/// Decoder for the CRDT State type. Used by `from_json` and
/// available for embedding in larger decoders (e.g. sync envelope parsing).
pub fn decoder() -> decode.Decoder(State) {
  use replica <- decode.field("replica", decode.string)
  use context <- decode.field("context", context_decoder())
  use clouds <- decode.field("clouds", clouds_decoder())
  use values <- decode.field("values", values_decoder())
  decode.success(presence_state.from_replicated_parts(
    replica,
    context,
    clouds,
    values,
  ))
}

// ── Context (vector clock) ──────────────────────────────────────────

fn encode_context(context: dict.Dict(String, Int)) -> json.Json {
  context
  |> dict.to_list
  |> list.map(fn(kv) { #(kv.0, json.int(kv.1)) })
  |> json.object
}

fn context_decoder() -> decode.Decoder(dict.Dict(String, Int)) {
  decode.dict(decode.string, decode.int)
  |> decode.then(fn(context) {
    case all_dict_values(context, fn(clock) { clock >= 0 }) {
      True -> decode.success(context)
      False -> decode.failure(context, "non-negative context clocks")
    }
  })
}

// ── Clouds ──────────────────────────────────────────────────────────

fn encode_clouds(clouds: dict.Dict(String, set.Set(Int))) -> json.Json {
  clouds
  |> dict.to_list
  |> list.map(fn(kv) { #(kv.0, json.array(set.to_list(kv.1), json.int)) })
  |> json.object
}

fn clouds_decoder() -> decode.Decoder(dict.Dict(String, set.Set(Int))) {
  decode.dict(decode.string, decode.list(decode.int))
  |> decode.then(fn(d) {
    case all_cloud_clocks_positive(d) {
      True ->
        decode.success(
          dict.map_values(d, fn(_, clocks) { set.from_list(clocks) }),
        )
      False -> decode.failure(dict.new(), "positive cloud clocks")
    }
  })
}

// ── Values (Tag -> Entry) ───────────────────────────────────────────

fn encode_tag(tag: Tag) -> json.Json {
  json.object([
    #("replica", json.string(tag.replica)),
    #("clock", json.int(tag.clock)),
  ])
}

fn tag_decoder() -> decode.Decoder(Tag) {
  use replica <- decode.field("replica", decode.string)
  use clock <- decode.field("clock", decode.int)
  case clock > 0 {
    True -> decode.success(Tag(replica: replica, clock: clock))
    False ->
      decode.failure(Tag(replica: replica, clock: clock), "positive tag clock")
  }
}

fn encode_entry(entry: Entry) -> json.Json {
  json.object([
    #("topic", json.string(entry.topic)),
    #("key", json.string(entry.key)),
    #("pid", json.string(entry.pid)),
    // `meta` is embedded as a raw JSON value (not a stringified blob) so
    // payloads are smaller and self-describing on the wire. Decoding uses
    // `json_value_decoder` to reconstruct the `json.Json` opaque value.
    #("meta", entry.meta),
  ])
}

fn entry_decoder() -> decode.Decoder(Entry) {
  use topic <- decode.field("topic", decode.string)
  use key <- decode.field("key", decode.string)
  use pid <- decode.field("pid", decode.string)
  use meta <- decode.field("meta", json_value_decoder())
  decode.success(Entry(topic: topic, key: key, pid: pid, meta: meta))
}

fn encode_values(values: dict.Dict(Tag, Entry)) -> json.Json {
  values
  |> dict.to_list
  |> list.map(fn(kv) {
    json.object([
      #("tag", encode_tag(kv.0)),
      #("entry", encode_entry(kv.1)),
    ])
  })
  |> json.preprocessed_array
}

fn values_decoder() -> decode.Decoder(dict.Dict(Tag, Entry)) {
  decode.list({
    use tag <- decode.field("tag", tag_decoder())
    use entry <- decode.field("entry", entry_decoder())
    decode.success(#(tag, entry))
  })
  |> decode.map(dict.from_list)
}

// ── Helpers ─────────────────────────────────────────────────────────

fn all_dict_values(
  values: dict.Dict(String, Int),
  predicate: fn(Int) -> Bool,
) -> Bool {
  dict.fold(values, True, fn(valid, _, value) { valid && predicate(value) })
}

fn all_cloud_clocks_positive(values: dict.Dict(String, List(Int))) -> Bool {
  dict.fold(values, True, fn(valid, _, clocks) {
    valid && list.all(clocks, fn(clock) { clock > 0 })
  })
}

/// Decoder that reconstructs a json.Json value from parsed JSON. Uses
/// standard decoder combinators instead of BEAM-specific dynamic.classify
/// so the same code works on both the Erlang and JavaScript targets.
fn json_value_decoder() -> decode.Decoder(json.Json) {
  json_value_decoder_at(0)
}

fn json_value_decoder_at(depth: Int) -> decode.Decoder(json.Json) {
  case depth > max_meta_depth {
    True -> decode.failure(json.null(), "metadata depth within limit")
    False -> json_value_decoder_within_limit(depth)
  }
}

fn json_value_decoder_within_limit(depth: Int) -> decode.Decoder(json.Json) {
  decode.one_of(decode.string |> decode.map(json.string), [
    decode.int |> decode.map(json.int),
    decode.float |> decode.map(json.float),
    decode.bool |> decode.map(json.bool),
    decode.optional(decode.string)
      |> decode.then(fn(opt) {
        case opt {
          option.None -> decode.success(json.null())
          option.Some(_) -> decode.failure(json.null(), "null")
        }
      }),
    decode.list(decode.dynamic)
      |> decode.then(fn(items) { json_value_list(items, [], depth + 1) }),
    decode.dict(decode.string, decode.dynamic)
      |> decode.then(fn(d) {
        let pairs = dict.to_list(d)
        json_value_dict(pairs, [], depth + 1)
      }),
  ])
}

// `json_value_list` and `json_value_dict` share the same recursive
// structure but produce different `json.Json` shapes (array vs. object)
// and consume different element types. Unifying them through a higher-
// order helper obscures the decoder shape without saving real code, so
// they are kept as two parallel functions.
fn json_value_list(
  items: List(decode.Dynamic),
  acc: List(json.Json),
  depth: Int,
) -> decode.Decoder(json.Json) {
  case items {
    [] -> decode.success(json.preprocessed_array(list.reverse(acc)))
    [item, ..rest] ->
      case decode.run(item, json_value_decoder_at(depth)) {
        Ok(val) -> json_value_list(rest, [val, ..acc], depth)
        // Decode boundary: per-element decode errors are replaced with a
        // single domain-specific decoder failure.
        // nolint: thrown_away_error
        Error(_) -> decode.failure(json.null(), "valid JSON value in array")
      }
  }
}

fn json_value_dict(
  pairs: List(#(String, decode.Dynamic)),
  acc: List(#(String, json.Json)),
  depth: Int,
) -> decode.Decoder(json.Json) {
  case pairs {
    [] -> decode.success(json.object(list.reverse(acc)))
    [#(key, value), ..rest] ->
      case decode.run(value, json_value_decoder_at(depth)) {
        Ok(val) -> json_value_dict(rest, [#(key, val), ..acc], depth)
        // Decode boundary: per-field decode errors are replaced with a
        // single domain-specific decoder failure.
        // nolint: thrown_away_error
        Error(_) -> decode.failure(json.null(), "valid JSON value in object")
      }
  }
}
