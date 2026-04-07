---
name: add-changelog-entry
description: Create changie changelog fragments for the lattice monorepo. Use this skill whenever the user mentions changelogs, changelog entries, changelog fragments, changie, "add a changelog", "add a change entry", or wants to document changes for a release. Also use proactively after completing user-facing code changes to any package, even if the user doesn't explicitly ask for a changelog entry.
---

# Changelog Entry Skill

This monorepo uses **changie** with project-based changelog management. Each entry is a YAML file in `.changes/unreleased/` that targets a specific package.

## When to create entries

Create one entry per user-facing change per affected package. A single PR might need multiple entries if it touches multiple packages or introduces both a new feature and a breaking change in the same package.

## Determining the right package and kind

### Packages

Identify which package(s) the change affects by looking at which source files were modified. Map file paths to projects:

| Path prefix | Project key |
|---|---|
| `packages/lattice_core/` | `lattice_core` |
| `packages/lattice_counters/` | `lattice_counters` |
| `packages/lattice_registers/` | `lattice_registers` |
| `packages/lattice_sets/` | `lattice_sets` |
| `packages/lattice_maps/` | `lattice_maps` |
| `packages/lattice_crdt/` | `lattice_crdt` |

If the change only affects tests, CI, docs, or internal tooling with no user-facing impact, a changelog entry is probably not needed. Ask the user if unsure.

### Kinds

Pick the kind that best describes the change's impact on users of that package:

| Kind | When to use | Semver bump |
|---|---|---|
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

## Creating the entry

### File naming

Pattern: `<project_key>-<Kind>-<slug>.yaml`

- `<project_key>`: exact key from the table above (e.g., `lattice_sets`)
- `<Kind>`: exact kind label, capitalized as shown (e.g., `Added`, `Breaking`)
- `<slug>`: short kebab-case descriptor (e.g., `orset-prune`, `json-v2`)

Place the file at: `.changes/unreleased/<project_key>-<Kind>-<slug>.yaml`

### File format

```yaml
project: <project_key>
kind: <Kind>
body: |-
  <Summary line>
  <Optional detailed description>
time: <ISO 8601 timestamp>
```

**Fields:**
- `project` — must exactly match a project key from `.changie.yaml`
- `kind` — must exactly match one of the configured kinds (case-sensitive)
- `body` — use `|-` block scalar. First line is a short summary (sentence case, no trailing period). Additional lines provide context on what changed and why.
- `time` — ISO 8601 with nanosecond precision in UTC. Generate with: `date -u +"%Y-%m-%dT%H:%M:%S.%N+00:00"` on Linux, or use a reasonable UTC timestamp like `2026-04-07T20:00:00.000000000Z` on macOS where `%N` isn't available.

### Example

File: `.changes/unreleased/lattice_sets-Added-orset-prune.yaml`

```yaml
project: lattice_sets
kind: Added
body: |-
  Add `or_set.prune(stable_vv)` for tombstone compaction

  Accepts a causally stable version vector and removes tombstones dominated by it. The merge algorithm now detects "zombie" tags from stale replicas, preventing resurrection of removed elements after pruning.
time: 2026-04-07T20:00:00.000000000Z
```

### Writing good body text

- The summary line should describe the change from a user's perspective, not implementation details
- For `Breaking` changes, explain what users need to update (e.g., new import paths, renamed functions, changed signatures)
- For `Added` features, name the new public API surface
- Keep it concise — a summary line plus 1-3 sentences of detail is usually enough

## Validation

After creating entries, verify they parse correctly by running a dry-run batch for the affected project:

```bash
changie batch auto --dry-run --project <project_key>
```

Check that each new entry appears under the correct `#### {Kind}` heading with the summary as a `#####` heading and description text below it. If there are YAML parse errors, fix the file and re-run.
