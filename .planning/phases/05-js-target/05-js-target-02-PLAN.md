---
phase: 05-js-target
plan: 02
type: execute
wave: 2
depends_on: ["01"]
files_modified:
  - .github/workflows/ci.yml
  - .github/actions/setup/action.yml
autonomous: true
requirements:
  - TARGET-03

must_haves:
  truths:
    - "CI workflow runs the full test suite on both Erlang and JavaScript targets"
    - "JavaScript target CI job sets up Node.js via the setup action's node input"
    - "Both Erlang and JavaScript CI jobs must pass for the workflow to succeed"
    - "CI triggers on push to main, pull requests to main, and workflow_call"
  artifacts:
    - path: ".github/workflows/ci.yml"
      provides: "Dual-target CI with separate Erlang and JavaScript test jobs"
    - path: ".github/actions/setup/action.yml"
      provides: "Setup action with Node.js support already wired (node input)"
  key_links:
    - from: ".github/workflows/ci.yml"
      to: ".github/actions/setup/action.yml"
      via: "uses: ./.github/actions/setup"
      pattern: "node: 'true'"
---

<objective>
Update the CI workflow to run the full test suite on both Erlang and JavaScript targets on every push.

Purpose: Complete TARGET-03 by adding a JavaScript target test job to the CI workflow. The existing setup action already supports Node.js via its `node` input parameter -- we just need to use it.

Output: CI workflow with dual-target test coverage enforced on every push and PR.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.github/workflows/ci.yml
@.github/actions/setup/action.yml
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Add JavaScript target test job to CI workflow</name>
  <files>.github/workflows/ci.yml</files>
  <behavior>
    - CI has a "test-erlang" job that runs `just test` (Erlang target, existing behavior)
    - CI has a "test-js" job that runs `just test-js` (JavaScript target, new)
    - The test-js job uses the setup action with `node: 'true'` to install Node.js
    - Both jobs run on push to main, pull requests to main, and workflow_call
    - The docs job is unchanged
    - Both test jobs must pass for the workflow to be green
  </behavior>
  <action>
Update `.github/workflows/ci.yml` to have two test jobs instead of one. Use a matrix strategy to keep it DRY, or use two explicit jobs. Two explicit jobs is clearer for this case since they have different setup requirements.

**Replace the current single `test` job with two jobs:**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_call:

jobs:
  test-erlang:
    runs-on: ubuntu-latest
    name: Test (Erlang)
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # ratchet:actions/checkout@v6

      - name: Setup environment
        uses: ./.github/actions/setup

      - name: Check formatting
        run: just format-check

      - name: Type check
        run: just check

      - name: Build (warnings as errors)
        run: just build-strict

      - name: Run tests
        run: just test

  test-js:
    runs-on: ubuntu-latest
    name: Test (JavaScript)
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # ratchet:actions/checkout@v6

      - name: Setup environment
        uses: ./.github/actions/setup
        with:
          node: 'true'

      - name: Build (warnings as errors)
        run: just build-strict-js

      - name: Run tests
        run: just test-js

  docs:
    runs-on: ubuntu-latest
    name: Docs
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # ratchet:actions/checkout@v6

      - name: Setup environment
        uses: ./.github/actions/setup

      - name: Build documentation
        run: just docs
```

**Key design decisions:**
- Format check and type check only run in the Erlang job (they're target-independent)
- The JS job only builds and tests on the JS target (no redundant format/check)
- Both jobs run independently in parallel for faster CI
- The JS job uses `node: 'true'` in the setup action to install Node.js
- Uses the `just` commands from Plan 01 (`build-strict-js`, `test-js`)
  </action>
  <verify>
    <automated>grep -c "test-js\|test-erlang\|Test (JavaScript)\|Test (Erlang)" .github/workflows/ci.yml</automated>
    <automated>grep "node:" .github/workflows/ci.yml</automated>
  </verify>
  <done>
    - .github/workflows/ci.yml has test-erlang job (format, check, build, test on Erlang)
    - .github/workflows/ci.yml has test-js job (build-strict-js, test-js on JavaScript)
    - test-js job uses setup action with node: 'true'
    - docs job is unchanged
    - Both test jobs are required (no allow-failure)
  </done>
</task>

</tasks>

<verification>
1. `grep -E "test-erlang|test-js" .github/workflows/ci.yml` -- both jobs present
2. `grep "node:" .github/workflows/ci.yml` -- node input used for JS job
3. Validate YAML syntax: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml'))"` or similar
4. `just ci` -- local CI check still passes (confirms justfile recipes from Plan 01 work)
</verification>

<success_criteria>
- TARGET-03: CI workflow runs tests on both Erlang and JavaScript targets
- Both jobs run in parallel on every push to main and every PR
- JS job has Node.js installed via setup action
- No existing CI behavior is broken
</success_criteria>

<output>
After completion, create `.planning/phases/05-js-target/05-js-target-02-SUMMARY.md`
</output>
