<h1 align="center">LATTICE</h1>

<p align="center">
  <img src="website/src/assets/lattice-min.webp" alt="lattice logo" />
</p>

<p align="center">
  <a href="https://hex.pm/packages/lattice"><img src="https://img.shields.io/hexpm/v/lattice" alt="Package Version" /></a>
  <a href="https://hexdocs.pm/lattice/"><img src="https://img.shields.io/badge/hex-docs-ffaff3" alt="Hex Docs" /></a>
</p>

Conflict-free replicated data types (CRDTs) for Gleam. Battle-tested with property-based tests, targeting both Erlang and JavaScript runtimes.

## Installation

```sh
gleam add lattice
```

## Quickstart

```gleam
import lattice/g_counter

pub fn main() {
  // Create counters for two replicas
  let counter_a = g_counter.new() |> g_counter.increment("node-a", 1)
  let counter_b = g_counter.new() |> g_counter.increment("node-b", 3)

  // Merge replicas -- CRDTs converge automatically
  let merged = g_counter.merge(counter_a, counter_b)
  g_counter.value(merged)
  // -> 4
}
```

## Available Types

### Counters

| Module | Description |
|--------|-------------|
| `lattice/g_counter` | GCounter -- grow-only counter |
| `lattice/pn_counter` | PNCounter -- positive-negative counter |

### Registers

| Module | Description |
|--------|-------------|
| `lattice/lww_register` | LWWRegister -- last-writer-wins register |
| `lattice/mv_register` | MVRegister -- multi-value register |

### Sets

| Module | Description |
|--------|-------------|
| `lattice/g_set` | GSet -- grow-only set |
| `lattice/two_p_set` | TwoPSet -- two-phase set with add/remove-once |
| `lattice/or_set` | ORSet -- observed-remove set |

### Maps

| Module | Description |
|--------|-------------|
| `lattice/lww_map` | LWWMap -- last-writer-wins map |
| `lattice/or_map` | ORMap -- observed-remove map |

### Supporting

| Module | Description |
|--------|-------------|
| `lattice/version_vector` | VersionVector -- logical clocks for causality tracking |
| `lattice/dot_context` | DotContext -- causal context for OR-types |

## Features

- Property-based tested merge semantics (commutativity, associativity, idempotency)
- Erlang and JavaScript target support
- JSON serialization for all types
- Comprehensive documentation with examples

## Documentation

Full API documentation is available at <https://hexdocs.pm/lattice>.

## License

MIT - see [LICENSE](LICENSE) for details.
