---
phase: 06-docs-api-polish
plan: 03
type: execute
wave: 2
depends_on: ["01", "02"]
files_modified:
  - src/lattice/*.gleam
autonomous: true
requirements:
  - DOCS-01
  - DOCS-02
  - DOCS-03
  - DOCS-04
  - API-01
  - API-02
  - API-03

must_haves:
  truths:
    - "gleam docs build completes without warnings from lattice code (dependency warnings are acceptable)"
    - "All 12 modules have //// module-level docs"
    - "All public functions across all 12 modules have /// doc comments"
    - "All public types across all 12 modules have /// doc comments"
    - "gleam test passes on both Erlang and JavaScript targets"
    - "gleam format --check src test passes"
    - "The generated hexdocs are readable and well-organized"
  artifacts: []
  key_links: []
---

<objective>
Final verification pass: confirm all 12 modules are documented, hexdocs build is clean, tests pass on both targets, and the API is consistent end-to-end.

Purpose: This is the gatekeeper plan for Phase 6. Plans 01 and 02 did the actual work — this plan runs comprehensive verification to confirm all phase success criteria are met before marking the phase complete.

Output: Verified Phase 6 completion with all DOCS and API requirements satisfied.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Verify all module-level documentation exists</name>
  <files>src/lattice/*.gleam</files>
  <behavior>
    - All 12 source modules under src/lattice/ have //// module-level docs at the top
    - Each module-level doc includes a brief description and a usage example
    - If any module is missing module-level docs, add them (gap closure)
  </behavior>
  <action>
**Step 1: Check all modules for //// module docs**

Run a check to verify every module starts with `////`:

```bash
for f in src/lattice/*.gleam; do
  first_code_line=$(head -1 "$f")
  if echo "$first_code_line" | grep -q "^////"; then
    echo "OK: $f"
  else
    echo "MISSING: $f"
  fi
done
```

If any are MISSING, add module-level docs following the pattern from Plans 01 and 02.

**Step 2: Verify doc examples are syntactically plausible**

Spot-check that the usage examples in module docs use correct function names and reasonable patterns. Read the first 20 lines of each module and visually confirm the example code is accurate.
  </action>
  <verify>
    <automated>for f in src/lattice/*.gleam; do head -1 "$f" | grep -q "^////" && echo "OK: $f" || echo "MISSING: $f"; done</automated>
  </verify>
  <done>
    - All 12 modules have //// module-level docs
    - Examples in module docs use correct API
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: Verify hexdocs build and all tests pass</name>
  <files>src/lattice/*.gleam</files>
  <behavior>
    - `gleam docs build` completes successfully
    - No warnings originating from lattice source code
    - `gleam test` passes (Erlang target)
    - `gleam test --target javascript` passes (JS target)
    - `gleam format --check src test` passes
    - `gleam build --warnings-as-errors` passes
  </behavior>
  <action>
**Step 1: Build hexdocs**

```bash
gleam docs build
```

Verify it completes. Any warnings from dependency packages (startest, interior) are acceptable. Warnings from `src/lattice/` are NOT acceptable -- fix them.

**Step 2: Run full test suite on both targets**

```bash
just test-all
```

All tests must pass on both Erlang and JavaScript targets.

**Step 3: Verify code quality**

```bash
gleam format --check src test
gleam build --warnings-as-errors
```

Both must pass.

**Step 4: Verify API consistency across all modules**

Run a quick scan of all public signatures to confirm consistent patterns:

```bash
rg '^pub (fn|type|opaque)' src/lattice/ | sort
```

Verify:
- Every module with a main type has: new, [mutators], [queries], merge, to_json, from_json
- Naming is consistent (e.g., `value` not `get_value`, `merge` not `combine`)
- Argument order is consistent (the "self" argument comes first in every function)

If any inconsistencies are found, fix them (they should have been caught in Plans 01/02 but this is the safety net).

**Step 5: Spot-check generated hexdocs**

Open the generated docs and verify:
- Each module page has a module description at the top
- Functions are listed with their doc comments
- Types show their doc comments
- No broken formatting or empty sections

The docs are at `build/dev/docs/lattice/index.html`.
  </action>
  <verify>
    <automated>gleam docs build 2>&1 | grep -v "^  " | grep -v "^$"</automated>
    <automated>just test-all 2>&1 | tail -10</automated>
    <automated>gleam format --check src test 2>&1; echo "exit: $?"</automated>
    <automated>gleam build --warnings-as-errors 2>&1; echo "exit: $?"</automated>
  </verify>
  <done>
    - gleam docs build completes (dependency warnings only, none from lattice)
    - All tests pass on Erlang target
    - All tests pass on JavaScript target
    - Code is formatted correctly
    - No build warnings
    - Hexdocs are readable and well-organized
  </done>
</task>

</tasks>

<verification>
1. `gleam docs build` -- completes with no lattice warnings
2. `just test-all` -- all tests pass on both targets
3. `gleam format --check src test` -- passes
4. `gleam build --warnings-as-errors` -- passes
5. All 12 modules have //// module-level docs confirmed by grep
</verification>

<success_criteria>
- DOCS-01: Every public function has a /// doc comment (confirmed)
- DOCS-02: Every public type has a /// doc comment (confirmed)
- DOCS-03: Every module has //// module-level docs with usage examples (confirmed)
- DOCS-04: gleam docs build generates clean hexdocs without warnings (confirmed)
- API-01: Public function signatures follow consistent naming and argument-order conventions (confirmed)
- API-02: Opaque types used where appropriate (confirmed)
- API-03: Missing convenience functions identified and documented (confirmed)
</success_criteria>

<output>
After completion, create `.planning/phases/06-docs-api-polish/06-docs-api-polish-03-SUMMARY.md`
</output>
