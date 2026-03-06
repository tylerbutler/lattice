# Phase 7: Publishing - Research

**Researched:** 2026-03-05
**Domain:** Hex.pm package publishing, Gleam project metadata, changelog management
**Confidence:** HIGH

## Summary

Phase 7 is a metadata and documentation phase -- no code changes to the library itself. The project already has a well-configured gleam.toml with name, description, repository, and license fields. The README.md needs a complete rewrite (still contains template boilerplate). No CHANGELOG.md exists yet; changie is installed and configured but has no unreleased change fragments. The publish workflow (`publish.yml`) is already set up in CI and triggers on version tags.

The main work items are: (1) update gleam.toml description to be more informative, (2) rewrite README.md with real content, (3) create changelog entries for v1.1 changes using changie, and (4) run `gleam publish` (or let CI handle it via tag push). The LICENSE file needs `YOUR_NAME` replaced with the actual copyright holder.

**Primary recommendation:** This is a straightforward metadata/docs phase. Write README from scratch, create changie fragments for v1.0-to-v1.1 changes, batch them into a v1.1 changelog, verify `gleam publish` prerequisites, then publish.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PUB-01 | gleam.toml metadata complete (name, description, repository, licenses) | gleam.toml already has name, version, description, licences, repository. Description should be enhanced. See "Current State" section. |
| PUB-02 | README.md with installation, quickstart, and type overview | Current README is template boilerplate. Needs full rewrite. See "README Structure" section. |
| PUB-03 | CHANGELOG.md or equivalent for v1.0 to v1.1 | No CHANGELOG.md exists. Changie is configured. Change fragments needed. See "Changelog Strategy" section. |
| PUB-04 | Package published to Hex.pm via `gleam publish` | publish.yml workflow exists. HEXPM_API_KEY secret required. See "Publishing Process" section. |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| gleam | >= 1.14.0 | Build, publish | `gleam publish` is the official Hex.pm publish command |
| changie | 1.24.0 | Changelog management | Already configured in project with `.changie.yaml` |

### Supporting
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `gleam docs build` | Generate hexdocs | Verify docs render before publish |
| `gleam publish --yes` | Non-interactive publish | CI workflow uses this |

## Architecture Patterns

### Current gleam.toml State

The current `gleam.toml` already contains:
```toml
name = "lattice"
version = "0.1.0"
description = "A Gleam CRDT library"
licences = ["MIT"]
repository = { type = "github", user = "tylerbutler", repo = "lattice" }
gleam = ">= 1.7.0"
```

**What needs updating:**
- `version`: Should be `1.1.0` (but changie/release workflow may handle this)
- `description`: Could be more descriptive, e.g., "Conflict-free replicated data types (CRDTs) for Gleam, with property-based tested merge semantics"
- All other metadata fields are already present and correct

**Optional additions (nice-to-have):**
- `links` field for pointing to documentation or examples

### README Structure

The README needs a complete rewrite. Current content is template boilerplate (`my_gleam_project` references throughout). Recommended structure:

```
# lattice

[badges: hex version, hexdocs, CI status]

Brief description (1-2 sentences)

## Installation

gleam add lattice

## Quickstart

[Simple GCounter or PNCounter example showing new/increment/merge]

## CRDT Types

### Counters
- GCounter - grow-only counter
- PNCounter - positive-negative counter

### Registers
- LWWRegister - last-writer-wins register
- MVRegister - multi-value register

### Sets
- GSet - grow-only set
- TwoPhaseSet - add and remove (once) set
- ORSet - observed-remove set

### Maps
- LWWMap - last-writer-wins map
- ORMap - observed-remove map

### Supporting Types
- VersionVector - logical clocks
- DotContext - causal context tracking

## Features
- Property-based tested merge semantics
- Erlang and JavaScript targets
- JSON serialization for all types

## Documentation
Link to hexdocs

## License
MIT
```

### Changelog Strategy

**Current state:**
- Changie is installed (v1.24.0) and configured (`.changie.yaml`)
- No unreleased change fragments exist (`.changes/unreleased/` has only `.gitkeep`)
- No CHANGELOG.md file exists yet
- v1.0 tag exists; v1.1 changes are all commits since that tag

**Approach:** Create changie change fragments for the v1.1 work, then batch them into a version. The key v1.1 changes (from commit history) are:

1. **Added**: JavaScript target support (Erlang + JS dual-target)
2. **Added**: CI workflow for JavaScript target testing
3. **Changed**: Comprehensive doc comments on all public functions and types
4. **Changed**: API polish -- opaque types for MVRegister, Tag, VersionVector, DotContext
5. **Changed**: Added `to_dict`/`from_dict` helpers for VersionVector serialization

**Changie commands:**
```bash
# Create change fragments
changie new --kind Added --body "JavaScript target support..."
changie new --kind Changed --body "Comprehensive doc comments..."

# Batch into version
changie batch v1.1.0

# Merge into CHANGELOG.md
changie merge
```

### Publishing Process

**Prerequisites for `gleam publish`:**
1. gleam.toml must have: `name`, `version` (required), plus `description`, `licences`, `repository` (recommended -- all present)
2. Package must build successfully: `gleam build`
3. HEXPM_API_KEY environment variable must be set

