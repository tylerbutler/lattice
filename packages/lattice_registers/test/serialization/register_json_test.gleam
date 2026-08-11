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
