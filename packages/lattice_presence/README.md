# lattice_presence

Distributed presence CRDT with topic/key/pid/meta tracking, add-wins merge semantics, replica visibility, and Phoenix-style diff reporting.

Use this package to track which users, devices, or processes are online across distributed nodes without requiring a central coordinator.

## Installation

```sh
gleam add lattice_presence
```

## Quick example

```gleam
import gleam/json
import lattice_presence/presence_state

pub fn main() {
  let state =
    presence_state.new_incarnation("node-a")
    |> presence_state.join(
      pid: "pid-1",
      topic: "room:lobby",
      key: "alice",
      meta: json.object([]),
    )

  presence_state.get_by_topic(state, "room:lobby")
  // -> [#("pid-1", "alice", json.object([]))]
}
```

## Modules

| Module | Purpose |
|--------|---------|
| `lattice_presence/presence_state` | Presence CRDT state, joins/leaves, merges, diffs, liveness, queries, and JSON encoding/decoding. |

## Serialization

Use `presence_state.to_json` or `presence_state.to_json_string` to encode state,
and `presence_state.from_json` to decode it. Use `presence_state.decoder()` to
decode state inside a larger sync envelope:

```gleam
import gleam/dynamic/decode
import gleam/json
import lattice_presence/presence_state

pub fn decode_sync(payload: String) {
  let decoder = {
    use kind <- decode.field("kind", decode.string)
    use state <- decode.field("state", presence_state.decoder())
    decode.success(#(kind, state))
  }
  json.parse(payload, decoder)
}
```

The JSON shape remains `replica`, `context`, `clouds`, and `values`, with no
type or version envelope. Context clocks must be non-negative; tag and cloud
clocks must be positive. Metadata is embedded JSON, supports null and nested
values, and is limited to depth 64 when decoded.

Local replica liveness is not encoded. Decoding marks only the state's own
replica as `Up` and retains its serialized identity. Merge a decoded remote
snapshot into the local state before making local edits.

**Migration:** Replace imports of `lattice_presence/state_json` with
`lattice_presence/presence_state`; the four codec function names are unchanged.
The old module and the `replicated_parts` / `from_replicated_parts` accessors
have been removed. Construct serialized fixtures through the public JSON decoder.

## Notes

- `presence_state` exposes `new`, `new_incarnation`, `join`, `leave`, `leave_by_pid`, `merge`, `merge_with_diff`, `online_list`, `get_by_topic`, and `get_by_key`.
- `merge` and `merge_with_diff` return `Result`; handle `SameReplica` by rejecting stale restart echoes or fixing duplicate replica names.
- The check also rejects unseen local-owned tags or causal history carried by another peer, including history whose entries have been removed. Gossip of already-known local tags remains valid; this check is not a substitute for unique incarnation identities.
- An identical state from the same replica is accepted as an idempotent no-op. Divergent states must use unique replica names.
- `merge_with_diff` reports Phoenix-style joins and leaves with the merged state on success.
- Replica identity uniqueness is per process incarnation. Use `new_incarnation` with a stable node name on every process start so peers cannot confuse new joins with causal history retained from an earlier run.
- A restarted state rejects cached values from earlier incarnations of its stable replica while retaining their causal context, so merging it back removes those stale entries from peers.
- Replica liveness is local-only: `replica_down` and `replica_up` affect local visibility and are not merged as replicated state.
- `remove_down_replica` permanently removes a down replica's entries while retaining its replicated causal high-water mark so stale gossip cannot restore them.
- Use `presence_state.to_json_string` and `presence_state.from_json` for persistence or transport.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_presence>
- Hex package: <https://hex.pm/packages/lattice_presence>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
