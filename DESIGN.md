---
name: lattice
description: Conflict-free replicated data types for Gleam, presented with mathematical precision and approachable documentation.
colors:
  accent: "#f54780"
  accent-low: "#3d1527"
  accent-high: "#f9b0cb"
  ink: "#2a0818"
  white: "#ffffff"
  blush-1: "#ffe7ee"
  blush-2: "#f5a8c0"
  blush-3: "#e8729a"
  plum-1: "#a8345e"
  plum-2: "#6e1f3d"
  plum-3: "#4d1029"
typography:
  display:
    fontFamily: "Bricolage Grotesque, Atkinson Hyperlegible, sans-serif"
    fontWeight: 700
    lineHeight: 1
    letterSpacing: "-0.02em"
  headline:
    fontFamily: "Bricolage Grotesque, Atkinson Hyperlegible, sans-serif"
    fontWeight: 600
    lineHeight: 1.1
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Atkinson Hyperlegible, sans-serif"
    fontWeight: 400
    lineHeight: 1.65
  label:
    fontFamily: "Atkinson Hyperlegible, sans-serif"
    fontWeight: 700
    lineHeight: 1.2
components:
  docs-primary-action:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.white}"
  docs-secondary-action:
    backgroundColor: "{colors.accent-low}"
    textColor: "{colors.accent-high}"
  docs-card:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.blush-1}"
---

# Design System: lattice

## 1. Overview

**Creative North Star: "The Convergence Notebook"**

lattice should feel like rigorous proofs made readable: a precise technical notebook where every visual choice helps developers trust the convergence model, choose the right CRDT, and move into code. The system is documentation-first, but it still needs a memorable public face: saturated magenta and plum tones give the library identity without becoming generic devtool gloss.

The typography now pairs Bricolage Grotesque for headings with Atkinson Hyperlegible for body copy. The display voice is distinctive enough for a brand surface, while the body face keeps long CRDT explanations, package lists, and code-adjacent guidance easy to scan. The site must reject the generic SaaS/devtool landing-page grammar named in PRODUCT.md: gradient heroes, metric blocks, identical icon-card repetition as a default, vague scale copy, and decorative technical noise.

**Key Characteristics:**
- Precise, mathematical, approachable.
- Documentation density with a clear public identity.
- Magenta/plum color as structure, not decoration.
- High-contrast reading surfaces for long-form technical content.
- Honest pre-1.0 caution presented as trust-building context.

## 2. Colors

The palette is a committed magenta/plum system: saturated enough to be recognizable, narrow enough to preserve mathematical calm.

### Primary
- **Convergence Magenta** (`accent`): the primary action and identity color. Use it for links, primary actions, active states, and rare emphasis where the reader should change direction.
- **Low Plum Field** (`accent-low`): the dark supporting accent behind prominent callouts and secondary action treatments.
- **Proof Pink Highlight** (`accent-high`): the light accent for dark surfaces, hover affordances, and high-emphasis supporting text.

### Neutral
- **Ink Plum** (`ink`): the deepest surface and text anchor. It keeps dark mode branded instead of generic black.
- **White** (`white`): the clean counter-surface for light-mode pages and documentation chrome.
- **Blush Ramp** (`blush-1`, `blush-2`, `blush-3`): light-to-mid documentation tones for text, borders, and quiet emphasis.
- **Plum Ramp** (`plum-1`, `plum-2`, `plum-3`): structural darker tones for dividers, navigation, and dark-mode surfaces.

### Named Rules
**The One Proof Color Rule.** Magenta is the proof mark: it should identify actions, links, and selected state. Do not scatter it as decoration.

**The No Gradient Hero Rule.** Gradient text and gradient hero treatments are prohibited. The brand is carried by type, color discipline, and explanatory artifacts.

## 3. Typography

**Display Font:** Bricolage Grotesque, with Atkinson Hyperlegible and sans-serif fallbacks.
**Body Font:** Atkinson Hyperlegible, with sans-serif fallback.
**Label/Mono Font:** Use Atkinson Hyperlegible for labels unless a code block or syntax renderer supplies a true code face.

