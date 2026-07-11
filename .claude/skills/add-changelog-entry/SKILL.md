---
name: add-changelog-entry
description: Create trellis changelog fragments for the lattice monorepo. Use this skill whenever the user mentions changelogs, changelog entries, changelog fragments, trellis changelog, "add a changelog", "add a change entry", or wants to document changes for a release. Also use proactively after completing user-facing code changes to any package, even if the user doesn't explicitly ask for a changelog entry.
---

# Changelog Entry Skill

This monorepo uses **trellis**'s native changelog engine. Each entry is a TOML
fragment in `.changes/unreleased/` that targets a specific package. Create
fragments with the CLI — it validates the package and kind and picks a free
filename:

```bash
trellis changelog new --package <pkg> --kind <kind> --body "<text>"
```

## When to create entries

Create one entry per user-facing change per affected package. A single PR
might need multiple entries if it touches multiple packages or introduces
both a new feature and a breaking change in the same package.

## Determining the right package and kind

### Packages

Identify which package(s) the change affects by looking at which source files
were modified: a change under `packages/<name>/` belongs to package `<name>`.
Run `trellis list --releasable` for the authoritative list of packages that
take changelog entries (`examples/` does not).

If the change only affects tests, CI, docs, or internal tooling with no
user-facing impact, a changelog entry is probably not needed. Ask the user if
unsure.

### Kinds

Kinds and their bumps are configured under `[tools.trellis.changelog]` in the
root `gleam.toml`. Pick the kind that best describes the change's impact on
users of that package:

| Kind | When to use | Semver bump |
|---|---|---|
| `MajorRelease` | Deliberate major-version release marker | major |
| `Breaking` | Removes/renames public API, changes behavior, breaks serialization compat | major |
| `Added` | New public functions, types, or capabilities | minor |
| `Changed` | Altered behavior of existing functionality | patch |
| `Deprecated` | Features marked for future removal | patch |
| `Fixed` | Bug fixes | patch |
| `Performance` | Performance improvements | patch |
| `Removed` | Removed features or capabilities | patch |
| `Reverted` | Reverted previous changes | patch |
| `Dependencies` | Dependency updates | patch |
| `Security` | Security-related changes | patch |

## Fragment format

`trellis changelog new` writes `.changes/unreleased/<package>-<n>.toml`:

```toml
project = "lattice_sets"
kind = "Added"
body = """
Add `or_set.prune(stable_vv)` for tombstone compaction

Accepts a causally stable version vector and removes tombstones dominated by it. The merge algorithm now detects "zombie" tags from stale replicas, preventing resurrection of removed elements after pruning."""
```

For multi-line bodies, prefer writing the file directly (the format above)
over wrangling shell quoting in `--body`. Always place fragments in
`.changes/unreleased/` — the per-package directories under `.changes/` hold
released version sections only.

## Writing good body text

- The first line is the summary; it becomes a `####` heading in the rendered
  CHANGELOG. Use sentence case, no trailing period. Lines after it provide
  detail.
- Describe the change from a user's perspective, not implementation details
- For `Breaking` changes, explain what users need to update (e.g., new import
  paths, renamed functions, changed signatures)
- For `Added` features, name the new public API surface
- Keep it concise — a summary line plus 1-3 sentences of detail is usually
  enough

## Validation

After creating entries, verify they parse and reference valid packages/kinds:

```bash
trellis doctor            # validates all unreleased fragments
trellis version plan      # shows the version bumps the fragments produce
```

Invalid fragments (unknown package or kind, empty body, unparseable TOML) are
hard errors — fix the file and re-run.