**Two publish paths:**
1. **Manual**: `HEXPM_API_KEY=xxx gleam publish --yes` from local machine
2. **CI (preferred)**: Push a `v*` tag, which triggers `publish.yml` workflow

**The CI path via changie-release workflow:**
1. Changie fragments are batched and merged
2. Push to main triggers `release.yml`
3. `changie-release` action creates a PR with version bump
4. Merging the PR creates a GitHub release with `v*` tag
5. Tag push triggers `publish.yml` which runs tests then publishes

### LICENSE File Fix

The LICENSE file contains `YOUR_NAME` placeholder:
```
Copyright (c) 2024 YOUR_NAME
```
This needs to be updated to the actual copyright holder before publishing.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Changelog generation | Manual CHANGELOG.md editing | changie | Already configured, integrates with release workflow |
| Version bumping | Manual version edits | changie batch + release workflow | Automated, consistent |
| Hex.pm publishing | Manual API calls | `gleam publish` or CI workflow | Standard tooling |

## Common Pitfalls

### Pitfall 1: Template Boilerplate Left in README
**What goes wrong:** Publishing with `my_gleam_project` references in README
**Why it happens:** README was never customized from template
**How to avoid:** Full rewrite, grep for `my_gleam_project` after

### Pitfall 2: Version Mismatch
**What goes wrong:** gleam.toml says `0.1.0` but changelog says `1.1.0`
**Why it happens:** Version not bumped before publish
**How to avoid:** Ensure gleam.toml version matches intended release. The changie-release workflow handles this via `version-files: gleam.toml:version`, but manual publish requires manual version update.

### Pitfall 3: Missing HEXPM_API_KEY
**What goes wrong:** `gleam publish` fails with auth error
**Why it happens:** Secret not configured in GitHub repo settings
**How to avoid:** Verify secret exists before attempting CI publish. For manual publish, set env var.

### Pitfall 4: LICENSE Placeholder
**What goes wrong:** Published package has "YOUR_NAME" in LICENSE
**Why it happens:** Template placeholder never updated
**How to avoid:** Update LICENSE before publishing

### Pitfall 5: Publishing Without Testing
**What goes wrong:** Broken package on Hex.pm
**Why it happens:** Skipping verification
**How to avoid:** Run `just ci` before publish. The CI workflow already gates on tests.

## Code Examples

### Changie Fragment Creation
```bash
# Create a change fragment (interactive prompts for kind and body)
changie new --kind Added --body "JavaScript target support for all CRDT types"

# Or create with multi-line body
changie new --kind Changed --body "Comprehensive documentation for all 12 public modules with doc comments on every public function and type"

# Batch unreleased fragments into a version
changie batch v1.1.0

# Merge version into CHANGELOG.md
changie merge
```

### gleam.toml Metadata (Target State)
```toml
name = "lattice"
version = "1.1.0"
description = "Conflict-free replicated data types (CRDTs) for Gleam, with property-based tested merge semantics"
licences = ["MIT"]
repository = { type = "github", user = "tylerbutler", repo = "lattice" }
gleam = ">= 1.7.0"
```

### Quickstart Example for README
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

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Manual CHANGELOG | changie-managed changelog | Project setup | Use changie commands, not manual edits |
| release-please | changie-release | Project setup | Different workflow: changie fragments + batch |

## Open Questions

1. **HEXPM_API_KEY availability**
   - What we know: CI workflow expects `secrets.HEXPM_API_KEY`
   - What's unclear: Whether the secret is configured in the GitHub repo
   - Recommendation: Verify before attempting CI publish; manual publish is fallback

2. **Version strategy: 1.1.0 vs 0.1.0 → 1.1.0**
   - What we know: gleam.toml currently says `0.1.0`, tag `v1.0` exists
   - What's unclear: Whether the release workflow will handle the jump from 0.1.0 to 1.1.0 correctly
   - Recommendation: Manually set version to `1.1.0` in gleam.toml before creating changie batch, or let changie batch handle it

3. **First-time publish vs replace**
   - What we know: `gleam publish` has a `--replace` flag for re-publishing same version
   - What's unclear: Whether `lattice` name is already claimed on Hex.pm
   - Recommendation: Check `hex.pm/packages/lattice` before publishing; if taken, consider alternative name

## Sources

### Primary (HIGH confidence)
- [gleam.run/writing-gleam/gleam-toml](https://gleam.run/writing-gleam/gleam-toml/) - gleam.toml field reference
- Project files: gleam.toml, .changie.yaml, publish.yml, release.yml - direct inspection

### Secondary (MEDIUM confidence)
- [hex.pm/docs/gleam-usage](https://hex.pm/docs/gleam-usage) - Hex.pm Gleam publishing docs
- `gleam publish --help` output - CLI reference

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - gleam publish and changie are already configured in the project
- Architecture: HIGH - all infrastructure (CI workflows, changie config) already exists
- Pitfalls: HIGH - identified from direct inspection of current project state

**Research date:** 2026-03-05
**Valid until:** 2026-04-05 (stable domain, unlikely to change)