**Character:** Headings should feel constructed and memorable, like labels on a mathematical specimen. Body copy should feel generous, legible, and clear enough for readers who are learning CRDT vocabulary for the first time.

### Hierarchy
- **Display** (700, fluid Starlight hero scale, 1 line-height): splash titles and high-level page identity only.
- **Headline** (600, section heading scale, 1.1 line-height): major documentation sections, guide titles, and package group headings.
- **Title** (600, compact heading scale, 1.2 line-height): cards, asides, navigation group labels, and local section titles.
- **Body** (400, Starlight body scale, 1.65 line-height): paragraphs, lists, tables, and prose explanations. Keep long-form content near 65-75ch where layout allows.
- **Label** (700, compact scale, 1.2 line-height): action text, badges, tabs, and dense metadata.

### Named Rules
**The Readable Math Rule.** If a typography choice makes a proof, code example, package table, or warning harder to read, it is wrong no matter how distinctive it looks.

## 4. Elevation

lattice is flat by default. Depth comes from tonal layering inside the magenta/plum ramp, Starlight's structural borders, and clear content grouping rather than heavy shadows. Hover and focus states may use slight tonal shifts, but persistent shadow stacks should not become part of the brand.

### Named Rules
**The Flat Notebook Rule.** Surfaces are pages, not floating panes. Use borders, spacing, and tone before shadow.

## 5. Components

The site uses Astro Starlight primitives with project-owned color and typography overrides. Components should stay recognizably Starlight for docs usability, while the palette and heading voice make them lattice-specific.

### Buttons
- **Shape:** inherit Starlight's action shape; do not add oversized pill styling.
- **Primary:** Convergence Magenta background with high-contrast text for the "Get started" path.
- **Hover / Focus:** preserve visible focus outlines. Hover may deepen toward Low Plum Field, but must not rely on color alone.
- **Secondary / Ghost:** use Low Plum Field and Proof Pink Highlight relationships rather than gray-on-gray neutrality.

### Cards / Containers
- **Corner Style:** inherit Starlight card geometry.
- **Background:** dark surfaces use Ink Plum; light surfaces use White and Blush Ramp tones.
- **Shadow Strategy:** flat by default; use border and tonal contrast instead of ambient shadows.
- **Border:** subtle plum/blush borders are acceptable when they improve grouping.
- **Internal Padding:** keep Starlight's generous documentation padding; do not compress cards into SaaS tiles.

### Navigation
- **Style:** navigation should prioritize orientation: package group, guide group, advanced material. Active states should use the magenta/plum system and remain readable in both themes.
- **Typography:** use the body face for navigation labels so sidebars remain scannable.
- **Mobile:** preserve Starlight's responsive navigation patterns rather than inventing custom chrome.

### Asides
- **Style:** caution and note asides are trust-building moments. Their color should communicate importance without theatrical warning styling.
- **Tone:** copy should be direct, especially for the pre-1.0 warning.

## 6. Do's and Don'ts

### Do:
- **Do** use Convergence Magenta for meaningful action, active, and link states.
- **Do** keep Bricolage Grotesque focused on headings and identity moments.
- **Do** use Atkinson Hyperlegible for long-form docs, package explanations, and guides.
- **Do** show correctness with code, examples, package boundaries, and explanatory diagrams.
- **Do** preserve high contrast for docs and code in both light and dark themes.

### Don't:
- **Don't** use generic SaaS/devtool landing-page clichés: gradient heroes, metric blocks, identical icon-card grids as the primary storytelling device, or vague "scale your workflow" copy.
- **Don't** use gradient text.
- **Don't** turn CRDT rigor into a dense academic archive.
- **Don't** use monospace as decorative shorthand for "technical"; reserve code faces for code.
- **Don't** add glassmorphism, oversized glow, or ambient shadows as a default surface treatment.
