---
phase: 7
slug: publishing
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-05
---

# Phase 7 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | gleeunit (Gleam) + shell assertions |
| **Config file** | gleam.toml |
| **Quick run command** | `gleam test` |
| **Full suite command** | `gleam test --target erlang && gleam test --target javascript` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `gleam test`
- **After every plan wave:** Run `gleam test --target erlang && gleam test --target javascript`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 7-01-01 | 01 | 1 | PUB-01 | file check | `grep -q 'description' gleam.toml && grep -q 'repository' gleam.toml && grep -q 'licences' gleam.toml` | N/A | pending |
| 7-01-02 | 01 | 1 | PUB-01 | file check | `grep -v 'YOUR_NAME' LICENSE` | N/A | pending |
| 7-02-01 | 02 | 1 | PUB-02 | file check | `grep -q 'gleam add lattice' README.md && grep -q 'import lattice' README.md` | N/A | pending |
| 7-03-01 | 03 | 1 | PUB-03 | file check | `test -f CHANGELOG.md && grep -q '1.1' CHANGELOG.md` | N/A | pending |
| 7-04-01 | 04 | 2 | PUB-04 | command | `gleam build && gleam docs build` | N/A | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements. No new test stubs needed — this phase is metadata/documentation only.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Hex.pm publish | PUB-04 | Requires API key and network access | Run `gleam publish --yes` with HEXPM_API_KEY set |
| Hex.pm listing | PUB-04 | External service verification | Check https://hex.pm/packages/lattice after publish |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
