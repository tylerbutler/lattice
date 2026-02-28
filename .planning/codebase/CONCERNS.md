# Codebase Concerns

**Analysis Date:** 2026-02-28

## Placeholder/Template Code

**Project Name and Placeholder Content:**
- Issue: The entire codebase is a template with placeholders. Package name is `my_gleam_project`, description is generic "A Gleam project", repository config points to `YOUR_USERNAME`.
- Files: `gleam.toml`, `src/my_gleam_project.gleam`, `README.md`
- Impact: The project is not yet ready for publication to Hex.pm. Attempting to publish with placeholder values will fail or produce incorrect package metadata.
- Fix approach: Before any release or CI/CD execution, replace all placeholder values: project name, description, repository URL, and license owner. Update `gleam.toml` with actual package metadata and realistic GitHub repository configuration.

**Example Placeholders:**
- `gleam.toml:` `name = "my_gleam_project"` (generic template name)
- `gleam.toml:` `description = "A Gleam project"` (no meaningful description)
- `gleam.toml:` `repository = { type = "github", user = "YOUR_USERNAME", repo = "my_gleam_project" }` (placeholder username)
- `examples/hello_world/src/hello_world.gleam:` Line 3 - hardcoded "Run with: gleam run -m hello_world" without verifying this is the actual module name

## Incomplete API Surface

**Minimal Public API:**
- Issue: Only a single `hello/1` function exists in `src/my_gleam_project.gleam`. The comment says "Replace this with your library's public API" but provides no guidance on what the actual library should implement.
- Files: `src/my_gleam_project.gleam` (14 lines total)
- Impact: No real functionality exists. Tests exist only to verify the template function works, not the actual business logic. Publishing this as a library would be misleading to users.
- Fix approach: Define the actual public API. Remove the hello function and implement real functionality. Consider breaking the API into submodules in `src/my_gleam_project/` for better organization.

## Inadequate Test Coverage

**Test Helpers Used But Not in Tests:**
- Issue: `test/test_helpers.gleam` defines utility functions (`sample_data()`, `sample_list()`, `ok_result()`, `error_result()`) but none are used in `test/my_gleam_project_test.gleam`. The helpers remain untested themselves.
- Files: `test/test_helpers.gleam` (53 lines), `test/my_gleam_project_test.gleam` (17 lines)
- Impact: Test utilities may contain bugs or incorrect behavior that won't be caught. The test helpers provide generic utilities that may not align with actual testing needs once real API functions exist.
- Fix approach: Either integrate these helpers into actual tests, or remove unused ones. Ensure all test utilities are exercised by real test cases.

**Test Count Mismatch:**
- Issue: Only 2 test functions exist (`hello_test()` and `hello_gleam_test()`) both testing the same trivial `hello/1` function. No error cases, edge cases, or negative tests.
- Files: `test/my_gleam_project_test.gleam`
- Impact: Once real functionality is added, the test suite will be far behind in coverage. No testing infrastructure exists for error handling, which is core to Gleam's Result type pattern.
- Fix approach: Establish a comprehensive testing strategy aligned with the actual API design. Include error cases and edge cases from the start.

## Configuration and Setup Concerns

**Changelog Configuration Duplication:**
- Issue: Both `.changie.yaml` and `.changie.no-kinds.yaml` exist simultaneously. The README explains you can switch between them, but having both creates confusion and potential for misalignment.
- Files: `.changie.yaml` (45 lines), `.changie.no-kinds.yaml`
- Impact: Developers may accidentally commit using the wrong configuration. The `.no-kinds.yaml` file should either be removed or clearly documented as "do not use unless intentionally switching."
- Fix approach: Decide on the changelog format (with kinds or without) early in development. Remove the unused config file. Document the choice clearly.

**CI Workflow Template Files Not Removed:**
- Issue: Template files exist: `.github/workflows/ci-multi-target.yml.template` and `.github/workflows/ci-shared-actions.yml.template` which should be removed or migrated once the actual CI approach is finalized.
- Files: `.github/workflows/ci-multi-target.yml.template`, `.github/workflows/ci-shared-actions.yml.template`
- Impact: Developers may accidentally use outdated templates instead of the active `ci.yml`. Repository contains unused files that increase maintenance burden.
- Fix approach: Remove template files once multi-target support or shared actions approach is definitively rejected. If multi-target is planned, implement it properly and remove the template.

**Missing Git Configuration:**
- Issue: Git user identity is not configured locally. The release workflow depends on `RELEASE_PAT` and `HEXPM_API_KEY` secrets which are not verified to exist in the repository settings.
- Files: Git config (implicit), `.github/workflows/release.yml`, `.github/workflows/publish.yml`
- Impact: Release workflows will fail silently if secrets are not configured. Developers attempting to test CI/CD locally will encounter git author issues.
- Fix approach: Document required GitHub repository secrets in README or CLAUDE.md. Add a setup check to verify secrets exist before release.

## Version Constraint Concerns

