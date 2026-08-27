# Thalyx — Implementation Plan

**Thalyx** is a cross-platform (macOS + Linux) desktop diagramming tool in the spirit of
OmniGraffle, with a ruthless focus on **simple, fast, user-friendly UX**, and with **Mermaid as a
first-class citizen**: paste or open Mermaid text and it becomes a fully editable diagram; edit any
diagram by hand and export its logical structure back to clean Mermaid — while also supporting
native, high-fidelity drag-and-drop editing that has nothing to do with Mermaid.

This document is the **authoritative implementation plan**. It was produced after a deep research
pass (desktop shells, canvas libraries, the Mermaid API — including hands-on verification of every
load-bearing API claim against `mermaid@11.17.0` — diagramming UX, and persistence architecture).
The raw research notes live in [`docs/research/`](docs/research/); **where a research note and this
plan disagree, this plan wins** (the notes contain superseded recommendations — see
`docs/research/README.md`).

The plan is written so that a careful but less-capable engineer or LLM can implement it
milestone-by-milestone without making architectural decisions of their own. Every open question
found during research has been resolved into a **binding decision** (§2). Follow them.

---

## Table of contents

1. [Product vision & principles](#1-product-vision--principles)
2. [Binding decisions](#2-binding-decisions)
3. [Scope: MVP, post-MVP, never](#3-scope-mvp-post-mvp-never)
4. [Licensing policy](#4-licensing-policy)
5. [Tech stack](#5-tech-stack)
6. [Architecture & repository layout](#6-architecture--repository-layout)
7. [Document model](#7-document-model)
8. [State management & undo/redo](#8-state-management--undoredo)
9. [Mermaid integration](#9-mermaid-integration)
10. [Interaction & UX specification](#10-interaction--ux-specification)
11. [Canvas subsystems](#11-canvas-subsystems)
12. [Desktop shell (Electron)](#12-desktop-shell-electron)
13. [Export pipeline](#13-export-pipeline)
14. [Security model](#14-security-model)
15. [Testing strategy](#15-testing-strategy)
16. [CI/CD & releases](#16-cicd--releases)
17. [Milestones](#17-milestones)
18. [Risks & mitigations](#18-risks--mitigations)
19. [Rules for the implementing engineer/LLM](#19-rules-for-the-implementing-engineerllm)

---

## 1. Product vision & principles

Thalyx sits between two worlds and must be excellent in both:

- **The OmniGraffle world**: precise, high-fidelity diagrams built by hand — real shapes, clean
  orthogonal connectors, alignment guides, beautiful exports.
- **The Mermaid world**: diagrams as text — versionable, diffable, generatable by tools and LLMs.

The bridge is the product: **a diagram in Thalyx is always both a picture and a graph.** Nodes and
edges are first-class model objects (never just pixels), so converting to/from Mermaid is pure
serialization, not inference.

Design principles (each is enforceable in review):

1. **Open straight onto a canvas.** No template pickers, no accounts, no dialogs at launch.
   (Excalidraw's zero-friction start is the most-loved onboarding in this product category;
   Miro's template-first onboarding is the most complained about.)
2. **One gesture per intent.** Creating a connected node is one keystroke (`Mod+Arrow`) or one
   click (hover chevrons) — never draw-shape-then-draw-arrow-then-type.
3. **A curated few beats a configurable many.** ~10 colors, 3 stroke widths, 4 font sizes, 5
   toolbar shapes. Full pickers exist but are demoted. (Excalidraw's documented palette
   philosophy.)
4. **One context panel, never inspector stacks.** The panel shows only what applies to the current
   selection. (OmniGraffle's nested inspectors are its #1 "heavy" complaint; draw.io's Format
   panel is the same failure.)
5. **Layout is an action, never a mode.** Auto-layout and Tidy Up are one-shot, undoable commands.
   (OmniGraffle's persistent auto-layout is documented — by OmniGroup itself — as something users
   must turn off.)
6. **Never lose work, never ask about it.** Continuous autosave, atomic writes, crash recovery.
   No "unsaved changes?" dialogs in the normal flow.
7. **Everything is undoable.** Import, auto-layout, style changes — one `Mod+Z` each.
8. **The graph is sacred.** Connections never break when shapes move. Geometry is derived from
   the graph, not the other way around.

Non-goals are listed in §3 ("never" column) — resist scope creep toward them.

---

## 2. Binding decisions

Research surfaced several contradictions and open questions. They are resolved **here, once**.
Do not relitigate these during implementation.

| # | Question | Decision | Rationale (short) |
|---|---|---|---|
| D1 | Desktop shell | **Electron (v43+, latest supported major at M0)**, electron-vite, electron-builder, electron-updater. Not Tauri. | Tauri's Linux engine (WebKitGTK) is a maintainer-acknowledged source of canvas perf bugs ("silently land on a slow path" per Tauri's own docs; ~40fps vs 240fps reports; NVIDIA/DMABUF breakage) and its version is controlled by the user's distro, not the app. WKWebView caps ~60fps on macOS. Chromium removes the whole class of risk; every serious canvas editor (Figma desktop, draw.io desktop, Obsidian) ships Electron. Single-language TS stack is also the easiest to implement correctly. Accepted cost: ~100–250 MB installers, Chromium upgrade treadmill. Full analysis: `docs/research/shell.md`. |
| D2 | Canvas/editor library | **React Flow (`@xyflow/react` ^12.11)** with custom node/edge components. Not tldraw (license-disqualified), not JointJS (undo/snaplines/halo paywalled on MPL core), not Excalidraw-as-library (no custom shape API), not a custom engine. | Its controlled `nodes[]`/`edges[]` arrays are effectively already the Mermaid logical model; MIT; best docs/ecosystem by far. Accepted DIY: undo, alignment guides, elbow routing, quick-connect UX (all specced below). Full analysis: `docs/research/canvas.md`. |
| D3 | Layout engine | **`@dagrejs/dagre` ^3.1 (MIT) is the only layout engine in the MVP.** elkjs is **deferred to M9** as an optional enhancement behind an explicit EPL-2.0 licensing sign-off. | dagre is pure MIT (no license decision needed), synchronous, tiny, actively maintained again (v3.1.1, 2026-08), and matches Mermaid's own default flowchart look. elkjs's orthogonal edge routing is better but is dual `EPL-2.0 OR GPL-3.0-or-later` — usable (Apache Category B precedent; Mermaid itself depends on it) but requires attribution obligations we don't need for MVP. Note: research notes `canvas.md` recommend elkjs-primary; **this decision supersedes that**. |
| D4 | Undo/redo | **Hand-rolled snapshot history** (~100 LOC, specced in §8). No `zundo` dependency. | Snapshot history over an immutable doc slice is the hardest-to-get-wrong option; zundo's compatibility with current zustand was not verified and a dependency is not worth 100 LOC. Delta/patch history (what Excalidraw/tldraw use) exists only for multiplayer — Thalyx is single-user local-first. |
| D5 | Grouping / containment model | **Single-parent containment via `parentId`** ("containers"). No Excalidraw-style `groupIds[]` in v1. `Mod+G` wraps the selection in a new container node; `Mod+Shift+G` dissolves it. | One containment model serves React Flow subflows AND Mermaid subgraphs 1:1. Two competing grouping systems (containment + selection-groups) is a known source of model bugs. |
| D6 | Multi-page documents | **No.** One canvas per file. Schema v1 has top-level `nodes`/`edges` (no `pages[]`). If pages ever come, that's schema v2 with a trivial normalize-on-load migration (wrap existing content as page 1). | Keeps every subsystem (store, exporter, importer, undo) one level flatter for the implementer. UX research explicitly puts multi-canvas in the do-not-build list. |
| D7 | Node rotation | **No rotation.** No `angle` field in schema v1. | Breaks Mermaid round-trip semantics and elbow routing for near-zero diagram value. (Excalidraw's elbow+rotation interaction was a documented bug farm.) |
| D8 | Minimap | **Not rendered.** Do not mount React Flow's `<MiniMap/>`. | Zoom-to-fit (`Shift+1`) + zoom-to-selection (`Shift+2`) replace it; none of the "fast" tools ship one. |
| D9 | Mermaid parse init sequence | Canonical sequence (verified in the lab): **(1)** in tests only: install jsdom globals *before* dynamically importing mermaid; **(2)** `await mermaid.parse(text, {suppressErrors: true})` — returns `false` on invalid input and, critically, registers the lazy diagram detectors; **(3)** `await mermaid.mermaidAPI.getDiagramFromText(text)` → `{type, db}`. | The alternative single-call `registerExternalDiagrams([], {lazyLoad:false})` init also works, but the lab-verified parse-first sequence is the one with real output dumps behind it; standardize on it. In the app, parsing runs in the **renderer** (real Chromium DOM — no jsdom shims needed at runtime; jsdom is test-only). |
| D10 | mermaid `htmlLabels` | **`htmlLabels: false` always** (`mermaid.initialize({ flowchart: { htmlLabels: false }, htmlLabels: false, ... })`). | Makes rendered preview SVGs self-contained `<text>` (no `foreignObject>`), which exports cleanly and behaves identically everywhere. |
| D11 | PDF export | **`svg2pdf.js` + `jsPDF` (both MIT), driven from the model-rendered SVG.** The "Print…" menu item uses `webContents.print()` (native print dialog); `webContents.printToPDF` is not used anywhere. | Vector fidelity + one export pipeline for all formats. (The research note's "never webview print-to-PDF" rule was a Tauri-specific argument; under Electron the choice is re-justified here on fidelity/pipeline-unity grounds.) |
| D12 | Edge geometry authority | Edge geometry is **always derived** for attached endpoints. Optional user waypoints (`waypoints[]`) exist only for manually adjusted routes and are **cleared whenever either endpoint node moves or resizes**. The Mermaid exporter ignores geometry entirely. | One simple invalidation rule beats incremental route-repair; keeps export pure. |
| D13 | Where positions live across round-trip | Positions live **only in `.thalyx` files**. Exported `.mmd` is pure logic — no coordinate comments/frontmatter smuggling. Re-importing text into an *open* document goes through `reconcileDocument()` (§9.6), which preserves positions of matched nodes. A fresh import of a `.mmd` file gets auto-layout. | Keeps exported Mermaid idiomatic and diff-friendly; hand-tuned layout is preserved through the reconcile path, which is the path users actually use. |
| D14 | Mermaid diagram-type scope | **Flowcharts: full native round-trip (import + export) in MVP.** **Every other Mermaid type: imported as a live "Mermaid island" node** (rendered SVG whose source text stays editable in a dialog). State-diagram *native* import/export is the first post-MVP target (M9); sequence/class/ER native support is v2+. | Flowcharts are ~the whole graph-editing use case and FlowDB is the richest verified surface. Islands give *meaningful* day-one support for all 40 diagram types without inventing canvas UX for lifelines/compartments now. |
| D15 | Grow-gesture & keymap conflicts | Keymap in §10.2 is final. Notables: `Mod+Arrow` grow (gated off while text-editing, so macOS `Cmd+Arrow` text navigation is unaffected); Tidy Up = **`Alt+Shift+T`** (NOT Figma's `Ctrl+Alt+T`, which launches a terminal on Ubuntu/GNOME); Auto-layout = `Alt+Shift+L`; theme = `Shift+Alt+D`; Mermaid panel = **`Mod+Shift+M`** (`Mod+M` is consumed by the app's own Window→Minimize menu role). Chords containing `Alt`, and `Shift`+digit chords, must be matched on `e.code` — see the §10.2 implementation note. | OS/self conflicts checked per-platform; see §10.2. |
| D16 | Mermaid version | **Pin `mermaid` exactly (`11.17.0`, no caret)**. Upgrades only via the golden-corpus gate (§15). | Every db property name Thalyx relies on is internal, semver-unprotected API, verified against exactly 11.17.0. |
| D17 | dompurify license arm | Thalyx elects the **Apache-2.0 arm** of dompurify's `MPL-2.0 OR Apache-2.0` dual license (it arrives as a mermaid transitive dep and is also used directly for island-SVG sanitization). Record in `THIRD_PARTY_LICENSES.md`. | Keeps the dependency ledger permissive-only. |
| D18 | Windows | **Out of scope for this plan.** Nothing may *preclude* it (avoid mac/linux-only APIs where an equivalent exists), but no Windows CI, packaging, or testing. | User requirement is Mac + Linux. |
| D19 | App font | Bundle **Inter** (SIL OFL-1.1) as the canvas/diagram font, `system-ui` stack for UI chrome. Exported SVG uses `font-family="Inter, system-ui, sans-serif"` (not embedded); PDF export registers the bundled Inter TTF with jsPDF. | Deterministic text metrics across macOS/Linux (fontconfig variance is the remaining Linux variable under Chromium). OFL is fine for bundling as an asset; ledger entry required. Known limitation: PDF export of non-Latin text falls back (documented in §13). |
| D20 | Package manager / workspace | **npm** (not pnpm/yarn), **single package** (no monorepo). | Lowest-friction, best-known toolchain for the implementing model. |

---

## 3. Scope: MVP, post-MVP, never

### MVP (milestones M0–M8)

- Infinite canvas; pan/zoom; light & dark themes.
- Shapes: rectangle, rounded rectangle, ellipse, diamond, cylinder in the toolbar; the full
  Mermaid flowchart shape set renderable (§7.3); text elements; containers (subgraphs).
- Connectors: elbow (default), straight, curved; floating attachment; arrowhead options;
  edge labels; solid/dashed/thick line styles.
- Full editing UX floor (§10): single-key tools, `Mod+Arrow` grow, hover quick-connect chevrons,
  inline text editing, alt-drag duplicate, smart guides + equal-spacing snapping, curated palette,
  one context panel, z-order, containers, select/multi-select, nudge.
- Undo/redo of everything; autosave + crash recovery; `.thalyx` files; recents; file associations.
- **Mermaid**: paste/open → native editable flowchart (or island for other types) with
  auto-layout; live read-only Mermaid text panel; "Apply" text edits with position-preserving
  reconcile; copy/save as `.mmd`; golden-corpus round-trip tests.
- Export: SVG, PNG (1x/2x), PDF, clipboard (PNG + Mermaid text); Print….
- One-shot Auto-layout and Tidy Up actions.
- Packaged builds: dmg (mac arm64+x64), AppImage + deb + rpm (linux x64), auto-update feed,
  GitHub Actions CI + release pipeline.

### Post-MVP backlog (M9+, in rough priority order)

1. State diagram native round-trip (import via `db.getData()` flat+`parentId` surface; export
   serializer).
2. elkjs orthogonal routing & layout option (requires the D3 licensing sign-off + attribution).
3. Fixed ports/magnets per node (N/S/E/W anchor pinning is already in the schema; UI for it).
4. Obstacle-avoiding interactive edge routing (A*, references: Excalidraw elbow-arrow write-ups,
   JointJS manhattan router options — **ideas only, never code**, see §4).
5. Stencil/shape-library format + a small searchable insert popup.
6. Multi-window (one doc per window), then maybe multi-page (schema v2).
7. Embed document JSON inside exported PNG/SVG (Excalidraw-style re-openable exports).
8. Sequence/class/ER native editing; Mermaid frontmatter config editing UI.
9. i18n of the UI; IME hardening pass beyond the basic `isComposing` guards; RTL labels.
10. Flatpak/Flathub distribution.

### Never (bloat list — each rejected for cause, see `docs/research/ux.md` §4)

Persistent auto-layout mode; inspector stacks / tabbed format panels; minimap; giant stencil trees
in-app; full color picker as primary styling; node rotation; realtime multiplayer; template
galleries / onboarding wizards / accounts; presentation modes, comments, stamps, timers; live
data/spreadsheet import; multi-page documents (in this plan's lifetime); hand-drawn "sketchy"
rendering; scripting/automation; freehand pen as a core tool.

---

## 4. Licensing policy

Thalyx's own code is dedicated to the public domain under the repository's existing
**Unlicense**. That imposes rules on everything we pull in:

**Allowed dependency licenses** (runtime and dev): MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause,
ISC, 0BSD, Unlicense, CC0-1.0, BlueOak-1.0.0. Fonts: SIL OFL-1.1 (as bundled assets).

**Banned**: GPL/AGPL/LGPL (any version), MPL (as *code we'd modify*; see dompurify exception D17),
EPL (until/unless the M9 elkjs sign-off happens), SSPL, BUSL, "source-available", and any license
requiring keys/watermarks. Concretely banned packages that research evaluated and rejected:
`tldraw`/`@tldraw/*` (proprietary watermark license), `gojs` (commercial), `mxgraph` (dead),
`libavoid-js` (LGPL), `@joint/*` (MPL + paywalled features).

**Rules for the implementer:**

1. **CI license gate** (M0): `scripts/check-licenses.mjs` runs `license-checker-rseidelsohn`
   twice — over **production deps (violations FAIL the build)** and over dev deps (violations
   print a WARNING report only; dev toolchains drag in odd transitive licenses that never ship).
   Dual-licensed packages resolve via an explicit elections map in the script (initially:
   `dompurify → Apache-2.0`).
2. **`THIRD_PARTY_LICENSES.md`** is generated by `scripts/gen-third-party-licenses.mjs` (same
   library) and surfaced in the About dialog. Regenerate whenever deps change.
3. **Ideas, never code**: you may *read about* tldraw's architecture, JointJS's manhattan router
   options, and React Flow **Pro** examples (undo/redo, helper lines — those examples are paid,
   non-MIT), but you must **never transcribe their code**. Implement from the specs in this plan.
4. Copying from MIT sources (Excalidraw, React Flow core, mermaid-to-excalidraw) is legally fine
   **but not into our tree as-is**: prefer re-implementation; if a verbatim copy is genuinely
   needed, place it under `src/vendor/<pkg>/` with its copyright header intact and add a ledger
   entry. (An Unlicense project can contain clearly-marked MIT files; it just can't silently
   absorb them.)
5. The public-domain dedication covers **Thalyx's own source**. Installers necessarily bundle
   MIT/BSD/etc. dependencies (Electron/Chromium above all); the About dialog + ledger make that
   explicit. Do not claim the *distribution* is public domain.
6. `CONTRIBUTING.md` (M0) states: contributions are accepted only as public-domain dedications
   under the Unlicense (DCO-style sign-off line).

---

## 5. Tech stack

Versions below were verified current on 2026-08-23. At M0, install the then-current versions of
everything **except mermaid (pinned exactly)**; if a major version has moved, check its changelog
before adopting (§19 rule 6).

| Layer | Choice | Version (2026-08) | License |
|---|---|---|---|
| Desktop shell | `electron` | ^43 (Chromium ~M150; verify current at M0) | MIT |
| Build tooling | `electron-vite`, `vite`, `typescript` (strict) | current | MIT |
| Packaging | `electron-builder` (+ `electron-updater`) | ^27 | MIT |
| UI framework | `react`, `react-dom` | ^19 | MIT |
| Canvas | `@xyflow/react` | ^12.11.3 | MIT |
| State | `zustand` | current major (verify v5 API at M0) | MIT |
| Immutability | `immer` | ^10 | MIT |
| Validation | `zod` | ^4 (or current) | MIT |
| Mermaid | `mermaid` | **=11.17.0 (exact pin)** | MIT |
| Mermaid sanitize | `dompurify` (direct dep for islands) | ^3.4 | Apache-2.0 (elected) |
| Layout | `@dagrejs/dagre` | ^3.1.1 | MIT |
| IDs | `nanoid` | ^5 | MIT |
| PDF | `jspdf`, `svg2pdf.js` | ^3 / ^2.7 | MIT |
| Font | Inter (static TTF + woff2 assets) | current | OFL-1.1 |
| Unit tests | `vitest` | ^4 | MIT |
| DOM for node tests | `jsdom` | ^30 | MIT |
| E2E | `@playwright/test` (`_electron`) | current | Apache-2.0 |
| Lint/format | `eslint` (+ typescript-eslint), `prettier` | current | MIT |
| License gate | `license-checker-rseidelsohn` (dev) | current | BSD-3 |

Explicitly **not** used in MVP: `elkjs` (D3), `zundo` (D4), `html-to-image` (export renders from
the model, §13), `@excalidraw/mermaid-to-excalidraw` (we implement our own importer against the
same db API; theirs is reference reading), `electron-store` (hand-rolled JSON prefs, §12.5).

---

## 6. Architecture & repository layout

Three Electron contexts + one shared pure-TS core. **The doctrine: everything interesting is a
pure function over the document model**; Electron and React are thin shells around
`src/shared/`.

```
thalyx/
├── PLAN.md                      # this file
├── LICENSE                      # Unlicense (exists)
├── README.md
├── CONTRIBUTING.md
├── THIRD_PARTY_LICENSES.md      # generated
├── package.json
├── electron.vite.config.ts
├── electron-builder.yml
├── tsconfig.json / tsconfig.node.json / tsconfig.web.json
├── .github/workflows/ci.yml
├── .github/workflows/release.yml
├── scripts/
│   ├── check-licenses.mjs
│   └── gen-third-party-licenses.mjs
├── resources/                   # icons (icns/png), Inter font files
├── src/
│   ├── shared/                  # PURE TS — no Electron, no React, no DOM (except mermaid via injected env)
│   │   ├── model/
│   │   │   ├── types.ts         # Doc, ThalyxNode, ThalyxEdge, Style… (§7)
│   │   │   ├── schema.ts        # zod schemas
│   │   │   ├── restore.ts       # restoreDocument() normalize-on-load (§7.5)
│   │   │   ├── create.ts        # factories: newDoc/newNode/newEdge with defaults
│   │   │   └── queries.ts       # selectors: nodesInContainer, edgesOfNode, bounds…
│   │   ├── geometry/
│   │   │   ├── vec.ts, rect.ts  # primitives
│   │   │   ├── anchors.ts       # boundary-intersection for floating attach (§11.2)
│   │   │   ├── elbow.ts         # elbow router (§11.3)
│   │   │   └── shapes.ts        # shapePath(kind, w, h) → SVG path data (§7.3)
│   │   ├── snap/
│   │   │   └── snap.ts          # smart-guide engine (§11.4)
│   │   ├── layout/
│   │   │   ├── dagreLayout.ts   # autoLayout(doc | subset, direction) (§11.5)
│   │   │   └── tidy.ts          # tidyUp(selection) grid/row/column (§11.5)
│   │   ├── mermaid/
│   │   │   ├── detect.ts        # isProbablyMermaid(text) (§9.7)
│   │   │   ├── import.ts        # importMermaid(text) → ImportResult (§9.3)
│   │   │   ├── export.ts        # exportMermaid(doc, {selection?}) → {text, idAssignments} — pure (§9.4)
│   │   │   ├── reconcile.ts     # reconcileDocument(doc, imported) (§9.6)
│   │   │   ├── entities.ts      # placeholder decode / entity encode (§9.2)
│   │   │   └── tables.ts        # arrow/shape/LINETYPE mapping tables (§9.2)
│   │   ├── export/
│   │   │   └── svg.ts           # renderDocToSvg(doc, opts) → string (§13.1)
│   │   └── files/
│   │       └── thalyxFile.ts    # serialize/deserialize .thalyx (§7.4)
│   ├── main/                    # Electron main process
│   │   ├── index.ts             # app lifecycle, single-instance, window creation
│   │   ├── menu.ts              # application menu (§12.3)
│   │   ├── ipc.ts               # all ipcMain.handle registrations (§12.2)
│   │   ├── files.ts             # atomic writes, backups, recovery store (§12.4)
│   │   ├── prefs.ts             # prefs + recents + window-state JSON (§12.5)
│   │   └── security.ts          # navigation/window-open/permission lockdown (§14)
│   ├── preload/
│   │   └── index.ts             # contextBridge → window.thalyx (§12.2)
│   └── renderer/
│       ├── index.html           # CSP meta (§14)
│       ├── main.tsx
│       ├── App.tsx
│       ├── store/
│       │   ├── store.ts         # zustand store: doc + session slices (§8.1)
│       │   ├── history.ts       # snapshot undo/redo (§8.2)
│       │   └── actions.ts       # ALL doc mutations live here (§8.3)
│       ├── canvas/
│       │   ├── Canvas.tsx       # <ReactFlow> wiring
│       │   ├── nodes/           # ShapeNode.tsx, TextNode.tsx, ContainerNode.tsx, MermaidIslandNode.tsx
│       │   ├── edges/           # ThalyxEdge.tsx (elbow/straight/curved + label chip)
│       │   ├── overlays/        # GuideLines.tsx, QuickConnectChevrons.tsx, HintLayer.tsx
│       │   └── hooks/           # useKeymap.ts, useGrowGesture.ts, usePasteImport.ts…
│       ├── panels/
│       │   ├── Toolbar.tsx      # left tool strip
│       │   ├── ContextPanel.tsx # selection-scoped properties (§10.3)
│       │   ├── MermaidPanel.tsx # live text panel (§9.5)
│       │   └── HelpOverlay.tsx  # Shift+/ shortcut sheet
│       ├── mermaid/
│       │   └── runtime.ts       # mermaid.initialize + parse/render wrappers (renderer-side)
│       ├── platform/
│       │   └── api.ts           # typed wrapper over window.thalyx with browser-mode fallback (§15.2)
│       └── theme/               # CSS variables, palette (§10.4)
└── tests/
    ├── unit/                    # vitest specs mirroring src/shared
    ├── corpus/                  # golden .mmd files + expected model JSON (§15.1)
    └── e2e/                     # Playwright specs (§15.2)
```

**Data-flow doctrine:**

- The **renderer owns the document** (zustand store). All mutations go through named action
  functions in `store/actions.ts`; each action = one history entry (or is explicitly marked
  transient, §8).
- The **main process owns the OS**: file IO, dialogs, menus, recents, updater. It never parses or
  interprets documents beyond zod validation of IPC payloads.
- **Mermaid runs in the renderer** (real DOM). jsdom appears only in vitest.
- `src/shared/` imports nothing from React/Electron and is where ~70% of unit tests live.

---

## 7. Document model

### 7.1 TypeScript types (authoritative)

```ts
// src/shared/model/types.ts
export type NodeId = string;      // nanoid(12)
export type EdgeId = string;

export type ShapeKind =
  // toolbar set (MVP visible)
  | 'rect' | 'rounded' | 'ellipse' | 'diamond' | 'cylinder'
  // full mermaid flowchart set (renderable, reachable via import & shape popup)
  | 'stadium' | 'circle' | 'doublecircle' | 'subroutine' | 'hexagon'
  | 'parallelogram' | 'parallelogram-alt' | 'trapezoid' | 'trapezoid-alt' | 'asymmetric';

export interface NodeStyle {
  fill: string;          // token like 'surface' | palette key like 'blue' | '#rrggbb'
  stroke: string;
  strokeWidth: 1 | 2 | 4;                 // thin | medium | bold
  fontSize: 12 | 14 | 18 | 24;            // S | M | L | XL
  textAlign: 'center';                    // reserved; only center in MVP
}
// NOTE: there is deliberately NO corner-radius style property. Sharp vs rounded rectangles are
// two ShapeKinds ('rect' vs 'rounded') — one representation only, so Mermaid export ([x] vs (x))
// can never disagree with what the canvas shows. The context panel's sharp/round toggle swaps
// the ShapeKind between 'rect' and 'rounded' (shown only for those two kinds).

export interface ThalyxNode {
  id: NodeId;
  kind: 'shape' | 'text' | 'container' | 'mermaid';
  shape?: ShapeKind;                      // kind === 'shape'
  x: number; y: number;                   // top-left, absolute canvas coords…
                                          // …but for children of a container: RELATIVE to parent
                                          // (React Flow parentId convention — keep it)
  width: number; height: number;
  label: string;                          // plain text; '\n' allowed
  parentId?: NodeId;                      // containment (container nodes only as parents)
  locked?: boolean;
  hidden?: boolean;                       // e.g. mermaid '~~~' phantom targets
  style: NodeStyle;
  // kind === 'mermaid' (island):
  mermaidSource?: string;
  meta?: NodeMeta;
}

export interface NodeMeta {
  mermaid?: {
    id?: string;            // mermaid node id, e.g. 'A' — round-trip anchor
    shape?: string;         // original mermaid vertex.type if it differs from our mapping (e.g. new '@{shape: …}' names)
    classes?: string[];     // mermaid class assignments
    styles?: string[];      // raw 'fill:#f9f' strings from `style`/classDef we didn't map
    link?: string;          // click href
    tooltip?: string;
    labelType?: 'text' | 'string' | 'markdown';
    dir?: 'TB' | 'BT' | 'LR' | 'RL';  // containers only: subgraph-local `direction` (round-tripped)
  };
}

export type ArrowHead = 'none' | 'arrow' | 'circle' | 'cross';

export interface EdgeStyle {
  line: 'solid' | 'dashed' | 'thick';
  stroke: string;
  rounded: boolean;                       // rounded elbow corners
}

export interface ThalyxEdge {
  id: EdgeId;
  source: NodeId;
  target: NodeId;
  sourceAnchor: 'auto' | 'n' | 's' | 'e' | 'w';   // 'auto' floats; cardinal values pin handles
  targetAnchor: 'auto' | 'n' | 's' | 'e' | 'w';
  kind: 'elbow' | 'straight' | 'curved';
  label?: string;
  labelT?: number;                        // 0..1 position of label along route (default 0.5)
  arrowStart: ArrowHead;                  // default 'none'
  arrowEnd: ArrowHead;                    // default 'arrow'
  hidden?: boolean;                       // mermaid '~~~'
  waypoints?: { x: number; y: number }[]; // manual route override; cleared on endpoint move (D12)
  style: EdgeStyle;
  meta?: {
    mermaid?: {
      id?: string;                        // only when isUserDefinedId
      minlen?: number;                    // mermaid edge.length > 1
      styles?: string[];                  // raw linkStyle strings
    };
  };
}

export interface ThalyxDoc {
  type: 'thalyx';
  version: 1;
  source: string;                         // 'thalyx@<appVersion>'
  nodes: ThalyxNode[];                    // z-order = array order (first = back)
  edges: ThalyxEdge[];
  canvas: { background: 'default' | string; grid: boolean };
  meta: {
    mermaid?: {
      direction: 'TB' | 'BT' | 'LR' | 'RL';   // default 'TB'
      frontmatter?: string;               // verbatim '---\n…\n---\n' block, re-emitted on export
      classDefs?: Record<string, string[]>;   // classDef name -> raw style strings
      sourceText?: string;                // last imported/applied mermaid text (for the panel diff)
    };
  };
}
```

Style color values: prefer **palette tokens** (`'blue'`, `'red'`, … — §10.4) so themes remap
them; raw hex is allowed (from mermaid imports / custom picker) and renders as-is in both themes.

### 7.2 Model invariants (enforce in `actions.ts` + assert in tests)

1. Every `edge.source`/`edge.target` references an existing, non-island node. Deleting a node
   deletes its edges (same history entry).
2. `parentId` chains: only `kind:'container'` may be a parent; containers may nest; no cycles.
   Children store coordinates **relative to the parent** (React Flow convention).
3. Z-order = `nodes[]` order; containers must appear **before** their children in the array
   (React Flow requirement).
4. `label` is plain text — never HTML. Rendering escapes it (React does by default; never use
   `dangerouslySetInnerHTML` for labels).
5. Islands (`kind:'mermaid'`) never participate in edges.
6. All numbers finite; width/height ≥ 8.
7. **Re-parenting preserves absolute position.** Because child coordinates are parent-relative,
   *every* code path that changes a node's `parentId` (drag-across-container re-parent in §11.1,
   `groupIntoContainer`/`dissolveContainer`, reconcile §9.6 step 1) must convert the stored
   `x/y` so the node's absolute canvas position is unchanged
   (`abs = own + Σ ancestor offsets`; recompute relative under the new parent).
   `restoreDocument()` (§7.5) clamps/repairs invariants 1–6 on load.

### 7.3 Shape rendering

One pure function `shapePath(kind, w, h): string` in `src/shared/geometry/shapes.ts` returns SVG
path data for every `ShapeKind` (rect/rounded are trivial; diamond = 4-point polygon; cylinder =
path with ellipse caps; parallelogram/trapezoid = skewed quads with a fixed 0.2·w skew;
asymmetric = flag shape; doublecircle = two concentric ellipses — return two paths joined).
`ShapeNode.tsx` renders `<svg><path d={…}/></svg>` + a centered label div. The same function is
reused by `renderDocToSvg` — **canvas and export share geometry by construction**.

Mermaid vertex.type → ShapeKind mapping (from the verified FlowDB dump):

| mermaid `type` | syntax | ShapeKind |
|---|---|---|
| *(absent)* / `square` | `A` / `A[x]` | `rect` |
| `round` | `A(x)` | `rounded` |
| `stadium` | `A([x])` | `stadium` |
| `circle` | `A((x))` | `circle` |
| `doublecircle` | `A(((x)))` | `doublecircle` |
| `ellipse` | `A(-x-)` | `ellipse` |
| `diamond` | `A{x}` | `diamond` |
| `hexagon` | `A{{x}}` | `hexagon` |
| `cylinder` | `A[(x)]` | `cylinder` |
| `subroutine` | `A[[x]]` | `subroutine` |
| `lean_right` | `A[/x/]` | `parallelogram` |
| `lean_left` | `A[\x\]` | `parallelogram-alt` |
| `trapezoid` | `A[/x\]` | `trapezoid` |
| `inv_trapezoid` | `A[\x/]` | `trapezoid-alt` |
| `odd` | `A>x]` | `asymmetric` |
| anything else (v11.3 `@{shape:…}` names like `cyl`, `diam`) | | nearest of the above by lookup table; original string preserved in `meta.mermaid.shape` and re-emitted on export |

### 7.4 File format

`.thalyx` = the `ThalyxDoc` JSON, pretty-printed 2-space, UTF-8, trailing newline (diff-friendly).
Suggested MIME `application/vnd.thalyx+json`. `thalyxFile.ts`:
`serializeDoc(doc): string` (strips runtime-only fields, sorts nothing — array order is data) and
`parseDoc(text): ThalyxDoc` (JSON.parse → `restoreDocument`).

### 7.5 Loading & migrations: normalize, don't migrate

`restoreDocument(raw: unknown): ThalyxDoc` (Excalidraw's `restore()` strategy):

1. If `raw?.version > 1` → throw `DocTooNewError` (UI: "made with a newer Thalyx").
2. Otherwise **coerce whatever arrives into a valid v1 doc**: fill every missing field with
   defaults from `create.ts`, drop unknown fields, drop edges whose endpoints don't resolve,
   fix z-order/parent ordering, clamp numbers. Never throw on merely-weird data.
3. zod-validate the result (`schema.ts`) as the final assertion.

This is deliberately not an ordered migration chain — normalize-on-load is dramatically easier to
implement correctly and tolerates hand-written files.

---

## 8. State management & undo/redo

### 8.1 Store shape (zustand)

One store, two slices. **Only `doc` is persisted and history-tracked.**

```ts
interface StoreState {
  doc: ThalyxDoc;
  session: {
    filePath: string | null;
    dirtySinceSave: boolean;
    selection: { nodeIds: NodeId[]; edgeIds: EdgeId[] };
    tool: 'select' | 'shape' | 'arrow' | 'line' | 'text' | 'container' | 'hand';
    pendingShape: ShapeKind;          // which shape the 'shape' tool places (toolbar buttons and
                                      // R/O/D set tool:'shape' + this; lets the toolbar offer
                                      // rect/rounded/ellipse/diamond/cylinder with one tool)
    toolLocked: boolean;
    editingLabel: { kind: 'node' | 'edge'; id: string } | null;
    viewport: { x: number; y: number; zoom: number };
    theme: 'system' | 'light' | 'dark';
    guides: GuideLine[];              // transient smart-guide render state
    chevronsEnabled: boolean;         // Q toggle
    mermaidPanelOpen: boolean;
  };
}
```

React Flow is used **controlled**: `nodes`/`edges` props are derived from `doc` via memoized
selectors (`toReactFlowNodes(doc)` maps `ThalyxNode` → RF `Node` with
`type`, `position`, `parentId`, `selected`, and the Thalyx node in `data`). RF change callbacks
(`onNodesChange` etc.) are translated back into store actions — position changes are applied as
**transient** updates during a drag and committed once on drag-end (§8.2).

### 8.2 Snapshot history (hand-rolled — D4)

`src/renderer/store/history.ts`, ~100 LOC, no dependency:

```ts
interface History { past: ThalyxDoc[]; future: ThalyxDoc[]; pending: ThalyxDoc | null; }
const LIMIT = 100;

// commit(prevDoc): called by the action wrapper BEFORE a tracked mutation
//   past.push(prevDoc); if (past.length > LIMIT) past.shift(); future = [];
// beginGesture(): pending ??= current doc   (call on drag/resize/label-edit start)
// endGesture():   if (pending && changed) { past.push(pending); future=[] } pending = null
// undo():  if past empty → no-op; future.push(current); doc = past.pop()
// redo():  symmetric
```

Because `doc` is updated immutably (immer inside actions), snapshots are structurally shared —
memory cost per entry is only the changed path. Rules:

- **One user intent = one entry.** Multi-step actions (delete node + its edges; import; auto-layout;
  reconcile) mutate once inside a single `produce`.
- **Gesture coalescing**: pointer-driven streams (drag, resize, waypoint drag, label typing) go
  through `beginGesture`/`endGesture` — one entry per gesture.
- Selection/viewport/tool are **not** in history (session slice). After undo, prune selection ids
  that no longer exist.
- `Mod+Z` / `Mod+Shift+Z` / `Mod+Y`; menu Edit items dispatch the same actions.

### 8.3 Actions catalog

Every doc mutation is a named function in `actions.ts` taking/returning plain data, wrapped by
`tracked(fn)` (history commit) or `transient(fn)` (drag frames). Initial catalog — implement
exactly these, add sparingly:

`addNode, updateNodeLabel, updateNodeStyle, setNodeShape, setNodeLocked, moveNodes(transient+gesture),
resizeNode(gesture), setNodesPosition, deleteSelection, duplicateSelection,
alignSelection(edge: 'left'|'hcenter'|'right'|'top'|'vcenter'|'bottom'), addEdge, updateEdge,
setEdgeWaypoints(gesture), clearEdgeWaypoints, reorderZ(op: 'forward'|'backward'|'front'|'back'),
groupIntoContainer, dissolveContainer, setCanvas, setDirection(dir), importMermaidAsNew,
applyMermaidText(reconcile), autoLayout, tidyUp, pasteInternal, toggleGrid`.

One deliberate exception to history tracking: **`ensureMermaidIds`** applies the id assignments
returned by `exportMermaid` (§9.4 step 1) to `meta.mermaid.id`. It is **untracked** — it creates
no history entry (it is idempotent bookkeeping metadata, a fixpoint after one pass, and it can be
triggered by merely *viewing* the Mermaid panel, which must never pollute undo). It is the only
untracked doc mutation in the app; document it with a comment at the definition.

---

## 9. Mermaid integration

This section encodes the **hands-on verified ground truth** from
`docs/research/mermaid-ground-truth.md` (real API dumps from `mermaid@11.17.0`, Node 22). That
file is the regression reference; if any assertion here surprises you, check there first — do not
"fix" the plan from memory of other mermaid versions.

### 9.1 Runtime setup (renderer)

```ts
// src/renderer/mermaid/runtime.ts
import mermaid, { type MermaidConfig } from 'mermaid';
mermaid.initialize({
  startOnLoad: false,
  securityLevel: 'strict',
  htmlLabels: false,
  flowchart: { htmlLabels: false },       // D10
  theme: 'neutral',
});

export async function parseMermaid(text: string): Promise<
  | { ok: true; diagramType: string; config: MermaidConfig; db: any }   // MermaidConfig, not Record — strict TS rejects the interface→Record assignment
  | { ok: false; error: { message: string; line?: number; col?: number; expected?: string[] } }
> {
  const res = await mermaid.parse(text, { suppressErrors: true }); // false on invalid; ALSO registers lazy detectors (D9)
  if (res === false) {
    try { await mermaid.parse(text); } catch (e: any) {
      const loc = e?.hash?.loc;          // 1-based first_line, 0-based first_column — trust loc over e.hash.line
      return { ok: false, error: { message: String(e?.message ?? e),
        line: loc?.first_line, col: loc?.first_column, expected: e?.hash?.expected } };
    }
    return { ok: false, error: { message: 'Invalid mermaid text' } };
  }
  const diagram = await mermaid.mermaidAPI.getDiagramFromText(text);
  return { ok: true, diagramType: diagram.type, config: res.config ?? {}, db: diagram.db };
}
```

For **unit tests in Node**, the verified jsdom shim (must run before a *dynamic* import of
mermaid — a static import gets hoisted above it and fails):

```ts
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', { url: 'https://localhost/' });
globalThis.window = dom.window as any;
globalThis.document = dom.window.document;   // do NOT assign globalThis.navigator (getter-only)
const mermaid = (await import('mermaid')).default;
```

Without this, any diagram containing a labeled node throws
`DOMPurify.addHook is not a function` (dompurify captures `globalThis.window` at module-eval
time; `securityLevel:'loose'` is NOT an escape hatch — verified).

### 9.2 Ground-truth tables (embed as `src/shared/mermaid/tables.ts`)

**FlowDB access (flowchart-v2).** `db.getVertices()` returns a **`Map`** (not an object!) of
`{ id, text, labelType: 'text'|'string'|'markdown', type?, styles: string[], classes: string[],
link?, props }` — label property is **`text`**, shape is **`type`** and is **absent** for bare
nodes. `db.getEdges()` returns an **Array** of `{ start, end, type, stroke, length, text,
labelType, id, isUserDefinedId }`. `db.getSubGraphs()` → `[{ id, nodes: string[], title,
dir?, labelType }]` (nested subgraphs: inner id appears in outer's `nodes`). `db.getDirection()`
→ `'TB'|'BT'|'LR'|'RL'` (`TD` normalizes to `TB`). `db.getClasses()` → Map of classDefs.
`db.getTooltip(id)` for tooltips.

**Arrow mapping — two orthogonal lookups (import) plus a closed emit table (export).**
Every entry below was parse-verified against 11.17.0 (`docs/research/mermaid-lab/out-20.txt`,
`out-23.txt`). The db's `type` and `stroke` vary independently, so the **import** mapping is two
composable lookups (never a single syntax table — real inputs like `-.-o` combine them):

```ts
// db edge.type → (arrowStart, arrowEnd)
arrow_point:(none,arrow)  arrow_open:(none,none)  arrow_circle:(none,circle)
arrow_cross:(none,cross)  double_arrow_point:(arrow,arrow)
double_arrow_circle:(circle,circle)  double_arrow_cross:(cross,cross)
// db edge.stroke → (line, hidden)
normal:(solid,–)  dotted:(dashed,–)  thick:(thick,–)  invisible:(solid, hidden:true)
// db edge.length L > 1 → meta.mermaid.minlen = L
```

**Export emit table** — keyed by `(line, arrowStart, arrowEnd)`; these 22 syntaxes are the ONLY
arrow bodies the exporter may emit (each one parse-verified; anything else, e.g. a bare `A -- B`
or `A == B`, is a **hard parse error**):

| line \ heads | (none,none) | (none,arrow) | (none,circle) | (none,cross) | (arrow,arrow) | (circle,circle) | (cross,cross) |
|---|---|---|---|---|---|---|---|
| solid | `---` | `-->` | `--o` | `--x` | `<-->` | `o--o` | `x--x` |
| dashed | `-.-` | `-.->` | `-.-o` | `-.-x` | `<-.->` | `o-.-o` | `x-.-x` |
| thick | `===` | `==>` | `==o` | `==x` | `<==>` | `o==o` | `x==x` |

plus `~~~` for `hidden:true` (whatever the heads — hidden edges carry no arrowheads in mermaid).

**Degrade rule** for head pairs outside this table (asymmetric pairs with `arrowStart ≠ 'none'`
and `arrowStart ≠ arrowEnd`, e.g. circle→arrow): emit `(none, arrowEnd)` — keep the target head,
drop the source head. This rule is also the canonicalization used by the round-trip tests
(§15.1).

**minlen extension**: repeat the line's *middle* character — solid `-`, dashed `.`, thick `=`,
hidden `~` — an extra `(minlen − 1)` times; no extension when minlen is absent or 1. Verified
examples for minlen 2: `--->`, `----`, `-..->`, `-..-`, `===>`, `====`, `~~~~` (all parse with
`length: 2`). Never insert extra dashes into dashed/thick/hidden bodies — `-.-->`, `==->` etc.
are parse errors.

Edge labels from `-->|lbl|` or `--lbl-->` land in `edge.text` identically; the exporter always
uses the `|lbl|` form. User edge ids: `A e1@--> B` (the `id@` sits between source and arrow;
verified to compose with every line style). Auto edge ids look like `L_A_B_0` — synthetic; never
persist them as `meta.mermaid.id`.

**Entity placeholders (critical gotcha).** `#quot;` etc. surface in db `text` as internal
placeholders. Decode on import (verbatim from mermaid's own `decodeEntities`):

```ts
export const decodeMermaidLabel = (t: string) => htmlEntityDecodeOnce(
    t.replace(/ﬂ°°/g, '&#').replace(/ﬂ°/g, '&').replace(/¶ß/g, ';'))
  .replace(/<br\s*\/?>/gi, '\n');
// 1. placeholder decode (mermaid's own inverse), 2. EXACTLY ONE HTML-entity-decode pass
//    (&quot; &#9829; &amp; &lt; → characters — a recursive decoder would re-break '&amp;lt;'),
// 3. <br>/<br/> → '\n' (mermaid normalizes <br/> to <br>; without this step multi-line labels
//    round-trip as the literal text 'line1<br>line2').
```

Skipping the placeholder decode **silently corrupts every label containing quotes**; skipping the
`<br>` step corrupts every multi-line label — both are covered by mandatory corpus tests.

**Export escaping (verified).** A raw `"` in a label is a hard parse error and backslash escapes
don't exist. Serializer label rule — **replacement order matters**:

```ts
export const encodeLabel = (s: string) =>
  '"' + s.replace(/#/g, '#35;')      // 1. first, so later entities' own '#' isn't re-escaped
         .replace(/&/g, '#38;')      // 2. '&' MUST be escaped: import entity-decodes once, so a
                                     //    literal 'AT&T' or '5 &lt; 6' would otherwise corrupt
         .replace(/"/g, '#quot;')    // 3. the only quote mechanism (\" is a parse error)
         .replace(/\n/g, '<br>')     // 4. newlines
  + '"';
// ALWAYS wrap in quotes (unquoted parens etc. are parse errors)
// Verified round-trip example (out-24.txt): '5 &lt; 6' → emit '5 #38;lt; 6' → db raw
// '5 ﬂ°°38¶ßlt; 6' → placeholder-decode '5 &#38;lt; 6' → one entity pass → '5 &lt; 6' ✓
```

**Mermaid-safe ids.** Generate exporter ids matching `[A-Za-z_][A-Za-z0-9_]*`, excluding this
**case-sensitive blocklist** (each verified to be a parse error as a node id, `out-24.txt`):
`end, style, class, classDef, click, subgraph, graph, flowchart, linkStyle` — on collision (or a
blocklisted derivation) append `_`. Capitalized forms (`End`, `Style`, …) and `direction`,
`default`, `o`, `x` are safe as ids, but avoid emitting ids whose leading `o`/`x` could fuse
with an adjacent arrow body (`A ---oK` parses as a circle-arrow to `K`).

**Sequence LINETYPE table** (needed for island tooltips now, native sequence later — embed the
FULL table; the abbreviated one in `mermaid-api.md` is missing 26–34):
`SOLID:0 DOTTED:1 NOTE:2 SOLID_CROSS:3 DOTTED_CROSS:4 SOLID_OPEN:5 DOTTED_OPEN:6 LOOP_START:10
LOOP_END:11 ALT_START:12 ALT_ELSE:13 ALT_END:14 OPT_START:15 OPT_END:16 ACTIVE_START:17
ACTIVE_END:18 PAR_START:19 PAR_AND:20 PAR_END:21 RECT_START:22 RECT_END:23 SOLID_POINT:24
DOTTED_POINT:25 AUTONUMBER:26 CRITICAL_START:27 CRITICAL_OPTION:28 CRITICAL_END:29 BREAK_START:30
BREAK_END:31 PAR_OVER_START:32 BIDIRECTIONAL_SOLID:33 BIDIRECTIONAL_DOTTED:34`;
`PLACEMENT: LEFTOF:0 RIGHTOF:1 OVER:2`.

### 9.3 Import pipeline (`importMermaid`)

```
importMermaid(text) →
  { kind: 'flowchart', nodes: ThalyxNode[], edges: ThalyxEdge[], meta } |
  { kind: 'island', diagramType } |
  { kind: 'error', error }
```

1. Strip + preserve frontmatter: if text starts with `---\n…\n---\n`, keep the raw block for
   `doc.meta.mermaid.frontmatter` (the parse still receives the full text — mermaid handles
   frontmatter itself; we only *remember* it).
2. `parseMermaid(text)`. Invalid → `error` (show message + line/col in UI).
3. `diagramType === 'flowchart-v2' || diagramType === 'flowchart-elk'` (both use FlowDB; `graph`
   and `flowchart` sources both report `flowchart-v2`, a `flowchart-elk` header reports
   `flowchart-elk` — verified `out-25.txt`) → **native import**:
   - Vertices → `ThalyxNode` (`kind:'shape'`): shape via §7.3 table; label =
     `decodeMermaidLabel(vertex.text)`; `meta.mermaid = { id, shape?, classes, styles, link,
     tooltip: db.getTooltip(id), labelType }`. Map recognizable `styles` entries (`fill:`,
     `stroke:`, `stroke-width:`) into `NodeStyle`; keep the raw strings too.
   - Subgraphs → `ThalyxNode` (`kind:'container'`, label = title, `meta.mermaid.id = sg.id`,
     `meta.mermaid.dir = sg.dir` when present); membership (`sg.nodes[]`, which may contain
     inner subgraph ids) → `parentId`. Two verified gotchas (`out-22.txt`): `getSubGraphs()`
     lists **inner subgraphs before outer ones** — topologically sort containers parent-first
     before appending to `nodes[]` (invariant 3) — and subgraph ids do **not** appear in
     `getVertices()`.
   - Edges → `ThalyxEdge` via the two §9.2 import lookups (type→heads, stroke→line/hidden);
     label = `decodeMermaidLabel(edge.text)`; `kind:'elbow'`.
   - **Initial node sizing** (before layout): `width = clamp(96, 8 + 9·longestLine, 320)`,
     `height = 40 + 20·(lines-1)`; diamonds ×1.4 both axes; circles square. (Exact text
     measurement happens on first render; these seeds only feed dagre.)
   - Auto-layout via dagre (§11.5) with `rankdir` = `db.getDirection()`.
   - `doc.meta.mermaid = { direction, frontmatter?, classDefs: fromEntries(db.getClasses()… styles), sourceText: text }`.
4. Any other diagram type → **island**: one `ThalyxNode { kind:'mermaid', mermaidSource: text }`
   sized from its rendered SVG (§9.8).
5. The caller (`importMermaidAsNew` action) inserts the result in **one history entry**, selects
   it, and zooms to fit.

### 9.4 Export pipeline (`exportMermaid`)

Hand-rolled serializer (~200 LOC — no npm package exists for this; verified). Only flowcharts in
MVP. **Purity contract**: `exportMermaid(doc, opts?: {selection?}) → { text: string;
idAssignments: Record<NodeId, string> }` is a pure function — it computes any missing mermaid ids
but does NOT mutate the doc. Callers apply `idAssignments` via the untracked `ensureMermaidIds`
action (§8.3) — after one application the assignments are empty on every subsequent export
(fixpoint; this is what makes M6's "byte-stable export" acceptance checkable and cannot loop the
live panel).

Island handling: a doc whose only content is one island exports as that island's verbatim
`mermaidSource`; a single selected island likewise. A **mixed** doc (flowchart content +
islands) exports the flowchart serialization only, and the caller surfaces "N mermaid island(s)
not included" (the Mermaid panel shows this as a notice line; Copy as Mermaid shows a toast).

Algorithm:

1. **Compute mermaid ids.** For each non-island node: use `meta.mermaid.id` if present, else
   derive from the label (`[A-Za-z_][A-Za-z0-9_]*`, CamelCase words, §9.2 blocklist respected,
   collision-suffixed `_2`), else `n1, n2…`. Derived ids go into the returned `idAssignments`
   so callers persist them (untracked) and reconcile (§9.6) can match on them later.
2. Emit frontmatter verbatim if stored. Then `flowchart ${doc.meta.mermaid.direction ?? 'TB'}`.
3. Node lines in z-order: `  ${id}${brackets(shape, encodeLabel(label))}` where `brackets`
   inverts the §7.3 table (if `meta.mermaid.shape` holds an unmapped original like `cyl`, emit
   `${id}@{ shape: cyl, label: ${encodeLabel(label)} }`). A node may skip its standalone
   declaration line **only if** its label equals its id, its shape is `rect`, **and** it appears
   in at least one emitted edge line — an edge-less node always gets a standalone line or it
   vanishes from the export.
4. Container blocks: `subgraph ${id}[${encodeLabel(title)}]` … `end`, members = children,
   nested containers nested. When the container carries `meta.mermaid.dir`, emit
   `direction ${dir}` as the first line inside the block (round-trips; verified `out-25.txt`).
5. Edge lines: use the **§9.2 emit table exactly** — the 22 verified `(line, heads)` bodies,
   the degrade rule for asymmetric head pairs, `~~~` for hidden, and the middle-character
   `(minlen − 1)` extension rule. Label: `|${encodeLabel(label)}|` right after the arrow. User
   edge id: `${meta.mermaid.id}@` prefix between source id and arrow. Keep node declarations
   separate from edge lines (simpler, still idiomatic).
6. Style tail: `classDef` lines from `doc.meta.mermaid.classDefs`; `class ${id} ${cls}` from node
   meta; `style ${id} …` for nodes with unmapped raw styles; `click ${id} href "…" "tooltip"`.
7. **Known losses (by design, do not "fix"):** `%%` comments, whitespace, statement order/sugar,
   `TD` vs `TB` spelling, `graph` vs `flowchart` keyword, auto edge ids, asymmetric arrowhead
   pairs (degrade rule). Round-trip is **semantic modulo the degrade canonicalization**, not
   textual (§15.1 defines the fixpoint test).

### 9.5 Mermaid panel (UX)

Right-side collapsible panel (`Mod+Shift+M` toggles — plain `Mod+M` belongs to the native
Window→Minimize menu role):

- **Live view**: regenerated `exportMermaid(doc)` text (read-only styling, monospace,
  select/copy enabled), updated debounced 300 ms after doc changes. Non-empty `idAssignments`
  are applied via the untracked `ensureMermaidIds` (§8.3) — never a history entry. Docs
  containing islands show the "N mermaid island(s) not included" notice line (§9.4); a
  single-island doc shows the island's source itself.
- **Edit mode**: user edits the text freely; parse errors show inline (message + line from
  §9.1); an **Apply** button (and `Mod+Enter`) runs `applyMermaidText` → reconcile (§9.6).
  A **Revert** button returns to live view. Leaving edit mode with unapplied changes asks once
  (this is the one permitted confirm dialog — text edits are real work).
- Panel header: diagram direction dropdown (TB/LR/BT/RL — re-runs auto-layout on change **only**
  if the user confirms via the same button that triggers it, it's an action not a mode).

### 9.6 Reconcile (`reconcileDocument`) — position-preserving re-import

`applyMermaidText(text)`: run `importMermaid(text)`; on flowchart result, **merge instead of
replace**, in one history entry:

1. Match imported nodes to existing nodes by `meta.mermaid.id` (the panel's live view has
   already applied `ensureMermaidIds`, so every existing exportable node has one). Matched: keep
   `x/y/width/height/style` (unless the imported text carries explicit `style`/class info that
   changed), update `label`, `shape`, `link`, `tooltip`, `parentId` — and when `parentId`
   changes, apply invariant §7.2.7: convert coordinates so the node's **absolute** position is
   unchanged (positions are parent-relative; keeping raw x/y across a parent change would
   teleport the node).
2. Unmatched imported nodes are **new**: position at the barycenter of their already-placed graph
   neighbors offset one `GRID_GAP` (48 px) in the document's flow direction; no placed neighbor →
   below the current content bounding box. Nudge ±16 px until not overlapping any node.
3. Existing nodes with a `meta.mermaid.id` absent from the import are **deleted** (with edges).
   Nodes *without* any mermaid id (hand-drawn, never exported — impossible after step 9.4.1, but
   normalize defensively) are kept untouched.
4. Edges: match by `(sourceMermaidId, targetMermaidId, occurrenceIndex)`; update
   label/arrows/line; add new; drop missing. Manual `waypoints` survive only on matched edges
   whose endpoints didn't move.
5. Update `doc.meta.mermaid.sourceText/frontmatter/classDefs/direction`.

Island documents: `applyMermaidText` on an island node simply replaces its `mermaidSource`
(re-render, resize if needed) — one history entry.

### 9.7 Paste & file detection

- `isProbablyMermaid(text)`: after skipping an optional frontmatter block AND any leading
  comment/directive lines matching `/^\s*%%/` (mermaid allows `%%` comments and `%%{init:…}%%`
  directives before the header), the next non-blank line starts with one of the known diagram
  keywords (`flowchart`, `graph`, `sequenceDiagram`, `classDiagram`,
  `stateDiagram`, `stateDiagram-v2`, `erDiagram`, `gantt`, `pie`, `mindmap`, `timeline`,
  `gitGraph`, `journey`, `quadrantChart`, `sankey`, `xychart`, `block`, `kanban`,
  `architecture`, `packet`, `radar`, `treemap`, `c4`, …). Cheap prefilter only — final arbiter
  is `mermaid.parse`.
- On paste of matching text onto the canvas: import at the cursor (native or island) and show a
  toast: “Imported Mermaid — ⌘Z to undo · Paste as text instead”. The toast's second button
  undoes and inserts a text node. No blocking dialog.
- `.mmd`/`.mermaid` files open via dialog/drag-drop/association: import into a fresh untitled doc
  (auto-layout). Saving that doc offers `.thalyx` (full fidelity) with “Export .mmd” separate.

### 9.8 Mermaid islands

`MermaidIslandNode.tsx`: renders `mermaidSource` via
`await mermaid.render('island-'+id, source)` → sanitize the returned SVG string with DOMPurify
(profile: SVG) → inject; natural size from the SVG's `viewBox` (scaled to fit node bounds,
preserve aspect). Double-click opens a modal editor (textarea + live preview + parse errors +
Apply). Islands resize proportionally, get no connection handles, and re-render on theme change
(mermaid `theme: 'neutral'` vs `'dark'`).

---

## 10. Interaction & UX specification

The full research catalog is `docs/research/ux.md`; its 18-interaction spec **I1–I18 is adopted
verbatim as the MVP UX contract**, with the deltas below. During M2–M5, implement interactions in
the order given by the milestone tables (§17), and treat I1–I18's thresholds as defaults:
snap threshold **6 screen px**, grow-gesture gap **48 px**, grid **8 px**, duplicate offset
**+16,+16 px**, chevron suppression below **40% zoom**. (These are our chosen values — vendors
don't publish theirs.)

Deltas / clarifications vs the research spec:

1. (I5) Grow gesture is `Mod+Arrow`; **disabled while `session.editingLabel` is set** so macOS
   text-caret navigation is untouched. Tab during the gesture cycles rect → diamond → ellipse.
   New node inherits the source node's style and size; connecting edge inherits the last-used
   edge style.
2. (I13) Tidy Up = **`Alt+Shift+T`** (D15). Auto-layout = **`Alt+Shift+L`**, and both live as
   buttons in the context panel when ≥2 nodes are selected.
3. (I16) Group = wrap in container (D5). Rubber-band = touch-select. Rotation: none (D7).
4. (I3) No minimap ever (D8).
5. (I17) Theme: `system` default; explicit toggle cycles light/dark. Canvas colors are palette
   tokens remapped per theme; exports always render on an explicit background (default light) —
   never "whatever theme the window is in".
6. (I18) Autosave: once a doc has a path, debounced (800 ms) atomic save in place;
   untitled docs autosave to the recovery dir; `.bak` created before the first in-place save of
   a session (§12.4).
7. (I4) The container ("frame") tool `F`/`8` is new (not in I1–I18), and `H` (hand) loses its
   digit alias to make room. Shape keys R/O/D select the single `shape` tool with the matching
   `pendingShape` (§8.1); rounded-rect and cylinder are toolbar-only (no letter keys).
8. (I2) Right-button drag also pans (in addition to space-drag and middle-drag) — React Flow's
   `panOnDrag={[1, 2]}` provides it for free and draw.io/Lucidchart users expect it.

### 10.2 Keymap (authoritative table)

`Mod` = `Cmd` on macOS, `Ctrl` on Linux. Implementation: one `useKeymap` hook. **Matching
rules** (getting these wrong silently kills shortcuts):

- Plain single-letter bindings (tools, H, Q…) match on `e.key.toLowerCase()` (layout-aware).
- **Any chord containing `Alt`, and any `Shift`+digit or `Shift`+punctuation chord, matches on
  `e.code`** (`KeyT`, `KeyL`, `KeyD`, `Digit1`, `Digit2`, `Slash`…). On macOS, Option composes
  characters (`Alt+Shift+T` → `e.key === 'ˇ'`), and `Shift+1` → `e.key === '!'` everywhere —
  `e.key` never matches those chords.
- All bindings are ignored while `e.isComposing` or while an input/textarea/contentEditable has
  focus (except Esc / Mod+Enter where specified).
- **Type-to-edit precedence**: when exactly one *node* is selected, printable keys without
  `Mod`/`Alt` (including `Shift`+letter for capitals) start label editing with that character —
  this **suppresses the single-key tool/toggle bindings** in that state. `Shift`+digit (zoom)
  and `Shift+/` (help) still win because they match on `e.code` before the type-to-edit branch.
  Tool keys work whenever the selection is empty, multiple, or an edge — or after Esc.

Menu accelerators are declared only for items that exist in the app menu (§12.3) and both paths
dispatch the same store action.

| Binding | Action |
|---|---|
| `V`/`1` | Select tool |
| `R`/`2` | Shape tool, pendingShape `rect` (toolbar also offers `rounded` and `cylinder`, no letter keys) |
| `O`/`3` | Shape tool, pendingShape `ellipse` |
| `D`/`4` | Shape tool, pendingShape `diamond` |
| `A`/`5` | Arrow (connector) tool |
| `L`/`6` | Line (no-arrowheads connector) tool |
| `T`/`7` | Text tool |
| `F`/`8` | Container ("frame") tool |
| `H` | Hand tool; `Space` (held) temporary hand |
| double-press tool key or `Alt`+click tool | lock tool active |
| `Q` | Toggle quick-connect chevrons |
| `Mod+Arrow` | Grow: create connected node in direction (I5); `Tab` cycles its shape |
| `Enter` | Edit label of selected node/edge; `Esc` commit + deselect |
| *(printable char with single node selected)* | Start label editing with that char |
| `Mod+D` / `Alt`+drag | Duplicate |
| `Delete`/`Backspace` | Delete selection (+ dependent edges) |
| `Mod+A` | Select all |
| `Mod+G` / `Mod+Shift+G` | Group into container / dissolve container |
| `Mod+[` `Mod+]` `Mod+Shift+[` `Mod+Shift+]` | Z-order: back one / forward one / to back / to front |
| `Arrow` / `Shift+Arrow` | Nudge 1 px / 8 px |
| `Mod+Z` / `Mod+Shift+Z` / `Mod+Y` | Undo / Redo / Redo |
| `Mod+scroll` / pinch | Zoom at cursor; `Mod+=` `Mod+-` step; `Mod+0` 100% |
| `Shift+1` / `Shift+2` | Zoom to fit / zoom to selection |
| `Shift+Alt+D` | Toggle theme |
| `Shift+/` | Help overlay (searchable shortcut sheet) |
| `Alt+Shift+T` | Tidy Up selection |
| `Alt+Shift+L` | Auto-layout selection (or all, if nothing selected) |
| `Mod+Shift+M` | Toggle Mermaid panel; inside panel edit mode: `Mod+Enter` = Apply |
| `Mod+Shift+C` | Copy selection as Mermaid |
| `Mod+N` `Mod+O` `Mod+S` `Mod+Shift+S` | New / Open / Save / Save As (menu) |
| `Mod+Shift+E` | Export dialog (SVG/PNG/PDF/MMD) |
| `Mod+C/X/V` | Copy/cut/paste (internal JSON flavor + PNG; §13.3) |

Known-conflict audit (why these bindings): `Ctrl+Alt+T` avoided (GNOME terminal);
`Cmd+Arrow` gated during text edit (macOS caret); `Shift+Alt+D`/`Alt+Shift+L/T` have no default
GNOME/macOS bindings (and match on `e.code`, so macOS Option-composition doesn't break them);
`Mod+M` avoided — the app's own Window→Minimize menu role owns `CommandOrControl+M` and menu
accelerators fire before renderer keydown, hence `Mod+Shift+M` for the panel; `Mod+Shift+C`
collides only with DevTools-inspect in dev builds (acceptable); single-key tools follow
Excalidraw muscle memory, with the type-to-edit precedence rule above resolving the
tool-key-vs-typing clash.

### 10.3 Context panel

One floating panel, left-docked (Excalidraw placement), showing only:

- **Node(s) selected**: fill (palette row), stroke (auto-derived + override row), stroke width
  (3 segmented), corner sharp/round (shown only for `rect`/`rounded` — it swaps the ShapeKind,
  see §7.1 note), font size (4 segmented), shape swap (popup with the full §7.3 set), link
  (URL field → `meta.mermaid.link`), lock toggle. Mixed selection: show shared controls only.
- **Edge(s) selected**: line style (solid/dashed/thick), kind (elbow/straight/curved), arrowheads
  per end (none/arrow/circle/cross), label field.
- **Container selected**: label, fill (subtle tints), lock.
- **Nothing selected**: canvas background, grid toggle, theme, direction (TB/LR/BT/RL — the
  same four options as the Mermaid panel's dropdown; both call `setDirection`), Mermaid panel
  toggle.
- **≥2 nodes**: alignment row (left/center-h/right/top/center-v/bottom), Tidy Up, Auto-layout.

Segmented controls for ≤5 options — no dropdowns. Max ~8 visible controls; nothing nests.

### 10.4 Palette & theming

12 curated fill colors (token names, not hex, in the model): `surface` (theme background),
`gray`, `blue`, `cyan`, `teal`, `green`, `yellow`, `orange`, `red`, `pink`, `violet`, plus
`transparent`. Each token maps to a light-theme and dark-theme pair (fill + auto stroke + text
color) defined once in `src/renderer/theme/palette.ts` as CSS variables. Derive values from the
Open Color palette *values* (MIT — verify its license file at M0 and add a ledger entry) or pick
equivalents; validate every pair for ≥4.5:1 label contrast in **both** themes (unit test with a
contrast function). Custom hex from the escape-hatch picker renders identically in both themes.

New shapes inherit the last-applied style (Whimsical persistence); defaults: `surface` fill,
theme-ink stroke, medium width, font M; the default `pendingShape` is `rounded` (soft-cornered
rectangles read friendlier; `R` explicitly selects sharp `rect`).

---

## 11. Canvas subsystems

### 11.1 React Flow integration

- `<ReactFlow>` props: controlled `nodes`/`edges`; `nodeTypes={{shape, text, container, mermaid}}`;
  `edgeTypes={{thalyx}}`; **no `snapToGrid` prop, ever** — React Flow's built-in grid snap
  quantizes positions before `onNodeDrag` fires and would fight the custom snap engine;
  `snap.ts` (§11.4) is the single snapping authority, including the 8 px lattice;
  `selectionOnDrag`; `panOnDrag={[1,2]}` (middle- and right-button drag pan, per §10.1 delta 8);
  `zoomOnPinch`; `onlyRenderVisibleElements` **enabled from M2**; `minZoom=0.1` `maxZoom=4`;
  `proOptions={{hideAttribution: false}}` (keep attribution; it's honest).
- Node components are `React.memo`'d and read only their own `data`; edges likewise. No
  whole-store subscriptions inside node/edge components (perf doctrine from React Flow docs).
- Containers use RF `parentId`; dragging a node across a container boundary re-parents on drop
  while preserving its absolute position.

### 11.2 Floating attachment (anchors)

`anchors.ts`: `edgeEndpoints(sourceNode, targetNode, sourceAnchor, targetAnchor)` — for `auto`,
endpoint = intersection of the source→target center segment with the node's shape boundary
(rect/ellipse/diamond analytic; other shapes use their bounding rect — visually fine). For pinned
sides (M9), the side midpoint. React Flow `Handle`s exist on all four sides (`id='n'|'s'|'e'|'w'`)
and handle drags store those cardinal sides so connections remain pinned to their magnets.
Recompute every render — geometry is derived (D12).

### 11.3 Elbow router (MVP)

`elbow.ts` — pure function, the FigJam-quality heuristic (not obstacle-avoiding; that's M9):

```
route(sourceRect, targetRect, sourceSide?, targetSide?):
  1. pick sourceSide = side of source facing target center (unless pinned); same for target
  2. stub out 16 px perpendicular from each side
  3. connect stubs with axis-aligned segments via the midline between the rects. Side-case
     point counts (polyline points incl. endpoints): orthogonal sides → 3-point L;
     opposite sides → 4-point Z; same side → 4-point U (via a rail 16 px beyond the outermost
     bound — two stubs pointing the same direction can never close in 3 points);
     non-facing/blocked variants add up to two more points (5–6-point S/C shapes)
  4. return polyline points; renderer draws with optional 6 px corner rounding
```

`ThalyxEdge.tsx` renders elbow (from `waypoints` if present, else `route()`), straight
(`getStraightPath`), curved (`getBezierPath`) — the latter two from React Flow's exported
helpers. Label chip at `labelT` along the polyline, canvas-background fill, draggable
(updates `labelT`, gesture-coalesced). Hidden edges render nothing (but hit-test in the Mermaid
panel's world only).

Manual adjustment: dragging an elbow segment perpendicular to itself sets `waypoints` (gesture);
moving/resizing either endpoint node clears them (D12).

### 11.4 Smart guides & snapping

`snap.ts` — pure: `computeSnap(draggedBounds, staticBounds[], zoom, opts)` returns
`{ dx, dy, guides: GuideLine[] }`, where (this type lives in `snap.ts` and is what
`session.guides` holds):

```ts
export interface GuideLine {
  kind: 'align' | 'gap';
  axis: 'x' | 'y';          // the axis the guide constrains
  position: number;          // canvas coord of the guide line (align) / gap midline (gap)
  start: number; end: number; // extent along the other axis, spanning the aligned bounds
  label?: string;            // gap chips: the px value, e.g. '24'
}
```

- Candidates: edges + centers (x: L/C/R, y: T/C/B) of nodes in the viewport (cap at nearest 40
  by distance for perf).
- Threshold 6/zoom px; nearest candidate wins per axis; produce guide lines spanning the two
  aligned bounds.
- Equal spacing: for each axis, find pairs of aligned neighbors with gap `g`; if the dragged
  box's gap to a neighbor is within threshold of `g`, snap and emit two gap chips (`GuideLine`
  with `kind:'gap'`, labeled with px value).
- Grid on → also snap to 8 px lattice; smart guides win over grid.
- `Mod` held during drag disables all snapping.
- Wire-up: RF `onNodeDrag` applies snapped positions transiently and writes `session.guides`;
  drag-end commits and clears. Resize snapping (same-size candidates) reuses the same module.

### 11.5 Layout actions

- `dagreLayout.ts`: build
  `new dagre.graphlib.Graph({ compound: true, multigraph: true })` — **`compound: true` is
  mandatory or `setParent` throws** — then `g.setDefaultEdgeLabel(() => ({}))` (dagre throws on
  label-less edges otherwise), `setGraph({ rankdir, nodesep: 40, ranksep: 60, marginx: 24,
  marginy: 24 })`, nodes with real (rendered) sizes, edges as
  `g.setEdge(src, tgt, { minlen: edge.meta?.mermaid?.minlen ?? 1 }, edge.id)`; containers via
  clusters (`g.setParent(child, container)`). **Edges whose source or target is a container are
  NOT added to the dagre graph** (dagre cannot route cluster edges — a documented limitation
  mermaid itself works around); they are simply drawn by our own router after layout using the
  container's laid-out bounds. Output centers → convert to top-left. Ignore dagre's edge points
  (our router draws edges). Direction from `doc.meta.mermaid.direction` unless the action
  passes one. Unit test: a containered corpus doc runs through `autoLayout` without throwing
  and children stay inside their containers.
- Scope: selection's connected subgraph, or whole doc if no selection. One history entry;
  animated 150 ms position transition (CSS) — respect `prefers-reduced-motion`.
- `tidy.ts`: unconnected-shape selection → infer row/column/grid from current arrangement
  (cluster y's → rows), distribute evenly with 24 px gaps, align to the dominant axis.

### 11.6 Quick-connect chevrons & grow gesture

`QuickConnectChevrons.tsx` (RF `ViewportPortal` overlay on the hovered node, select tool only,
zoom ≥ 40%, `Q` toggleable, hidden while dragging/editing):

- 4 chevrons 12 px outside N/S/E/W edges.
- **Click**: same as `Mod+Arrow` in that direction — if a node already exists within a 48px-gap
  corridor in that direction, connect to it instead of creating (draw.io rule).
- **Drag**: rubber-band a connector; drop on a node → attach; drop on empty canvas → small shape
  popup (recent shapes first, the 5 toolbar shapes) → create + attach there, open its label
  editor.
- `useGrowGesture` implements the shared "create connected node" primitive both paths call:
  new node = source style/size, position = source bounds + gap 48 px in direction (snapped to
  grid when on), edge = last-used edge style, select + open label editor. All one history entry.

### 11.7 Performance budget & spike (M2 gate)

Fixture generator: `tests/perf/genDoc.ts` produces 500/1000/2000-node docs (mixed shapes, 1.5×
edges, 10% containers). **Acceptance at M2**: on a dev-class machine, 1000-node doc pans/zooms at
≥50 fps and node drag latency <32 ms with `onlyRenderVisibleElements` + memoized components
(measure with Chrome tracing in the packaged app on both OSes). 2000-node doc must stay usable
(≥25 fps pan). If 1000-node fails after applying React Flow's documented perf checklist:
introduce zoom-based LOD (below 50% zoom render nodes as plain rects, hide labels below 30%).
**Escape hatch trigger** (documented, not built): sustained <30 fps at 1000 nodes after LOD →
plan a Konva-based renderer swap (the doc model and `shapePath` are renderer-agnostic by
design; this is why nothing may import React Flow types into `src/shared/`).

---

## 12. Desktop shell (Electron)

### 12.1 Windows & lifecycle

- Single `BrowserWindow`, one document at a time (multi-window is M9). `contextIsolation: true`,
  `sandbox: true`, `nodeIntegration: false`, `webSecurity: true`.
- Single-instance lock (`app.requestSingleInstanceLock`); `second-instance` argv and macOS
  `open-file` events route to `openPath()` (replace current doc after autosave flush).
- Window state (bounds, maximized) persisted in prefs (§12.5), restored on launch (validate
  on-screen).
- Close flow: flush pending autosave → clear recovery entry if clean → close. Untitled-with-
  content docs keep their recovery entry and are restored on next launch ("scratch doc" model) —
  no dialog.
- macOS: `window.setDocumentEdited(dirty)` + represented filename.

### 12.2 IPC surface (complete list — add nothing without updating §14)

`preload/index.ts` exposes exactly this via `contextBridge.exposeInMainWorld('thalyx', …)`; all
handlers validate inputs with zod and enforce the path policy (§14):

```
dialog:  openFile(filters) → path|null · saveFile(defaultName, filters) → path|null
file:    read(path) → string · writeAtomic(path, contents) → void · backup(path) → void ·
         pathForDropped(file: File) → string   // preload-only: wraps Electron webUtils.getPathForFile
                                               // (File.path was REMOVED in Electron 32 — do not use it);
                                               // the returned path still goes through main's grant check
recovery: write(docId, contents) · list() → RecoveryEntry[] · read(docId) → string · clear(docId)
recents: list() → {path, name}[] · add(path) · clear()
prefs:   get(key) → json · set(key, json)
shellx:  openExternal(url)                      // scheme-validated in main
clip:    writePng(bytes: Uint8Array)            // native clipboard fallback
appx:    version() → string · onMenu(cb(actionId)) · onOpenFile(cb(path)) ·
         setDocumentEdited(bool) · setTitle(string)
export:  print() → void                         // menu Print… only: webContents.print() native dialog
updater: check() · onUpdateReady(cb) · quitAndInstall()
```

`platform/api.ts` wraps this with a browser fallback (in-memory/localStorage + download-anchor
exports) so the renderer runs in plain Chromium for Playwright and `vite dev` (§15.2).

### 12.3 Application menu

`Menu.buildFromTemplate`. **Role rule**: an Electron menu item with a `role` ignores its `click`
handler and dispatches native WebContents commands (which are no-ops when no editable element is
focused) — so **roles are used only for items with no canvas meaning**: the macOS app menu
(`about`, `quit`), Window (`minimize`, `zoom`, `close` — minimize keeps its native
`CommandOrControl+M`, which is why the Mermaid panel binding is `Mod+Shift+M`). The **Edit menu
items are role-less custom items** (Undo/Redo/Cut/Copy/Paste/Select All) with §10.2
accelerators whose `click` sends a `menu:action` event; the renderer routes each: if focus is in
an input/textarea/contentEditable, invoke the corresponding native editing behavior
(`webContents` editing methods via a tiny IPC, or simply let the accelerator-equivalent keydown
path handle it), otherwise dispatch the store action. Other menus: File (New/Open/Open
Recent/Save/Save As/Import Mermaid…/Export…/Print…), View (zoom actions, theme, Mermaid panel,
grid), Help (shortcut overlay, GitHub link, About with THIRD_PARTY_LICENSES viewer). Linux: same
template renders as an in-window menubar.

### 12.4 Saving, autosave, recovery (main-process rules)

- **Atomic writes always**: write `path + '.tmp'` in the same directory, `fsync`, `rename` over
  target (`fs.promises`); never truncate-then-write.
- `.bak` copy of the target before the first in-place save per session per file.
- Autosave (renderer-triggered, 800 ms debounce after doc changes): with a path → atomic save in
  place + `dirtySinceSave=false`; untitled → `recovery.write(docId, contents)`.
- Recovery dir `app.getPath('userData')/recovery/<docId>.thalyx` + `manifest.json`
  (`{docId, originalPath|null, savedAt}`). **docId rule** (deterministic across relaunches):
  for path-associated docs, `docId = sha256(absolutePath).slice(0, 16)` so a reopened file finds
  its old recovery entry; untitled docs get a session `nanoid()` persisted in the manifest (the
  scratch doc restores from the manifest, not from the path). Clean exit clears entries for
  saved docs. On launch with entries present: restore untitled scratch silently; for
  path-associated entries newer than the file, offer a toast "Recovered newer version —
  Restore / Discard".

### 12.5 Prefs & recents

Hand-rolled JSON at `userData/prefs.json` (atomic writes, zod-validated, normalize-on-load):
`{ theme, recents: [{path, name, lastOpened}] (max 10, existence-checked on read),
windowState, chevronsEnabled, lastExportDir, updateChannelOptIn }`.

### 12.6 File associations & updater

- electron-builder `fileAssociations`: `.thalyx` (Editor, own icon, MIME
  `application/vnd.thalyx+json` on Linux via mime.xml) and `.mmd`/`.mermaid` (Viewer/Editor
  role Alternate).
- electron-updater: GitHub Releases provider; check on launch (after 5 s) + manual "Check for
  Updates…"; download in background; "Restart to update" toast; never force. **Verify at M8**
  the current electron-updater Linux coverage (docs say AppImage/deb/rpm/pacman — confirm
  against the shipped version's release notes; AppImage is the guaranteed path). **macOS
  auto-update hard-requires code-signed builds** (Squirrel.Mac rejects updates for unsigned
  apps) — without the signing secrets, mac auto-update is inert and the release workflow prints
  a warning saying so. Flatpak (M9) disables in-app updates.
- Dev-mode granting: `process.env.THALYX_ALLOW_ANY_PATH=1` loosens the path policy for local
  dev only.

---

## 13. Export pipeline

### 13.1 One source of truth

`renderDocToSvg(doc, opts: { selectionOnly?, background: 'light'|'dark'|'transparent',
padding=16, islandSvgs?: Record<NodeId, string> })`
in `src/shared/export/svg.ts` — a **pure function from the model**, never DOM scraping. Emits
`<svg viewBox…>` with: background rect (unless transparent), containers (back), edges (elbow
polylines with markers — `<marker>` defs per arrowhead/color), nodes via `shapePath`, centered
`<text>` labels (line-broken to the node's stored width using a character-width estimate table
for Inter; label overflow clips), label chips. **Mermaid islands** cannot be rendered by pure
code (they need `mermaid.render` in the renderer), so the caller passes each island's cached,
DOMPurify-sanitized SVG string via `opts.islandSvgs`; `renderDocToSvg` embeds it as a nested
`<svg x y width height>` at the island's bounds, and draws a labeled placeholder rect for any
island missing from the map. Fonts: `font-family="Inter, system-ui, sans-serif"` (D19). All
styling inline attributes; no CSS classes; no `foreignObject`.

### 13.2 Formats

- **SVG**: serialize the string → save dialog.
- **PNG**: `Blob` the SVG string → `Image` → offscreen `<canvas>` at 1×/2× (dialog toggle) →
  `toBlob('image/png')`. (Same-origin blob: no tainting.) **Font caveat**: Chromium renders
  SVG-in-`<img>` in an isolated context that cannot see document `@font-face` fonts or load
  external resources — with D19's non-embedded SVG, labels would silently rasterize in a
  fallback font with wrong metrics. So **for the rasterization path only** (PNG export +
  clipboard PNG), inject the bundled Inter woff2 as a `data:` URI `@font-face` `<style>` into
  the SVG string before creating the blob, and draw only after `img.onload` fires (data-URI
  fonts inside an SVG image do resolve). The on-disk SVG export stays unembedded per D19.
- **PDF**: `new jsPDF({unit:'pt', format:[w,h]})`; register bundled Inter TTF
  (`addFileToVFS`/`addFont`); `await pdf.svg(svgElement, {…})` (svg2pdf). Known limitation
  (document in README): non-Latin glyphs fall back to jsPDF's built-ins — CJK PDF export is
  post-MVP; SVG/PNG cover it meanwhile.
- **Print…**: `webContents.print()` (native dialog). Never the PDF export path (D11).
- **Copy as Mermaid** (`Mod+Shift+C`): `exportMermaid(selection || doc)` → clipboard text.

### 13.3 Clipboard

- Internal copy: JSON flavor `{"type":"thalyx/clipboard","version":1,"nodes":[…],"edges":[…]}`
  written as `text/plain` alongside a rendered PNG (`ClipboardItem` with both). Paste priority:
  thalyx JSON → mermaid detection (§9.7) → plain text becomes a text node → image ignored (MVP).
- Copy-as-image: PNG via `navigator.clipboard.write([new ClipboardItem({'image/png': blob})])`
  (Chromium — works); fall back to `clip.writePng` IPC if it throws.
- Cross-copy fidelity: pasting inside Thalyx re-ids nodes/edges (fresh nanoids, +16px offset,
  preserving intra-selection edges only).

---

## 14. Security model

Untrusted inputs: `.thalyx` files, `.mmd` files, pasted text. The renderer is a full Chromium —
treat XSS there as RCE-adjacent even with sandbox on.

1. **Renderer lockdown**: `contextIsolation:true`, `sandbox:true`, `nodeIntegration:false`.
   CSP meta injected into `index.html` **by a Vite HTML transform, per build mode** — the strict
   policy would break `npm run dev` (Vite's React-refresh preamble and HMR WebSocket):
   - production: `default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';
     img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'` (no remote
     anything; updater runs in main);
   - dev only: additionally allow the plugin preamble (`'unsafe-inline'` in script-src) and
     `connect-src 'self' ws://localhost:*` for HMR.
   A unit/e2e assertion checks the **packaged** index.html carries the strict policy.
2. `will-navigate` → `preventDefault` always; `setWindowOpenHandler` → `deny` always.
   `webContents.on('render-process-gone')` → log + reload with recovery.
3. **Labels are text**: rendered via React text nodes only (invariant 7.2.4). The only
   `innerHTML`-adjacent sink in the app is island SVG injection, which passes through DOMPurify
   (SVG profile, `FORBID_TAGS: ['foreignObject']`) after mermaid's own `securityLevel:'strict'`.
4. **Links** (`meta.mermaid.link`): never navigated automatically; shown in the context panel;
   opened only by explicit click on an "open link" affordance → `shellx.openExternal`, main
   validates scheme ∈ {`https:`, `http:`, `mailto:`} and refuses everything else (`file:`,
   `javascript:`, smb, etc.).
5. **IPC path policy** (main): reads/writes only under (a) paths returned by this session's
   dialogs, (b) recents entries the user clicks, (c) argv/open-file/drag-drop paths — for
   drag-drop the renderer hands the dropped `File` object to the preload's `pathForDropped`
   bridge, which calls Electron's `webUtils.getPathForFile(file)` (the non-standard `File.path`
   property was **removed in Electron 32**; do not use it), and main re-validates the result:
   it's a file, size <50 MB, extension allowlisted — and (d) `userData`. Maintain the grant set
   in main; reject anything else. All IPC payloads zod-validated; oversize contents rejected
   (50 MB).
6. **Docs are data**: `restoreDocument` never `eval`s, never interprets strings as paths/URLs to
   fetch. zod bounds all sizes/lengths (labels ≤ 4 kB, ≤ 20 k nodes).
7. `npm audit` in CI (non-blocking report), Renovate weekly for Electron majors (§16).

---

## 15. Testing strategy

### 15.1 Unit (vitest, `tests/unit`) — the bulk

- **Model**: restore/normalize (garbage in → valid doc out; property: `restore(restore(x)) ==
  restore(x)`), invariants, zod schema.
- **History**: undo/redo semantics, gesture coalescing, limit, structural-sharing sanity.
- **Geometry**: anchors, elbow router (golden polylines for the side-case matrix), shapePath
  snapshots, snap engine (table-driven: candidates → expected dx/dy/guides).
- **Mermaid import**: the jsdom harness (§9.1) against `tests/corpus/*.mmd` — the corpus starts
  from the lab's verified samples and must include: every arrow variant (all 22 emit-table
  bodies plus minlen extensions); every shape bracket; labels with `#quot;`, `&`, entity-like
  text (`5 &lt; 6`), multi-line `<br>` labels, unicode, markdown backticks; nested subgraphs
  with `direction`;
  `classDef`/`class`/`style`/`linkStyle`/`click`/tooltips; `~~~`; `---->`; `e1@-->`;
  the `@{shape: cyl}` syntax; frontmatter; a 150-node generated chart. Each fixture asserts the
  exact imported model (JSON snapshot).
- **Mermaid export + round-trip (the crown jewel)**: for every corpus file:
  `M1 = import(text)` → `out = export(M1)` → `M2 = import(out)` → assert **semantic equality
  modulo canonicalization** and **fixpoint**: `export(M2) === out` (byte-equal from the second
  pass on). Semantic equality compares: same node set by mermaid id with same labels/shapes/
  links, same edge multiset with same line styles/labels and `canonicalizeHeads(edge)` equal,
  same containment including subgraph `dir`. `canonicalizeHeads` applies the §9.2 degrade rule
  (asymmetric head pairs with a non-none start collapse to `(none, end)`) — without this, the
  sanctioned degradation would fail the test by construction. The property-based test (random
  Thalyx docs → export → import → semantic equality) uses the same canonicalized comparison, so
  its generator may produce all 16 head pairs.
- **Reconcile** (built in M8): matched-position preservation (including the parentId-change
  coordinate conversion), new-node placement, deletion, edge matching.
- **Palette contrast** both themes (built in M2).
- **Mermaid upgrade gate** (built in M5): `npm ls mermaid` version assertion test — fails if the
  pin changes without regenerating corpus snapshots (forces conscious upgrades, D16).
- **PDF golden tests** (built in M7, runs in the Playwright web-mode suite since jsPDF/svg2pdf
  need a real browser): render three corpus docs to PDF, assert non-empty output, expected page
  dimensions, and page count 1 — a smoke net for svg2pdf marker/text regressions (§18).

### 15.2 E2E (Playwright, `tests/e2e`)

Two tiers:

- **Web-mode suite (primary, fast)**: renderer served by `vite preview` in Chromium with the
  browser platform fallback. Covers: create/connect/label flows, grow gesture, chevrons,
  duplicate, snapping (position assertions), undo, z-order, containers, paste-import of mermaid
  text, Mermaid panel apply/reconcile, export SVG/PNG downloads (content assertions on SVG).
- **Electron smoke suite (small)**: `_electron.launch()` (Playwright's Electron support — works
  on mac + linux, no WebDriver needed). Covers: app launches; open `.thalyx` via IPC-mocked
  dialog; save/atomic write happened; autosave recovery after `browserWindow.destroy()`
  (simulated crash); menu → renderer action wiring; second-instance file open.
  Runs on both CI OSes; Linux under `xvfb-run`.

### 15.3 Manual QA checklist (per release)

Kept as `docs/qa-checklist.md` (write at M8): HiDPI/fractional scaling on Wayland + X11
(`ELECTRON_OZONE_PLATFORM_HINT=auto` — set in main; verify text crispness), trackpad vs mouse,
IME composition in labels (type Japanese via ibus/macOS), dark-theme exports, 2000-node perf doc,
file association double-click, update flow from previous release.

---

## 16. CI/CD & releases

### `.github/workflows/ci.yml` (every PR/push)

- **check** (ubuntu): `npm ci` → typecheck → eslint → prettier check → license gate script →
  `vitest run` (includes the corpus suite via jsdom).
- **e2e** (matrix `ubuntu-latest`, `macos-latest`): build renderer, run Playwright web-mode
  suite (Chromium), then Electron smoke suite (`xvfb-run` on Linux).
- **package** (matrix): `electron-builder --publish never` (unsigned) to prove packaging never
  rots; upload artifacts.

### `.github/workflows/release.yml` (on tag `v*`)

- Matrix build: mac (dmg+zip, arm64+x64) on `macos-latest`, linux (AppImage, deb, rpm) on
  `ubuntu-latest`; `electron-builder --publish always` to a GitHub Release (draft), including
  `latest-mac.yml`/`latest-linux.yml` for electron-updater.
- macOS signing/notarization runs **only if** secrets (`CSC_LINK`, `CSC_KEY_PASSWORD`,
  `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`) are configured; otherwise the job
  still produces unsigned artifacts and prints a warning (prerequisite note: Apple Developer
  Program $99/yr for distribution outside quarantine bypass; document in README).
- Changelog: keep `CHANGELOG.md` (Keep-a-Changelog format) updated per milestone; release notes
  from it.

### Dependency policy

Renovate config (M0): weekly, grouped minor/patch; Electron majors as individual PRs (8-week
Chromium cadence — staying within the supported latest-3 window is a security requirement);
mermaid excluded from auto-bump (D16 gate).

---

## 17. Milestones

Each milestone lists **Goal / Tasks / Acceptance** — acceptance items are demoable or runnable
checks. Do them in order; do not start Mn+1 with Mn acceptance red. Keep `CHANGELOG.md` updated.

### M0 — Scaffold & guardrails

**Goal**: empty Electron+React app runs on mac & linux; all guardrails active.

Tasks:
1. electron-vite TypeScript scaffold per §6 tree; strict tsconfig; eslint+prettier.
2. Security baseline (§14.1–2), CSP, preload with a stub `appx.version()`.
3. Verification sub-tasks for facts flagged unverified in research: current Electron major &
   required macOS/glibc minimums (record in README), zustand current-major API, Playwright
   `_electron` current API, Open Color license file. Adjust pins accordingly.
4. `scripts/check-licenses.mjs` + `gen-third-party-licenses.mjs` + `THIRD_PARTY_LICENSES.md`.
5. vitest + one trivial shared-module test; Playwright installed with one launch smoke test.
6. `ci.yml` fully green on both matrix OSes; Renovate config; `CONTRIBUTING.md` (§4.6);
   `README.md` skeleton.

Acceptance: `npm run dev` opens a window with hot reload on mac+linux (CSP dev allowances per
§14.1); CI green including packaging job (unsigned artifacts produced); license gate
demonstrably fails when a GPL **production** dep is added in a test branch (dev-dep violations
only warn, per §4.1).

### M1 — Document model, store, history

**Goal**: the whole §7/§8 core exists as tested pure code — before any canvas pixels.

Tasks: `types/schema/create/restore/queries`; zustand store with doc+session slices; history
module; actions catalog (§8.3) for node/edge CRUD, z-order, containers, duplicate;
`thalyxFile.ts`. Unit tests per §15.1 (model, history).

Acceptance: `vitest run` covers restore-garbage cases, undo/redo including gesture coalescing,
invariant enforcement; mutation-through-actions is the only way to change the doc (lint rule or
convention test that `set(state => …)` appears only in actions.ts/history.ts).

### M2 — Canvas MVP + perf gate

**Goal**: see and edit a document.

Tasks: `Canvas.tsx` with controlled RF wiring (§11.1); ShapeNode/TextNode/ContainerNode;
selection (click/shift/rubber-band); move (transient+gesture); NodeResizer resize; the `shape`
tool (§8.1 pendingShape; keys R/O/D + all five toolbar shape buttons) with click-place and
drag-size; pan/zoom/nav per I2–I3 (no minimap); theme system + palette tokens (§10.4) including
the contrast unit test (§15.1); toolbar; empty-canvas hint layer (I1); perf fixture + spike
(§11.7).

Acceptance: create/move/resize/delete/undo all placeable shapes; containers loaded from fixture
docs render, move, and resize correctly with their children (container *creation* UX — F tool,
Mod+G — lands in M4); theme toggle remaps palette live; **perf gate numbers recorded in
`docs/perf.md`** for both OSes; e2e web-suite covers the basics.

### M3 — Connections

**Goal**: the connector experience (I7–I9).

Tasks: 4-side handles; floating attachment + anchors module; elbow router + ThalyxEdge component
(3 kinds, arrowheads, line styles, rounded corners); edge selection/deletion; edge label chip +
`labelT` drag; waypoint drag + clear-on-move rule (D12); arrow tool (A) and line tool (L);
edge-style inheritance (last used).

Acceptance: connect any two nodes from any side; edges re-route live at 60fps while dragging
nodes (perf doc updated); labels stay legible over lines; corpus of router side-cases green;
undo granularity: one entry per connect/label/waypoint gesture.

### M4 — Editing UX floor

**Goal**: the app feels like the §10 spec.

Tasks: inline label editing (I10: double-click/Enter/type-to-edit, textarea-in-node, IME
`isComposing` guard); alt-drag duplicate + `Mod+D` (I11); smart guides + equal spacing + grid
(I12, §11.4); nudge; z-order commands; group/ungroup containers (D5) + F/8 container tool;
alignment row actions (`alignSelection`, §8.3/§10.3); context panel (§10.3); curated palette +
custom picker escape hatch; keymap hook complete (§10.2 — including the e.code matching rules
and the type-to-edit precedence rule) + help overlay (`Shift+/`); quick-connect chevrons +
`Mod+Arrow` grow + Tab-cycle (§11.6); Tidy Up + dagre auto-layout actions (§11.5, incl. the
containered-doc layout unit test).

Acceptance: a first-time user can build the **login-flow demo** in under 90 seconds using only
keyboard+mouse per the spec. The demo (fixed, for repeatable timing): rounded nodes `Start` →
`Login form` → diamond `Valid?` —yes→ `Dashboard`, —no→ `Show error` → back to `Login form`;
`Login form`, `Valid?`, and `Show error` sit inside a container titled `Auth`; a final edge
`Dashboard` → `Log out`. (7 nodes counting the container, 6 edges.) Every I1–I18 behavior
manually verified against the checklist (record in `docs/qa-checklist.md` draft); e2e suite
covers grow gesture, chevrons, guides snapping, group, palette, and the type-to-edit-vs-tool-key
precedence.

### M5 — Mermaid import

**Goal**: paste Mermaid → editable diagram.

Tasks: renderer mermaid runtime (§9.1, D10 settings); tables.ts + entities.ts with the §9.2
ground truth; `importMermaid` (§9.3) + `importMermaidAsNew` action; dagre layout on import;
paste detection + toast (§9.7); island node + editor dialog (§9.8); `.mmd` open path (File →
Import Mermaid… + drag-drop of text files in web-mode); parse-error surfaces (line/col).
Corpus tests (§15.1 import half) + the mermaid upgrade-gate version-assertion test.

Acceptance: the corpus imports to exact snapshots; pasting each of: a 50-node flowchart (native,
laid out, editable), a sequence diagram (island), garbage ("not mermaid" → plain text paste)
behaves per spec; labels with `#quot;`/`&`/emoji round through display correctly; import is one
undo step.

### M6 — Mermaid export & round-trip

**Goal**: the graph is always available as clean Mermaid text.

Tasks: `exportMermaid` (§9.4, pure — returns `{text, idAssignments}`) + the untracked
`ensureMermaidIds` action (§8.3); Copy as Mermaid (`Mod+Shift+C`); Save as `.mmd`; Mermaid panel
live view (§9.5, read-only + copy + island notice); round-trip + fixpoint corpus tests (§15.1
export half, canonicalized comparison); property-based doc→text→doc test.

Acceptance: full corpus round-trip green; hand-built diagram from the M4 demo exports to Mermaid
that renders correctly on mermaid.live (manual check) and re-imports semantically identical;
byte-stable export across two consecutive exports (id stability).

### M7 — Files & desktop integration

**Goal**: a real desktop app citizen.

Tasks: complete IPC surface (§12.2) + path policy (§14.5); menus (§12.3); open/save/save-as with
dirty tracking; atomic writes + .bak; autosave + recovery + scratch-doc restore (§12.4); recents;
prefs; window-state; single-instance + open-file events; file associations (builder config);
drag-drop of `.thalyx`/`.mmd` onto the window (via the `pathForDropped` preload bridge, §14.5);
export dialog (SVG/PNG/PDF per §13, background choice, 1x/2x, PNG font inlining); PDF golden
tests (§15.1); clipboard flavors (§13.3); Print… (`webContents.print()`); About dialog with
licenses.

Acceptance: kill -9 during editing → relaunch restores the exact doc; double-click a `.thalyx`
in Finder/Files opens it (packaged build); exports open correctly in Inkscape (SVG), Preview
(PDF — vector, selectable text), and paste as PNG into an image editor; Electron smoke suite
green on both OSes.

### M8 — Sync, polish, release

**Goal**: v0.1.0 shipped.

Tasks: Mermaid panel edit mode + `applyMermaidText` reconcile (§9.5–9.6) with position
preservation, plus the reconcile unit tests (§15.1); direction switcher (`setDirection`); toast
system polish; a11y pass (toolbar/panel keyboard
navigation + ARIA labels, focus rings, reduced-motion); `docs/qa-checklist.md` final + full
manual pass on Ubuntu LTS (X11+Wayland) and macOS; updater wiring + verification of
electron-updater Linux target coverage (§12.6); release workflow + signing hooks; icons; README
with screenshots; CHANGELOG; tag v0.1.0, publish release, verify auto-update from a v0.0.x
throwaway build.

Acceptance: edit exported text in the panel (rename a node, add an edge, delete a node), Apply →
canvas updates with all untouched positions preserved, one undo step reverts; v0.1.0 artifacts
install and pass the QA checklist on both OSes; auto-update from a previous build works on
AppImage unconditionally, and on dmg **only if the macOS signing secrets are configured**
(unsigned mac builds cannot auto-update — §12.6; verify manually-downloaded dmg installs
instead).

### M9+ — Post-MVP

Backlog per §3, in order. Each item gets its own mini-spec PR against this plan before
implementation (state-diagram round-trip and elkjs option first).

---

## 18. Risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| React Flow perf at 1000–2000 complex nodes (maintainer: "not intended for 1000+ complex nodes") | Medium | M2 perf gate with recorded numbers; LOD plan; renderer-agnostic `src/shared` keeps the Konva escape hatch real (§11.7). |
| mermaid db internal API changes under us | Certain, eventually | Exact pin (D16); corpus snapshot suite is the upgrade gate; ground-truth doc records the 11.17.0 shapes. |
| Elbow routing quality disappoints vs OmniGraffle | Medium | MVP heuristic matches FigJam; M9 upgrade path (ELK routes / A*) specced; manual waypoints cover the last mile. |
| Electron security treadmill outpaces maintenance | Medium | Renovate individual-PR majors; CI packaging job keeps upgrades cheap; sandbox+CSP+no-remote-content minimizes blast radius. |
| Reconcile produces surprising merges on aggressive text edits | Medium | Reconcile is one undo step; matching rules are simple & documented in-app (panel help); corpus tests for the tricky cases. |
| PDF non-Latin limitation annoys users | Low-Med | Documented; SVG/PNG unaffected; post-MVP font-subsetting task listed. |
| jsPDF/svg2pdf marker/text edge cases | Medium | Export golden tests render corpus docs to PDF in CI and assert non-empty/page-size; manual QA item; Print… as native fallback. |
| Contributor code with incompatible licenses | Low | CI license gate; §4 rules; CONTRIBUTING sign-off. |

---

## 19. Rules for the implementing engineer/LLM

1. **Read §2 before every milestone.** If you find yourself re-deciding a D-number, stop.
2. **Milestones in order; acceptance before advancing.** Green CI is part of acceptance.
3. **No new dependencies** beyond §5 without: license allowlist check, ledger regeneration, and
   a note in CHANGELOG. Never any package from the banned list (§4).
4. **Never copy code** from tldraw, JointJS, GoJS, or React Flow Pro examples — regardless of
   how helpful a snippet looks (§4.3). Verbatim MIT copies go to `src/vendor/` with headers.
5. **All doc mutations through actions**; all geometry/serialization logic in `src/shared/`
   (no React/Electron imports there — enforced by an eslint `no-restricted-imports` rule you set
   up in M0).
6. When this plan pins a version and reality has moved (e.g. Electron 45 is current at M0):
   take the current **stable** version, verify the specific APIs this plan names still exist
   (their names are listed precisely so you can grep the changelog), and record the delta in
   CHANGELOG. Exception: mermaid stays pinned until the corpus gate passes on the new version.
7. When an instruction here conflicts with something a library's docs recommend, prefer the plan
   for *product decisions* and the library docs for *API mechanics* — and note the conflict in
   CHANGELOG so the plan can be corrected.
8. Commit style: small, milestone-scoped, imperative subjects (`M3: elbow router side cases`).
   Update `CHANGELOG.md` per milestone, not per commit.
9. The research notes in `docs/research/` are background and evidence — quote them in PR
   descriptions when useful, but **PLAN.md is the contract**.
