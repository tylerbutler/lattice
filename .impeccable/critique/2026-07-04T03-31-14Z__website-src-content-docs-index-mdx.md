---
target: website/src/content/docs/index.mdx
total_score: 26
p0_count: 0
p1_count: 3
timestamp: 2026-07-04T03-31-14Z
slug: website-src-content-docs-index-mdx
---
Method: dual-agent (A: critique-design-review · B: critique-detector-evidence)

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|------:|-----------|
| 1 | Visibility of System Status | 3 | Starlight navigation/search likely communicates location; static splash has no major status needs. |
| 2 | Match System / Real World | 3 | Strong technical language for Gleam developers, but CRDT newcomers get little framing on the splash. |
| 3 | User Control and Freedom | 3 | Clear navigation and CTAs; no trapping flows. |
| 4 | Consistency and Standards | 3 | Starlight patterns are consistent; homepage storytelling conflicts with the new brand principles. |
| 5 | Error Prevention | 2 | Does not prevent package-choice mistakes or wrong entry path decisions. |
| 6 | Recognition Rather Than Recall | 2 | Users must infer which CRDT/package fits their need from a flat set of cards. |
| 7 | Flexibility and Efficiency of Use | 3 | Quick Start and sidebar IA support efficient movement. |
| 8 | Aesthetic and Minimalist Design | 2 | Clean, but the identical card grid is generic and weakens distinctiveness. |
| 9 | Error Recovery | 2 | Docs do not yet help users recover from wrong package/API choices on the homepage. |
| 10 | Help and Documentation | 3 | Surrounding docs IA is strong; homepage routing could be sharper. |
| **Total** | | **26/40** | **Acceptable foundation; significant homepage design improvement needed.** |

## Anti-Patterns Verdict

**LLM assessment**: This does not look broken, but it does look template-shaped. The hero is credible and the gradient-text issue is gone, but the primary content is still a repeated Starlight `CardGrid` of icon + title + text cards. That directly conflicts with the PRODUCT/DESIGN anti-reference against identical icon-card grids as the main storytelling device. The page has the ingredients of “The Convergence Notebook” — rigorous copy, committed plum/magenta tokens, better fonts — but not the artifact that makes it memorable.

**Deterministic scan**: The bundled detector found no issues. `detect.mjs --json website/src/content/docs/index.mdx` exited `0` with `[]`. No rule names or file locations were reported.

**Visual overlays**: No user-visible overlay is available for this run. Browser automation is not exposed in this environment, so Assessment B could not open a fresh tab, inject `detect.js`, or collect console overlay messages.

## Overall Impression

The homepage is a solid Starlight docs splash with better typography and a disciplined palette, but it is not yet a designed brand surface. The biggest opportunity is replacing the flat seven-card feature grid with a proof-oriented onboarding artifact: something that helps a skeptical Gleam developer understand convergence, choose the right CRDT, and trust the library in one memorable pass.

## What's Working

1. **The strategic foundation is strong.** “Property-based tested merge semantics” is specific, credible, and better than generic devtool positioning.
2. **The new visual system is appropriate.** Bricolage Grotesque + Atkinson Hyperlegible supports the “precise, mathematical, approachable” direction without falling into a banned mono/devtool reflex.
3. **The surrounding docs IA is clear.** `Start Here`, `Guides`, and `Advanced` in `astro.config.mjs` are understandable groupings for evaluation and learning.

## Priority Issues

### **[P1] The homepage is a default card grid, not “The Convergence Notebook”**
**Why it matters**: The main content violates the project’s own anti-reference and does not make correctness visible. A CRDT library should show convergence, not only list features.
**Fix**: Replace the flat feature grid with a proof-oriented artifact: a small replica merge diagram, package chooser, or “local update → merge → same value” notebook panel.
**Suggested command**: `/impeccable craft homepage convergence artifact`

### **[P1] Seven equal choices overload the evaluation moment**
**Why it matters**: Developers evaluating CRDTs need fast orientation. Seven equal cards force them to classify counters/registers/sets/maps/presence/delta/modularity themselves.
**Fix**: Chunk into no more than four visible paths: “Start”, “Choose a CRDT”, “Understand merge semantics”, and “Pick packages”.
**Suggested command**: `/impeccable layout website/src/content/docs/index.mdx`

### **[P1] The pre-1.0 caution appears before earned confidence**
**Why it matters**: Honesty builds trust, but leading with “quality should not be considered production-ready” before showing rigor creates avoidable anxiety.
**Fix**: Pair the caution with reassurance: tested merge laws, target support, explicit instability scope, and invitation for feedback. Consider moving it after a proof/value block.
**Suggested command**: `/impeccable clarify website/src/content/docs/index.mdx`

### **[P2] Icons feel generic and semantically weak**
**Why it matters**: Rocket/settings/puzzle icons read as stock devtool residue, not mathematical calm. They make the site feel assembled from defaults.
**Fix**: Use text-first structures, package labels, mathematical symbols, or minimal diagrams instead of generic Starlight icon cards.
**Suggested command**: `/impeccable quieter website/src/content/docs/index.mdx`

### **[P2] The package-selection story is underused**
**Why it matters**: The site already has strong package guidance, but the splash does not expose the key installation decision: umbrella package vs focused package.
**Fix**: Add a compact decision block that points users to `lattice_crdt` for everything or individual packages for minimal dependencies.
**Suggested command**: `/impeccable onboard website/src/content/docs/index.mdx`

## Persona Red Flags

**Jordan (CRDT/Gleam first-timer)**: The splash uses “CRDTs” and “property-based tested merge semantics” credibly, but it does not explain the concept before presenting seven cards. Jordan sees labels, not a learning path. The pre-1.0 caution may make them leave before they reach Quick Start.

**Riley (deliberate evaluator / trust tester)**: Riley wants evidence: merge law examples, package boundaries, serialization behavior, and test guarantees. The homepage claims correctness but does not show a proof artifact or route directly to the strongest evidence. The pre-1.0 warning is honest but underspecified: what is safe to try, and what is unstable?

**Casey (mobile / distracted reader)**: The caution block plus seven-card grid becomes scroll fatigue. The strongest next action after the cards is unclear, and the page ends on “Modular” rather than a decisive next step.

## Minor Observations

- `Features` is too generic for a mathematically precise brand.
- `Presence` and `Delta-State Sync` deserve different treatment than the core CRDT families.
- `logo.alt: "lattice logo"` is serviceable but generic.
- The global color/token work is disciplined; the homepage needs local composition, not just global theming.

## Questions to Consider

- What if the homepage taught convergence with one tiny worked merge before listing any features?
- What if “Features” became “Choose the shape of your state”?
- What would make a skeptical distributed-systems engineer trust this page in 10 seconds?
- Should the final impression be “many CRDTs available” or “I understand which one to install”?
