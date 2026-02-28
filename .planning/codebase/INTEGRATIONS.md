# External Integrations

**Analysis Date:** 2026-02-28

## APIs & External Services

**Package Registry:**
- Hex.pm - Gleam package registry for publishing and dependency resolution
  - CLI integration: `gleam publish` command
  - Auth: `HEXPM_API_KEY` environment variable

**Source Control Hosting:**
- GitHub - Repository hosting and CI/CD (configured in `gleam.toml`)
  - Repository metadata: `repository = { type = "github", user = "YOUR_USERNAME", repo = "my_gleam_project" }`

## Data Storage

**Databases:**
- Not applicable - Library/package does not use databases

**File Storage:**
- Local filesystem only - No external file storage integration

**Caching:**
- Not detected

## Authentication & Identity

**Auth Provider:**
- None (library package - no user authentication)

**Secrets:**
- `HEXPM_API_KEY` - Required for publishing to Hex.pm registry
- `RELEASE_PAT` (RELEASE_TOKEN) - GitHub Personal Access Token for release automation
  - Permissions: `contents:write`, `pull-requests:write`

## Monitoring & Observability

**Error Tracking:**
- Not detected

**Logs:**
- Standard output (test and build logs via GitHub Actions)
- No external logging service

**Metrics:**
- Not detected

## CI/CD & Deployment

**Hosting:**
- GitHub (source code and releases)

**CI Pipeline:**
- GitHub Actions (workflows in `.github/workflows/`)
  - **ci.yml**: Runs on push/PR to main
    - Formatting check (`gleam format --check`)
    - Type checking (`gleam check`)
    - Build with strict warnings (`gleam build --warnings-as-errors`)
    - Test execution (`gleam test`)
    - Documentation build (`gleam docs build`)
  - **publish.yml**: Publishes to Hex.pm on version tag (v*)
    - Runs CI checks first
    - Executes `gleam publish --yes`
  - **release.yml**: Automated release management via changie
    - Uses tylerbutler/actions/changie-release action
    - Creates/updates release PR on main branch
    - Updates `gleam.toml` version field

**Build Infrastructure:**
- Runner: ubuntu-latest (GitHub Actions default runner)
- Custom setup action: `.github/actions/setup` (tool installation)

## Environment Configuration

**Required env vars:**
- `HEXPM_API_KEY` - Hex.pm API key for publishing (secret)
- `RELEASE_PAT` (optional, called RELEASE_TOKEN in docs) - GitHub PAT for release automation (secret)

**Secrets location:**
- GitHub repository secrets (configured in Settings > Secrets and variables > Actions)

## Webhooks & Callbacks

**Incoming:**
- None detected - Library package does not expose webhooks

**Outgoing:**
- None detected

## Version Control Integration

**Commit Convention:**
- Conventional Commits enforced via commitlint
  - Config: `.commitlintrc.json`
  - Types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
  - Header max length: 72 characters
  - Body max line length: 100 characters
  - Scope case: lower-case
  - Subject case: lower-case

**Release Automation:**
- release-please (not directly visible but referenced in workflows)
  - Generates version bumps based on commit messages
  - Creates release PRs with updated CHANGELOG.md

**Changelog Management:**
- changie - Changelog generator
  - Fragment location: `.changes/` directory
  - Supports two config modes: kinds-based or simple
  - Config files: `.changie.yaml` (default with kinds), `.changie.no-kinds.yaml`
  - Command: `just change` creates new fragment
  - Command: `just changelog` merges fragments to CHANGELOG.md

---

*Integration audit: 2026-02-28*
