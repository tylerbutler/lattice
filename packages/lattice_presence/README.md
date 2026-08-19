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
    presence_state.new("node-a")
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
| `lattice_presence/presence_state` | Presence CRDT state, joins/leaves, merges, diffs, liveness, and queries. |
| `lattice_presence/state_json` | JSON encoding and decoding for presence state. |

## Notes

- `presence_state` exposes `new`, `join`, `leave`, `leave_by_pid`, `merge`, `merge_with_diff`, `online_list`, `get_by_topic`, and `get_by_key`.
- `merge_with_diff` reports Phoenix-style joins and leaves while returning the merged state.
- Replica liveness is local-only: `replica_down` and `replica_up` affect local visibility and are not merged as replicated state.
- `remove_down_replica` permanently removes a down replica's entries while retaining its replicated causal high-water mark so stale gossip cannot restore them.
- Use `state_json.to_json_string` and `state_json.from_json` for persistence or transport.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_presence>
- Hex package: <https://hex.pm/packages/lattice_presence>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
