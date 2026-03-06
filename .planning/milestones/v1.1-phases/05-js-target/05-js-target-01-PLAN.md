---
phase: 05-js-target
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - justfile
autonomous: true
requirements:
  - TARGET-01
  - TARGET-02

must_haves:
  truths:
    - "gleam test --target javascript passes all 228+ tests with zero failures"
    - "No JS-specific failures exist (all CRDT modules compile and run correctly on JS target)"
    - "justfile has working test-js and test-all commands (uncommented and functional)"
    - "just test-all runs tests on both Erlang and JavaScript targets sequentially"
  artifacts:
    - path: "justfile"
      provides: "Multi-target build and test commands for Erlang and JavaScript"
      exports: ["test-erlang", "test-js", "test-all", "build-js", "build-strict-js", "build-strict-all"]
  key_links: []
---

<objective>
Verify the full test suite passes on the JavaScript target and enable multi-target justfile commands.

Purpose: Confirm TARGET-01 (all tests pass on JS) and TARGET-02 (identify/fix any JS-specific failures). Since Gleam compiles to both Erlang and JavaScript, we need to verify that all 228+ CRDT tests pass on the JS target before enforcing it in CI. Then uncomment the justfile multi-target support section so developers can easily run `just test-all`.

Output: Verified JS target compatibility, updated justfile with active multi-target commands.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@justfile
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Verify JS target and activate justfile multi-target commands</name>
  <files>justfile</files>
  <behavior>
    - `gleam test --target javascript` passes all 228+ tests with zero failures
    - `gleam build --target javascript --warnings-as-errors` succeeds with no warnings
    - justfile multi-target section is uncommented and active
    - `just test-js` runs JavaScript target tests
    - `just test-all` runs both Erlang and JavaScript target tests
    - `just build-strict-all` builds both targets with warnings as errors
    - The `ci` recipe is updated to use `test-all` instead of `test` and `build-strict-all` instead of `build-strict`
  </behavior>
  <action>
**Step 1: Verify JS target**

Run and confirm:
```bash
gleam test --target javascript
gleam build --target javascript --warnings-as-errors
```

Both commands must succeed with zero failures/warnings. If any failures occur, fix them before proceeding (this addresses TARGET-02). Based on reconnaissance, all 228 tests already pass.

**Step 2: Uncomment justfile multi-target commands**

In the justfile, uncomment the "MULTI-TARGET SUPPORT" section (lines ~91-114). The final result should have these active recipes:

```just
# Build for JavaScript target
build-js:
    gleam build --target javascript

# Build all targets
build-all: build build-js

# Build JavaScript with warnings as errors
build-strict-js:
    gleam build --target javascript --warnings-as-errors

# Build all targets strictly
build-strict-all: build-strict build-strict-js

# Test on Erlang target
test-erlang:
    gleam test

# Test on JavaScript target
test-js:
    gleam test --target javascript

# Test on all targets
test-all: test-erlang test-js
```

**Step 3: Update ci and main recipes**

Update the `ci` recipe to test both targets:
```just
# Run all CI checks (format, check, test all targets, build strict all targets)
ci: format-check check test-all build-strict-all
```

The `main` recipe already depends on `ci` so it inherits the change.

**Step 4: Verify everything works**

Run:
```bash
just test-all
just build-strict-all
```

Both must succeed.

Do NOT uncomment the "JAVASCRIPT INTEGRATION TESTS" or "COVERAGE" sections -- those are not needed for this phase.
  </action>
  <verify>
    <automated>just test-all 2>&1 | grep -E "(Tests:|passed)"</automated>
    <automated>just build-strict-all 2>&1 | echo "exit: $?"</automated>
  </verify>
  <done>
    - gleam test --target javascript passes all 228+ tests
    - justfile has active test-js, test-all, build-strict-js, build-strict-all recipes
    - ci recipe uses test-all and build-strict-all
    - just test-all succeeds (both Erlang and JS targets)
  </done>
</task>

</tasks>

<verification>
1. `just test-all` -- both Erlang and JavaScript targets pass all tests
2. `just build-strict-all` -- both targets build with warnings as errors
3. `just ci` -- full CI check passes locally
</verification>

<success_criteria>
- TARGET-01: All 228+ tests pass with `gleam test --target javascript`
- TARGET-02: No JS-specific failures found (or all fixed if any discovered)
- justfile multi-target commands are active and working
- ci recipe enforces both targets
</success_criteria>

<output>
After completion, create `.planning/phases/05-js-target/05-js-target-01-SUMMARY.md`
</output>
