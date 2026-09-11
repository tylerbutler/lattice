import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_registers/lww_register
import lattice_registers/mv_register

fn rid(id: String) {
  replica_id.new(id)
}

// LWW-Register round-trip tests

pub fn lww_register_to_json_simple_test() {
  let reg = lww_register.new("hello", 42, rid("test-replica"))
  let json_str = json.to_string(lww_register.to_json(reg))
  assert lww_register.from_json(json_str) == Ok(reg)
}

pub fn lww_register_round_trip_updated_test() {
  let reg =
    lww_register.new("initial", 1, rid("test-replica"))
    |> lww_register.set("updated", 100, rid("test-replica"))
  let json_str = json.to_string(lww_register.to_json(reg))
  assert lww_register.from_json(json_str) == Ok(reg)
}

pub fn lww_register_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"mv_register\",\"v\":2,\"state\":{\"value\":\"hello\",\"timestamp\":42,\"replica_id\":\"test\"}}"
  let assert Error(_) = lww_register.from_json(payload)
}

pub fn lww_register_from_json_wrong_version_rejected_test() {
  let payload =
    "{\"type\":\"lww_register\",\"v\":99,\"state\":{\"value\":\"hello\",\"timestamp\":42,\"replica_id\":\"test\"}}"
  let assert Error(_) = lww_register.from_json(payload)
}

pub fn lww_register_round_trip_preserves_metadata_test() {
  let reg = lww_register.new("hello", 42, rid("test-replica"))
  let json_str = json.to_string(lww_register.to_json(reg))
  let assert Ok(decoded) = lww_register.from_json(json_str)
  assert lww_register.timestamp(decoded) == 42
  assert lww_register.replica_id(decoded) == rid("test-replica")
}

/// The bootstrap case from issue #154: a client joining against a checkpoint
/// written by a replica whose clock ran ahead seeds its own clock from the
/// decoded register, so its first write to the key is not lost.
pub fn lww_register_snapshot_seeds_a_logical_clock_test() {
  // A peer checkpointed this at a wall-clock time ahead of ours.
  let checkpoint =
    json.to_string(
      lww_register.to_json(lww_register.new("painted", 5000, rid("peer"))),
    )

  let assert Ok(loaded) = lww_register.from_json(checkpoint)
  // Our wall clock is behind the checkpoint, so stamping from it alone
  // would drop the write.
  let our_clock = 4000
  let stamped = int.max(our_clock, lww_register.timestamp(loaded) + 1)

  let erased = lww_register.set(loaded, "erased", stamped, rid("local"))

  assert lww_register.value(erased) == "erased"
  assert lww_register.timestamp(erased) == 5001
  assert lww_register.replica_id(erased) == rid("local")
}

pub fn lww_register_from_json_v1_compat_test() {
  let payload =
    "{\"type\":\"lww_register\",\"v\":1,\"state\":{\"value\":\"hello\",\"timestamp\":42}}"
  let assert Ok(reg) = lww_register.from_json(payload)
  assert lww_register.value(reg) == "hello"
  assert lww_register.timestamp(reg) == 42
  // v1 envelopes carry no replica_id; it decodes to the empty id.
  assert lww_register.replica_id(reg) == rid("")
}

pub fn lww_register_v2_missing_replica_id_returns_precise_error_test() {
  let payload =
    "{\"type\":\"lww_register\",\"v\":2,\"state\":{\"value\":\"hello\",\"timestamp\":42}}"

  assert lww_register.from_json(payload)
    == Error(
      json.UnableToDecode([
        decode.DecodeError(expected: "Field", found: "Nothing", path: [
          "state",
          "replica_id",
        ]),
      ]),
    )
}

pub fn lww_register_v2_rejects_null_and_non_string_replica_ids_test() {
  use replica_id <- list.each(["null", "42", "true", "[]", "{}"])
  let payload =
    "{\"type\":\"lww_register\",\"v\":2,\"state\":{\"value\":\"hello\",\"timestamp\":42,\"replica_id\":"
    <> replica_id
    <> "}}"

  let assert Error(_) = lww_register.from_json(payload)
}

pub fn lww_register_v2_preserves_present_replica_ids_test() {
  use writer <- list.each(["writer", "", "\u{1f680} replica"])
  let original = lww_register.new("hello", 42, rid(writer))

  assert original
    |> lww_register.to_json()
    |> json.to_string()
    |> lww_register.from_json()
    == Ok(original)
}

// MV-Register round-trip tests

pub fn mv_register_to_json_simple_test() {
  let reg = mv_register.new(rid("A")) |> mv_register.set("hello")
  let json_str = json.to_string(mv_register.to_json(reg))
  let assert Ok(decoded) = mv_register.from_json(json_str)
  assert list.sort(mv_register.value(decoded), string.compare)
    == list.sort(mv_register.value(reg), string.compare)
}

pub fn mv_register_from_json_invalid_counter_test() {
  // Counter <= 0
  let json_str =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":0},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let assert Error(_) = mv_register.from_json(json_str)

  let json_str2 =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":-1},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let assert Error(_) = mv_register.from_json(json_str2)
}

pub fn mv_register_from_json_causality_violation_test() {
  // entry tag counter > vclock counter
  let json_str =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":2},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let assert Error(_) = mv_register.from_json(json_str)

  // missing from vclock
  let json_str2 =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"B\",\"c\":1},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let assert Error(_) = mv_register.from_json(json_str2)
}

