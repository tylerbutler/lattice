---
on:
  workflow_dispatch:
  schedule: weekly on monday around 09:00

permissions:
  contents: read
  pull-requests: read

safe-outputs:
  create-pull-request:
    title-prefix: "docs: "
    labels: [documentation, automated]
    draft: true
    base-branch: main
    allowed-base-branches: [main]
    max: 1
    protected-files: fallback-to-issue
    expires: 14

max-ai-credits: 200
---

# Audit documentation drift

Review implementation changes merged during the last seven days.

Compare public APIs and behavior under `packages/*/src/` with:

- `README.md`
- `packages/*/README.md`
- `website/src/content/docs/`

Ignore changelogs, planning documents, and generated Gleam API documentation.

Confirm every claimed function, module, package dependency, installation
instruction, and code example against the current implementation. Make only
necessary documentation changes. Never modify source code, manifests,
workflows, lockfiles, or generated files.

If drift exists, open one draft pull request containing the minimal corrections.
If nothing is stale, take no action.