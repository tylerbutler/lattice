# my_gleam_project

[![Package Version](https://img.shields.io/hexpm/v/my_gleam_project)](https://hex.pm/packages/my_gleam_project)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/my_gleam_project/)

A Gleam project.

## Installation

```sh
gleam add my_gleam_project
```

## Usage

```gleam
import my_gleam_project

pub fn main() {
  my_gleam_project.hello("World")
  // -> "Hello, World!"
}
```

## Development

### Setup Options

#### Changelog Kinds

By default, changie is configured with **kinds** (Added, Changed, Fixed, etc.) which categorize changelog entries. If you prefer a simpler changelog without kind categorization:

1. Replace `.changie.yaml` with `.changie.no-kinds.yaml`:
   ```sh
   mv .changie.no-kinds.yaml .changie.yaml
   ```

To keep kinds (the default), just delete the alternative config:
```sh
rm .changie.no-kinds.yaml
```

#### CI Options

This template includes two CI options:

1. **Local setup action** (default): Self-contained, no external dependencies
   - Uses `.github/actions/setup/action.yml`

2. **Shared actions**: Uses [tylerbutler/actions](https://github.com/tylerbutler/actions)
   - Rename `ci-shared-actions.yml.template` to `ci.yml`
   - Delete `.github/actions/` directory

### Prerequisites

- [Erlang](https://www.erlang.org/) 27+
- [Gleam](https://gleam.run/) 1.7+
- [just](https://github.com/casey/just) (task runner)

Install tools via [mise](https://mise.jdx.dev/) or [asdf](https://asdf-vm.com/):

```sh
mise install
# or
asdf install
```

### Commands

```sh
just deps      # Download dependencies
just build     # Build the project
just test      # Run tests
just format    # Format code
just check     # Type check
just docs      # Build documentation
just ci        # Run all CI checks
```

### CI/CD

This project uses GitHub Actions for CI and automated releases:

- **CI**: Runs on every push/PR to main
- **Release**: Uses [release-please](https://github.com/googleapis/release-please) for automated versioning
- **Publish**: Automatically publishes to [Hex.pm](https://hex.pm) on release

### GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `RELEASE_TOKEN` | GitHub PAT with `contents:write` and `pull-requests:write` permissions |
| `HEXPM_API_KEY` | API key from [hex.pm](https://hex.pm) for publishing |

### Commit Convention

This project uses [Conventional Commits](https://www.conventionalcommits.org/):

- `feat:` - New features (minor version bump)
- `fix:` - Bug fixes (patch version bump)
- `docs:` - Documentation changes
- `chore:` - Maintenance tasks
- `BREAKING CHANGE:` in commit body - Major version bump

## License

MIT - see [LICENSE](LICENSE) for details.
