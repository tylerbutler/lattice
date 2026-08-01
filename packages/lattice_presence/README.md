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
  let assert Ok(replica) =
    presence_state.new_replica("node-a", "process-incarnation-123")
  let assert Ok(state) =
    presence_state.join(
      presence_state.new(replica),
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
| `lattice_presence/presence_state` | Presence CRDT state, serialization, joins/leaves, checked merges, diffs, liveness, and queries. |

## Notes

- `join`, `merge`, `merge_with_diff`, `replica_up`, and `supersede` return
  `Result`; retired incarnations cannot create joins or be marked up.
- `merge` and `merge_with_diff` return `Result`; divergent states claiming the
  same full incarnation identity are rejected.
- Callers must provide a fresh, unique incarnation token for every restart of a
  stable replica base. Use `supersede` when replacing known older incarnations.
- Replica liveness is local-only. `remove_down_replica` requires `Down` and adds
  the identity to a replicated grow-only retired set that blocks stale replay,
  including unseen higher clocks.
- Use `presence_state.to_json_string` and `presence_state.from_json` for
  persistence or transport. The structured replica JSON format is not
  compatible with the version 1 wire format.

## Links

- Project site: <https://lattice.tylerbutler.com>
- API docs: <https://hexdocs.pm/lattice_presence>
- Hex package: <https://hex.pm/packages/lattice_presence>
- Repository: <https://github.com/tylerbutler/lattice>

## License

MIT
