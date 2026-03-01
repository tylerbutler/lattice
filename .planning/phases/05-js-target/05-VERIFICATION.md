---
phase: 05-js-target
verified: 2026-03-01T16:00:00Z
status: gaps_found
score: 4/5 must-haves verified
re_verification: false
gaps:
  - truth: "CI workflow runs the full test suite against both Erlang and JavaScript targets on every push"
    status: partial
    reason: "CI structure is correct (both test-erlang and test-js jobs exist and are properly wired), but the test-erlang job includes a 'Check formatting' step (just format-check) that will fail on every push due to 20 pre-existing Gleam source files with formatting violations. The format failures were introduced in Phase 3 (commit 67fed04) and predate Phase 5, but Phase 5 did not fix them. When format-check fails, the subsequent test steps in the Erlang job never execute — meaning the test suite is blocked from running in CI for the Erlang target."
    artifacts:
      - path: ".github/workflows/ci.yml"
        issue: "test-erlang job runs 'just format-check' before 'just test', and format-check fails due to 20 unformatted .gleam files"
      - path: "src/lattice/g_counter.gleam"
        issue: "Unformatted (and 19 other src/test files)"
    missing:
      - "Run 'gleam format src test' to fix the 20 formatting violations across src/ and test/"
      - "Commit the formatting fix so CI's test-erlang job can reach the test step"
human_verification:
  - test: "Push a commit to a PR branch targeting main and observe both CI jobs"
    expected: "test-erlang completes all steps (format-check, check, build-strict, test) and test-js completes all steps (build-strict-js, test-js), both showing green"
    why_human: "Cannot run GitHub Actions locally; actual CI execution requires a real push to remote"
---

# Phase 5: JS Target Verification Report

**Phase Goal:** All existing tests pass on the JavaScript target and CI enforces dual-target coverage going forward
**Verified:** 2026-03-01T16:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| #   | Truth                                                                                      | Status      | Evidence                                                                                                                |
| --- | ------------------------------------------------------------------------------------------ | ----------- | ----------------------------------------------------------------------------------------------------------------------- |
| 1   | `gleam test --target javascript` completes with all 228+ tests passing                    | ✓ VERIFIED  | SUMMARY confirms 228 tests passed; 228 test functions counted in test/ directory; commit e84e1a5 verifies the run      |
| 2   | Any JS-specific failures discovered are identified and fixed before proceeding             | ✓ VERIFIED  | SUMMARY documents no failures found; no .gleam files were modified by Phase 5; commit message confirms zero failures   |
| 3   | justfile has working test-js and test-all commands (uncommented and functional)            | ✓ VERIFIED  | All 7 multi-target recipes present and substantive: build-js, build-all, build-strict-js, build-strict-all, test-erlang, test-js, test-all |
| 4   | just test-all runs tests on both Erlang and JavaScript targets sequentially               | ✓ VERIFIED  | `test-all: test-erlang test-js` in justfile; `ci: format-check check test-all build-strict-all` confirms integration  |
| 5   | CI workflow runs the full test suite against both Erlang and JavaScript targets on every push | ✗ FAILED | CI structure is correct (test-erlang + test-js jobs wired, node: 'true' for JS), but test-erlang fails at format-check step before reaching test execution — 20 .gleam files have pre-existing formatting violations (introduced in Phase 3, not fixed in Phase 5) |

**Score:** 4/5 truths verified

### Required Artifacts

| Artifact                              | Expected                                                 | Status      | Details                                                                                                     |
| ------------------------------------- | -------------------------------------------------------- | ----------- | ----------------------------------------------------------------------------------------------------------- |
| `justfile`                            | Multi-target build and test commands for both targets    | ✓ VERIFIED  | All 7 recipes active: build-js, build-all, build-strict-js, build-strict-all, test-erlang, test-js, test-all; ci recipe uses test-all + build-strict-all |
| `.github/workflows/ci.yml`           | Dual-target CI with separate Erlang and JavaScript jobs  | ✓ VERIFIED  | Three jobs: test-erlang, test-js, docs; triggers on push/PR to main and workflow_call; no allow-failure     |
| `.github/actions/setup/action.yml`   | Setup action with Node.js support via node input         | ✓ VERIFIED  | `node` input defined (required: false, default: "false"); conditional `if: inputs.node == 'true'` installs Node 22 |

### Key Link Verification

