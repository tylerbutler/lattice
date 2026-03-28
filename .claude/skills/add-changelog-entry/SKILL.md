---
name: add-changelog-entry
description: Use when explicitly asked to add a changelog entry. Creates a changie YAML fragment in .changes/unreleased/ with the correct format, kind, and timestamp.
---

<required>
*CRITICAL* Add the following steps to your Todo list using TodoWrite:

1. Determine the changelog kind and body content
2. Generate the YAML fragment file
3. Validate the fragment with `changie batch auto --dry-run`
</required>

# Overview

This project uses **changie** for changelog management. Changelog entries are YAML fragment files stored in `.changes/unreleased/`. This skill creates those fragments directly without running the interactive `changie new` command.

# Step-by-step process

## 1. Determine the changelog kind and body content

Select exactly one kind from the following list. If the user doesn't specify a kind, infer the most appropriate one from the context of the change.

| Kind           | When to use                                      | Version bump |
|----------------|--------------------------------------------------|--------------|
| `Added`        | New features or capabilities                     | minor        |
| `Changed`      | Changes to existing functionality                | patch        |
| `Deprecated`   | Features marked for future removal               | patch        |
| `Fixed`        | Bug fixes                                        | patch        |
| `Performance`  | Performance improvements                         | patch        |
| `Removed`      | Removed features or capabilities                 | patch        |
| `Reverted`     | Reverted previous changes                        | patch        |
| `Dependencies` | Dependency updates                               | patch        |
| `Security`     | Security-related changes                         | patch        |

Write the body content as a multi-line YAML block:
- **First line**: A short summary title (sentence case, no trailing period)
- **Subsequent lines** (optional): Detailed description of what changed and why. Use complete sentences.

Example body:
```
Optimized merge and compare operations
Replaced list.unique-based key iteration with dict.combine, dict.fold, and dict.filter in GCounter, VersionVector, ORSet, LWWMap, and ORMap merge/compare operations.
```

If the user has not provided enough information to write a meaningful entry, ask them what the change is about before proceeding.

## 2. Generate the YAML fragment file

Create the fragment file directly using the `create` tool (or `bash` with `cat`). Follow this exact structure:

### File naming

Use the pattern: `{Kind}-{slug}.yaml`

- `{Kind}` is the exact kind label with original casing (e.g., `Added`, `Fixed`, `Performance`)
- `{slug}` is a short kebab-case descriptor of the change (e.g., `or-set-tombstone-gc`, `json-size-limits`)

Place the file at: `.changes/unreleased/{Kind}-{slug}.yaml`

### File content

The file must be valid YAML with exactly three fields:

```yaml
kind: {Kind}
body: |-
    {First line: summary title}
    {Optional subsequent lines: detailed description}
time: {ISO 8601 timestamp with nanosecond precision}
```

Generate the timestamp using bash:

```bash
date -u +"%Y-%m-%dT%H:%M:%S.%N+00:00"
```

### Complete example

File: `.changes/unreleased/Fixed-lww-tiebreak.yaml`

```yaml
kind: Fixed
body: |-
    Deterministic LWW register tie-breaking
    Improved LWW tie-breaking to use lexicographic comparison of values when
    timestamps are equal, ensuring merge is commutative regardless of argument
    order.
time: 2026-03-20T20:41:25.580469006+00:00
```

### Important rules

- The `body` field MUST use `|-` (literal block, strip trailing newlines)
- Body lines after the first MUST be indented by 4 spaces (YAML block indent)
- The `kind` value MUST exactly match one of the 9 configured kinds (case-sensitive)
- Do NOT add extra fields — changie only expects `kind`, `body`, and `time`
- Do NOT include a trailing newline after the last line of body content within the YAML block

## 3. Validate the fragment

After creating the file, run the following command to verify the fragment is valid and will render correctly:

```bash
changie batch auto --dry-run
```

This renders all unreleased fragments into a preview. Verify that:
- The new entry appears under the correct `#### {Kind}` heading
- The summary title renders as a `#####` heading
- The description text (if any) appears below the title
- No YAML parsing errors are reported

If validation fails, read the error output, fix the YAML file, and re-run the validation.
