# Lattice — Roadmap

## Milestones

- ✅ **v1.0 CRDT Library** — Phases 1-4 (shipped 2026-03-01)
- 🚧 **v1.1 Production Ready** — Phases 5-7 (in progress)

## Phases

<details>
<summary>✅ v1.0 CRDT Library (Phases 1-4) — SHIPPED 2026-03-01</summary>

- [x] Phase 1: Foundation & Counters (3/3 plans) — completed 2026-02-28
- [x] Phase 2: Registers & Sets (4/4 plans) — completed 2026-03-01
- [x] Phase 3: Maps & Serialization (4/4 plans) — completed 2026-03-01
- [x] Phase 4: Advanced Testing (3/3 plans) — completed 2026-03-01

</details>

---

### 🚧 v1.1 Production Ready (In Progress)

**Milestone Goal:** Polish, document, test on JS target, and publish lattice to Hex.pm.

- [x] **Phase 5: JS Target** - All 228+ tests pass on both Erlang and JavaScript targets with CI enforcing both
- [ ] **Phase 6: Docs & API Polish** - All public API documented, reviewed for consistency, and hexdocs builds clean
- [ ] **Phase 7: Publishing** - Package metadata complete, README written, CHANGELOG created, and published to Hex.pm

## Phase Details

### Phase 5: JS Target
**Goal**: All existing tests pass on the JavaScript target and CI enforces dual-target coverage going forward
**Depends on**: Phase 4
**Requirements**: TARGET-01, TARGET-02, TARGET-03
**Success Criteria** (what must be TRUE):
  1. `gleam test --target javascript` completes with all 228+ tests passing
  2. Any JS-specific failures discovered are identified and fixed before proceeding
  3. CI workflow runs the full test suite against both Erlang and JavaScript targets on every push
**Plans**: 2 plans
**Completed**: 2026-03-01

### Phase 6: Docs & API Polish
**Goal**: Every public function and type has doc comments, the API surface is consistent and ergonomic, and hexdocs generates without warnings
**Depends on**: Phase 5
**Requirements**: DOCS-01, DOCS-02, DOCS-03, DOCS-04, API-01, API-02, API-03
**Success Criteria** (what must be TRUE):
  1. Every public function has a `///` doc comment describing its behavior
  2. Every public type has a `///` doc comment
  3. Each module has a module-level documentation block with a usage example
  4. `gleam docs build` completes without warnings and the generated hexdocs are readable
  5. All public function signatures follow consistent naming and argument-order conventions, with opaque types used where internals should be hidden
**Plans**: TBD

### Phase 7: Publishing
**Goal**: Lattice is published to Hex.pm with complete metadata and user-facing documentation
**Depends on**: Phase 6
**Requirements**: PUB-01, PUB-02, PUB-03, PUB-04
**Success Criteria** (what must be TRUE):
  1. gleam.toml contains complete metadata: name, description, repository URL, and license
  2. README.md covers installation, a quickstart example, and an overview of the CRDT types
  3. CHANGELOG.md documents the changes from v1.0 to v1.1
  4. `gleam publish` succeeds and the package appears on Hex.pm
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation & Counters | v1.0 | 3/3 | Complete | 2026-02-28 |
| 2. Registers & Sets | v1.0 | 4/4 | Complete | 2026-03-01 |
| 3. Maps & Serialization | v1.0 | 4/4 | Complete | 2026-03-01 |
| 4. Advanced Testing | v1.0 | 3/3 | Complete | 2026-03-01 |
| 5. JS Target | v1.1 | 2/2 | Complete | 2026-03-01 |
| 6. Docs & API Polish | v1.1 | 0/? | Not started | - |
| 7. Publishing | v1.1 | 0/? | Not started | - |

---

*Roadmap created: 2026-02-28*
*v1.0 shipped: 2026-03-01*
*v1.1 roadmap added: 2026-03-01*
