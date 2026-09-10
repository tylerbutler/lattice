import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lattice_core/replica_id
import lattice_registers/lww_register
import lattice_registers/mv_register
import startest/expect

fn rid(id: String) {
  replica_id.new(id)
}

// LWW-Register round-trip tests

pub fn lww_register_to_json_simple_test() {
  let reg = lww_register.new("hello", 42, rid("test-replica"))
  let json_str = json.to_string(lww_register.to_json(reg))
  lww_register.from_json(json_str)
  |> expect.to_equal(Ok(reg))
}

pub fn lww_register_round_trip_updated_test() {
  let reg =
    lww_register.new("initial", 1, rid("test-replica"))
    |> lww_register.set("updated", 100)
  let json_str = json.to_string(lww_register.to_json(reg))
  lww_register.from_json(json_str)
  |> expect.to_equal(Ok(reg))
}

pub fn lww_register_from_json_wrong_type_rejected_test() {
  let payload =
    "{\"type\":\"mv_register\",\"v\":2,\"state\":{\"value\":\"hello\",\"timestamp\":42,\"replica_id\":\"test\"}}"
  case lww_register.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn lww_register_from_json_wrong_version_rejected_test() {
  let payload =
    "{\"type\":\"lww_register\",\"v\":99,\"state\":{\"value\":\"hello\",\"timestamp\":42,\"replica_id\":\"test\"}}"
  case lww_register.from_json(payload) {
    Error(_) -> expect.to_be_true(True)
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn lww_register_round_trip_preserves_metadata_test() {
  let reg = lww_register.new("hello", 42, rid("test-replica"))
  let json_str = json.to_string(lww_register.to_json(reg))
  case lww_register.from_json(json_str) {
    Ok(decoded) -> {
      expect.to_equal(lww_register.timestamp(decoded), 42)
      expect.to_equal(lww_register.replica_id(decoded), rid("test-replica"))
    }
    Error(_) -> expect.to_be_true(False)
  }
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

  case lww_register.from_json(checkpoint) {
    Ok(loaded) -> {
      // Our wall clock is behind the checkpoint, so stamping from it alone
      // would drop the write.
      let our_clock = 4000
      let stamped = int.max(our_clock, lww_register.timestamp(loaded) + 1)

      let erased = lww_register.set(loaded, "erased", stamped)

      expect.to_equal(lww_register.value(erased), "erased")
      expect.to_equal(lww_register.timestamp(erased), 5001)
    }
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn lww_register_from_json_v1_compat_test() {
  let payload =
    "{\"type\":\"lww_register\",\"v\":1,\"state\":{\"value\":\"hello\",\"timestamp\":42}}"
  case lww_register.from_json(payload) {
    Ok(reg) -> {
      expect.to_equal(lww_register.value(reg), "hello")
      expect.to_equal(lww_register.timestamp(reg), 42)
      // v1 envelopes carry no replica_id; it decodes to the empty id.
      expect.to_equal(lww_register.replica_id(reg), rid(""))
    }
    Error(_) -> expect.to_be_true(False)
  }
}

// MV-Register round-trip tests

pub fn mv_register_to_json_simple_test() {
  let reg = mv_register.new(rid("A")) |> mv_register.set("hello")
  let json_str = json.to_string(mv_register.to_json(reg))
  let decoded = mv_register.from_json(json_str)
  case decoded {
    Ok(d) ->
      list.sort(mv_register.value(d), string.compare)
      |> expect.to_equal(list.sort(mv_register.value(reg), string.compare))
    Error(_) -> expect.to_be_true(False)
  }
}

pub fn mv_register_from_json_invalid_counter_test() {
  // Counter <= 0
  let json_str =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":0},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let decoded = mv_register.from_json(json_str)
  case decoded {
    Error(_) -> Nil
    Ok(_) -> expect.to_be_true(False)
  }

  let json_str2 =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":-1},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let decoded2 = mv_register.from_json(json_str2)
  case decoded2 {
    Error(_) -> Nil
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn mv_register_from_json_causality_violation_test() {
  // entry tag counter > vclock counter
  let json_str =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":2},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let decoded = mv_register.from_json(json_str)
  case decoded {
    Error(_) -> Nil
    Ok(_) -> expect.to_be_true(False)
  }

  // missing from vclock
  let json_str2 =
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"B\",\"c\":1},\"value\":\"bad\"}],\"vclock\":{\"A\":1}}}"
  let decoded2 = mv_register.from_json(json_str2)
  case decoded2 {
    Error(_) -> Nil
    Ok(_) -> expect.to_be_true(False)
  }
}

pub fn mv_register_round_trip_concurrent_test() {
  // Simulate two concurrent writes from different replicas
  let a = mv_register.new(rid("A")) |> mv_register.set("from_a")
  let b = mv_register.new(rid("B")) |> mv_register.set("from_b")
  let merged = mv_register.merge(a, b)
  let json_str = json.to_string(mv_register.to_json(merged))
  let decoded = mv_register.from_json(json_str)
  case decoded {
    Ok(d) ->
      list.sort(mv_register.value(d), string.compare)
      |> expect.to_equal(list.sort(mv_register.value(merged), string.compare))
    Error(_) -> expect.to_be_true(False)
  }
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
  loaded |> expect.to_equal(original)
  lww_register.set_as(loaded, 43, 12, rid("new"))
  |> expect.to_equal(original)
  let updated = lww_register.set_as(loaded, 43, 13, rid("new"))
  lww_register.to_json_with(updated, json.int)
  |> json.to_string()
  |> lww_register.from_json_with(decode.int)
  |> expect.to_equal(Ok(lww_register.new(43, 13, rid("new"))))
}

pub fn lww_register_generic_record_round_trip_test() {
  let original = lww_register.new(Payload("record", 42), 12, rid("A"))
  lww_register.to_json_with(original, encode_payload)
  |> json.to_string()
  |> lww_register.from_json_with(payload_decoder())
  |> expect.to_equal(Ok(original))

  let v1 =
    "{\"type\":\"lww_register\",\"v\":1,\"state\":{\"value\":42,\"timestamp\":12}}"
  lww_register.from_json_with(v1, decode.int)
  |> expect.to_equal(Ok(lww_register.new(42, 12, rid(""))))
}

pub fn register_string_wire_formats_are_unchanged_test() {
  let lww = lww_register.new("value", 12, rid("A"))
  let lww_json = json.to_string(lww_register.to_json(lww))
  lww_json
  |> expect.to_equal(
    "{\"type\":\"lww_register\",\"v\":2,\"state\":{\"value\":\"value\",\"timestamp\":12,\"replica_id\":\"A\"}}",
  )
  lww_register.to_json_with(lww, json.string)
  |> json.to_string()
  |> expect.to_equal(lww_json)
  lww_register.from_json_with(lww_json, decode.string)
  |> expect.to_equal(Ok(lww))

  let mv = mv_register.new(rid("A")) |> mv_register.set("value")
  let mv_json = json.to_string(mv_register.to_json(mv))
  mv_json
  |> expect.to_equal(
    "{\"type\":\"mv_register\",\"v\":1,\"state\":{\"replica_id\":\"A\",\"entries\":[{\"tag\":{\"r\":\"A\",\"c\":1},\"value\":\"value\"}],\"vclock\":{\"A\":1}}}",
  )
  mv_register.to_json_with(mv, json.string)
  |> json.to_string()
  |> expect.to_equal(mv_json)
  mv_register.from_json_with(mv_json, decode.string)
  |> expect.to_equal(Ok(mv))
}

pub fn mv_register_generic_record_preserves_causal_history_test() {
  let a = mv_register.new(rid("A")) |> mv_register.set(Payload("a", 1))
  let b = mv_register.new(rid("B")) |> mv_register.set(Payload("b", 2))
  let concurrent = mv_register.merge(a, b)
  let assert Ok(loaded) =
    mv_register.to_json_with(concurrent, encode_payload)
    |> json.to_string()
    |> mv_register.from_json_with(payload_decoder())
  loaded |> expect.to_equal(concurrent)

  let #(updated, delta) = mv_register.set_with_delta(loaded, Payload("next", 3))
  let assert Ok(loaded_delta) =
    mv_register.to_json_with(delta, encode_payload)
    |> json.to_string()
    |> mv_register.from_json_with(payload_decoder())
  loaded_delta |> expect.to_equal(delta)
  mv_register.merge(concurrent, loaded_delta) |> expect.to_equal(updated)
  mv_register.merge(updated, a) |> expect.to_equal(updated)
  mv_register.merge(updated, b) |> expect.to_equal(updated)
}

pub fn mv_register_generic_int_round_trip_test() {
  let a = mv_register.new(rid("A")) |> mv_register.set(1)
  let b = mv_register.new(rid("B")) |> mv_register.set(2)
  let original = mv_register.merge(a, b) |> mv_register.set(3)
  let assert Ok(loaded) =
    mv_register.to_json_with(original, json.int)
    |> json.to_string()
    |> mv_register.from_json_with(decode.int)
  loaded |> expect.to_equal(original)
  mv_register.set(loaded, 4) |> expect.to_equal(mv_register.set(original, 4))
}

pub fn register_generic_invalid_payloads_and_metadata_rejected_test() {
  lww_register.new("not an int", 1, rid("A"))
  |> lww_register.to_json()
  |> json.to_string()
  |> lww_register.from_json_with(decode.int)
  |> expect.to_be_error()

  mv_register.new(rid("A"))
  |> mv_register.set("not a record")
  |> mv_register.to_json()
  |> json.to_string()
  |> mv_register.from_json_with(payload_decoder())
  |> expect.to_be_error()

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
  mv_register.from_json_with(encoded, decode.int) |> expect.to_be_error()
}