pub fn mv_register_round_trip_concurrent_test() {
  // Simulate two concurrent writes from different replicas
  let a = mv_register.new(rid("A")) |> mv_register.set("from_a")
  let b = mv_register.new(rid("B")) |> mv_register.set("from_b")
  let merged = mv_register.merge(a, b)
  let json_str = json.to_string(mv_register.to_json(merged))
  let assert Ok(decoded) = mv_register.from_json(json_str)
  assert list.sort(mv_register.value(decoded), string.compare)
    == list.sort(mv_register.value(merged), string.compare)
}

type Payload {
  Payload(name: String, count: Int)
}

fn encode_payload(payload: Payload) -> json.Json {
  json.object([
    #("name", json.string(payload.name)),
    #("count", json.int(payload.count)),
  ])
}

fn payload_decoder() -> decode.Decoder(Payload) {
  use name <- decode.field("name", decode.string)
  use count <- decode.field("count", decode.int)
  decode.success(Payload(name, count))
}

pub fn lww_register_generic_int_and_historical_author_round_trip_test() {
  let original = lww_register.new(42, 12, rid("historical"))
  let assert Ok(loaded) =
    lww_register.to_json_with(original, json.int)
    |> json.to_string()
    |> lww_register.from_json_with(decode.int)
  assert loaded == original
  assert lww_register.set(loaded, 43, 12, rid("new")) == original
  let updated = lww_register.set(loaded, 43, 13, rid("new"))
  assert lww_register.to_json_with(updated, json.int)
    |> json.to_string()
    |> lww_register.from_json_with(decode.int)
    == Ok(lww_register.new(43, 13, rid("new")))
}

pub fn lww_register_generic_record_round_trip_test() {
  let original = lww_register.new(Payload("record", 42), 12, rid("A"))
  assert lww_register.to_json_with(original, encode_payload)
    |> json.to_string()
    |> lww_register.from_json_with(payload_decoder())
    == Ok(original)

  let v1 =
    "{\"type\":\"lww_register\",\"v\":1,\"state\":{\"value\":42,\"timestamp\":12}}"
  assert lww_register.from_json_with(v1, decode.int)
    == Ok(lww_register.new(42, 12, rid("")))
}

pub fn register_string_wire_formats_are_unchanged_test() {
  let lww = lww_register.new("value", 12, rid("A"))
  let lww_json = json.to_string(lww_register.to_json(lww))
  assert lww_json
    == "{\"type\":\"lww_register\",\"v\":2,\"state\":{\"value\":\"value\",\"timestamp\":12,\"replica_id\":\"A\"}}"
  assert lww_register.to_json_with(lww, json.string)
    |> json.to_string()
    == lww_json
  assert lww_register.from_json_with(lww_json, decode.string) == Ok(lww)

  let mv = mv_register.new(rid("A")) |> mv_register.set("value")
  let mv_json = json.to_string(mv_register.to_json(mv))
  assert mv_json
    == "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":1},\"value\":\"value\"}],\"vclock\":{\"A\":1}}}"
  assert mv_register.to_json_with(mv, json.string)
    |> json.to_string()
    == mv_json
  assert mv_register.from_json_with(mv_json, decode.string) == Ok(mv)
}

pub fn mv_register_generic_record_preserves_causal_history_test() {
  let a = mv_register.new(rid("A")) |> mv_register.set(Payload("a", 1))
  let b = mv_register.new(rid("B")) |> mv_register.set(Payload("b", 2))
  let concurrent = mv_register.merge(a, b)
  let assert Ok(loaded) =
    mv_register.to_json_with(concurrent, encode_payload)
    |> json.to_string()
    |> mv_register.from_json_with(payload_decoder())
  assert loaded == concurrent

  let #(updated, delta) = mv_register.set_with_delta(loaded, Payload("next", 3))
  let assert Ok(loaded_delta) =
    mv_register.to_json_with(delta, encode_payload)
    |> json.to_string()
    |> mv_register.from_json_with(payload_decoder())
  assert loaded_delta == delta
  assert mv_register.merge(concurrent, loaded_delta) == updated
  assert mv_register.merge(updated, a) == updated
  assert mv_register.merge(updated, b) == updated
}

pub fn mv_register_generic_int_round_trip_test() {
  let a = mv_register.new(rid("A")) |> mv_register.set(1)
  let b = mv_register.new(rid("B")) |> mv_register.set(2)
  let original = mv_register.merge(a, b) |> mv_register.set(3)
  let assert Ok(loaded) =
    mv_register.to_json_with(original, json.int)
    |> json.to_string()
    |> mv_register.from_json_with(decode.int)
  assert loaded == original
  assert mv_register.set(loaded, 4) == mv_register.set(original, 4)
}

pub fn register_generic_invalid_payloads_and_metadata_rejected_test() {
  let assert Error(_) =
    lww_register.new("not an int", 1, rid("A"))
    |> lww_register.to_json()
    |> json.to_string()
    |> lww_register.from_json_with(decode.int)

  let assert Error(_) =
    mv_register.new(rid("A"))
    |> mv_register.set("not a record")
    |> mv_register.to_json()
    |> json.to_string()
    |> mv_register.from_json_with(payload_decoder())

  use state <- list.each([
    "\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":2},\"value\":42}],\"vclock\":{\"A\":1}",
    "\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":0},\"value\":42}],\"vclock\":{\"A\":1}",
    "\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":1},\"value\":42},{\"tag\":{\"r\":\"A\",\"c\":1},\"value\":43}],\"vclock\":{\"A\":1}",
    "\"entries\":[],\"vclock\":{\"A\":-1}",
  ])
  let encoded =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\","
    <> state
    <> "}}"
  let assert Error(_) = mv_register.from_json_with(encoded, decode.int)
}