**Flexible Version Ranges:**
- Issue: `gleam.toml` uses loose version constraints: `gleam = ">= 1.7.0"` (no upper bound) and `gleam_stdlib = ">= 0.48.0 and < 2.0.0"` (wide range). This allows building with significantly different dependency versions.
- Files: `gleam.toml` (lines 1-15)
- Impact: Reproducibility issues. Builds could work differently across CI and local environments if newer Gleam versions introduce breaking changes. The 0.x to 2.0 range for stdlib is particularly wide.
- Fix approach: Pin to specific minor versions during development: `gleam = ">= 1.14.0 and < 2.0.0"` (current is 1.14.0). Review and test against constraint boundaries before releases.

**No Minimum Erlang/OTP Requirement Documented:**
- Issue: `.tool-versions` specifies Erlang 27.2.1 but `gleam.toml` makes no mention of Erlang/OTP version requirements.
- Files: `.tool-versions` (lists erlang 27.2.1), `gleam.toml` (no erlang constraint)
- Impact: Package consumers may have incompatible Erlang versions. No dependency specification in package metadata.
- Fix approach: Add a note in README about minimum supported OTP version, or ensure the Gleam compiler version constraint implicitly handles this.

## Documentation Gaps

**Missing Implementation Guidance:**
- Issue: Both `CLAUDE.md` and `DEV.md` use template language: "Replace this with your library's public API", "Modify as needed for your project". No actual design decisions are documented.
- Files: `CLAUDE.md` (lines 1-4), `DEV.md` (multiple sections)
- Impact: Developers lack clear guidance on what this library should do, how it's structured, and what patterns to follow for new functionality.
- Fix approach: Create an `ARCHITECTURE.md` or project specification document describing the library's purpose, core concepts, and design decisions.

**Example Project Incomplete:**
- Issue: `examples/hello_world/` is a minimal example that only demonstrates the template `hello/1` function. It doesn't show how to use real functionality, error handling, or complex workflows.
- Files: `examples/hello_world/src/hello_world.gleam` (17 lines)
- Impact: Users have no realistic usage examples. The example won't be useful once the actual API is implemented.
- Fix approach: Develop the API first, then create comprehensive examples demonstrating various features, error cases, and typical workflows.

## Potential Release Issues

**Publish Workflow May Fail:**
- Issue: `.github/workflows/publish.yml` publishes on any `v*` tag without verifying changelog entry exists or that the version was released through normal processes. The `release.yml` uses changie but publish.yml only runs `gleam publish`.
- Files: `.github/workflows/publish.yml`, `.github/workflows/release.yml`
- Impact: Manual `v*` tags could trigger publication of unvetted code. No integration between changelog management and publishing.
- Fix approach: Ensure only release.yml can create version tags. Document that manual `v*` tags should never be created. Consider adding a check that ensures `CHANGELOG.md` has been updated.

**No Pre-Publication Verification:**
- Issue: The publish workflow doesn't verify that all tests pass on the exact tagged commit before publishing to Hex.pm.
- Files: `.github/workflows/publish.yml` (line 11-13)
- Impact: A release could be published even if a previous commit broke tests, if the tag was applied to an untested commit.
- Fix approach: The `needs: test` dependency ensures CI runs first, but verify this works correctly. Document the release process clearly.

## Missing Capabilities

**No Built-in Examples for Gleam Patterns:**
- Issue: No examples of Result type usage, error handling patterns, or pattern matching best practices in the codebase.
- Impact: Users unfamiliar with Gleam may not understand how to properly use the library when it's implemented.
- Fix approach: Add examples to `examples/` demonstrating error handling, type-safe operations, and common patterns.

**JavaScript Target Not Configured:**
- Issue: Gleam supports JavaScript target but the main project is Erlang-only. The justfile has commented-out JS build targets but they're never activated.
- Files: `justfile` (lines 88-138, all commented)
- Impact: If JavaScript support is desired later, this infrastructure exists but is unmaintained and may be out of date.
- Fix approach: Either commit to JavaScript target support and enable it, or clearly document that this project is Erlang-only and remove the commented sections.

## Security Considerations

**No Dependency Audit Configuration:**
- Issue: No tooling configured to check for known vulnerabilities in Gleam dependencies.
- Impact: Vulnerable transitive dependencies could be used without detection.
- Fix approach: Consider adding automated dependency auditing (though Gleam ecosystem tooling for this is limited compared to Node.js/Rust).

**Secrets Handling in CI:**
- Issue: CI configuration references `RELEASE_PAT` and `HEXPM_API_KEY` secrets but doesn't verify they exist or handle missing secrets gracefully.
- Files: `.github/workflows/release.yml` (line 18), `.github/workflows/publish.yml` (line 23)
- Impact: If secrets aren't configured, workflows will fail at runtime with unclear error messages.
- Fix approach: Add explicit secret verification steps or use GitHub's built-in secret validation.

---

*Concerns audit: 2026-02-28*