| From                          | To                              | Via                             | Status      | Details                                                                                      |
| ----------------------------- | ------------------------------- | ------------------------------- | ----------- | -------------------------------------------------------------------------------------------- |
| `.github/workflows/ci.yml`   | `.github/actions/setup/action.yml` | `uses: ./.github/actions/setup` | ✓ WIRED  | test-js job uses `uses: ./.github/actions/setup` with `node: 'true'`; setup action handles Node 22 conditionally |
| `justfile` ci recipe          | `test-all`                      | `ci: format-check check test-all build-strict-all` | ✓ WIRED | ci recipe explicitly depends on test-all which chains test-erlang + test-js |
| `.github/workflows/ci.yml` test-erlang | `justfile` test recipe  | `run: just test`                | ⚠️ BLOCKED | Step exists and is wired, but format-check step preceding it will fail on current codebase, preventing tests from running |

### Requirements Coverage

| Requirement | Source Plan | Description                                                        | Status      | Evidence                                                                                                          |
| ----------- | ----------- | ------------------------------------------------------------------ | ----------- | ----------------------------------------------------------------------------------------------------------------- |
| TARGET-01   | Plan 01     | All existing tests pass with `gleam test --target javascript`      | ✓ SATISFIED | 228 test functions in test/; SUMMARY documents zero JS failures; commit e84e1a5 confirms the run                 |
| TARGET-02   | Plan 01     | Fix any JS-specific failures (if discovered)                       | ✓ SATISFIED | No JS-specific failures found; no .gleam files modified; SUMMARY and commit message both confirm clean run        |
| TARGET-03   | Plan 02     | CI workflow runs tests on both Erlang and JavaScript targets       | ✗ BLOCKED   | CI structure correct (test-erlang + test-js jobs, both required, node: 'true' wired), but format-check failure in test-erlang prevents the Erlang test suite from executing in CI |

No orphaned requirements: all three TARGET-01, TARGET-02, TARGET-03 are claimed by plans and accounted for above.

### Anti-Patterns Found

| File                              | Line | Pattern              | Severity   | Impact                                                                              |
| --------------------------------- | ---- | -------------------- | ---------- | ----------------------------------------------------------------------------------- |
| `src/lattice/g_counter.gleam`     | —    | Pre-existing format  | ⚠️ Warning | Causes `just format-check` to fail, blocking test-erlang CI job from reaching tests |
| `src/lattice/crdt.gleam`          | —    | Pre-existing format  | ⚠️ Warning | Same impact — 20 files total across src/ and test/                                  |
| _(18 additional .gleam files)_    | —    | Pre-existing format  | ⚠️ Warning | See full list from `gleam format --check src test`                                  |

Note: These format violations were introduced in Phase 3 (commit 67fed04, feat(03-02): JSON serialization) and are pre-existing relative to Phase 5. Phase 5 made no changes to any .gleam source files. However, Phase 5 did not fix them either, and they directly block the Erlang CI job from running its test suite — which is the core deliverable of this phase.

### Human Verification Required

#### 1. Full CI Green on Push

**Test:** Push a branch to origin with a PR targeting main, or push directly to main.
**Expected:** Both `Test (Erlang)` and `Test (JavaScript)` jobs pass in GitHub Actions — once the formatting issue is resolved.
**Why human:** Cannot execute GitHub Actions locally; real CI run requires remote push.

### Gaps Summary

Phase 5 achieved significant progress: all 228 CRDT tests pass on the JavaScript target (TARGET-01), no JS-specific failures were found (TARGET-02), and the CI workflow structure for TARGET-03 is correctly implemented with two parallel jobs (`test-erlang` and `test-js`) both required for a green build.

The single blocking gap is a pre-existing Gleam source formatting issue — 20 files in `src/` and `test/` do not pass `gleam format --check`. These violations were introduced during Phase 3 (JSON serialization work) and were never fixed. The Phase 5 CI SUMMARY noted this issue explicitly as "pre-existing Gleam formatting issues detected when running `just ci` locally... Deferred to Phase 6."

The problem is that deferring this to Phase 6 leaves the CI enforcement goal of Phase 5 (TARGET-03) incomplete: the `test-erlang` GitHub Actions job runs `just format-check` as its first step, which will fail before the test suite ever executes. CI is structurally correct but functionally blocked.

**Root cause fix:** Run `gleam format src test` and commit the result. This is a one-command fix (no logic changes) that will allow the Erlang CI job to reach and execute all 228 tests.

---

_Verified: 2026-03-01T16:00:00Z_
_Verifier: Claude (gsd-verifier)_
