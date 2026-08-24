# Changelog

All notable changes to Thalyx are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). The authoritative roadmap is
[PLAN.md](PLAN.md) §17 — each milestone lands as its own PR and records any
deviations from the plan here (per PLAN.md §19.6–7).

## [Unreleased]

### M4a — Editing UX floor, part 1: text / duplicate / guides (PLAN.md §17 M4, split per the plan)

Added:

- **Inline label editing (I10)** — `LabelTextarea` rendered inside shape/text
  nodes when `session.editingLabel` targets them: double-click / Enter opens;
  Enter commits, Esc commits + deselects, blur commits; `isComposing` guarded
  (IME-safe); multi-line via newline.
- **Type-to-edit precedence (§10.2)** — printable chars (incl. Shift+letter
  capitals) on a single selected node start editing with that char and
  suppress single-key tool bindings; Shift+digit zoom chords and Shift+/
  still match on `e.code` first; tool keys work with empty/edge selections and
  after Esc.
- **Duplicate (I11)** — `Mod+D` (`duplicateSelection`) and **alt-drag**:
  originals return to their pre-drag positions while fresh re-ided copies
  land where the drag ended (one user intent; implemented via
  `altDragDuplicate` + position restore on drag-stop).
- **Smart guides + snapping (§11.4)** — full `computeSnap` engine (edge/center
  candidates capped at nearest 40, 6/zoom threshold, equal-spacing gap chips
  labeled with px values, 8-px grid lattice, Mod disables everything, smart
  guides win over grid) wired into node drags: transient snapped positions +
  `session.guides` rendered by the `GuideLines` overlay (ViewportPortal).
- **Nudge** — Arrow / Shift+Arrow moves the selection 1/8 px.
- **Z-order keys** — `Mod+[`/`Mod+]`/`Mod+Shift+[`/`Mod+Shift+]`.
- **Containers** — `F`/`8` tool (toolbar button + click-place) and
  `Mod+G`/`Mod+Shift+G` group/dissolve on the selection.
- Full §10.2 keymap skeleton (tools V/R/O/D/A/L/T/F/H with digit aliases,
  undo/redo, delete, zoom chords, Enter/Esc) in `useKeymap`; chevrons/grow/
  layout chords land with M4c.
- Tests: `computeSnap` table-driven suite (thresholds, zoom scaling, gap
  chips, grid, precedence, disableAll), action tests for nudge and
  alt-drag-duplicate semantics, and the `editing-ux.spec.ts` web e2e (label
  editing undo, type-to-edit precedence, Esc+tool-keys, Mod+D duplicate,
  guide snapping position assertion, group/dissolve, F tool).

### M3 — Connections (PLAN.md §17 M3)

Added:

- `src/shared/geometry/anchors.ts` (§11.2): `edgeEndpoints` — floating
  'auto' endpoints via shape-boundary intersection on the center-to-center
  line (analytic rect/ellipse/diamond), pinned sides via side midpoints,
  `facingSide` for the router.
- `src/shared/geometry/elbow.ts` (§11.3): `route()` — stub 16 px, L for
  orthogonal sides, Z via midline for opposite sides, U via
  rail-beyond-outermost for same side; `collapseCollinear`, `pointAtT`,
  `polylineLength` for label placement.
- `ThalyxEdge` component (§11.3): elbow (rounded 6 px corners via
  arc-joined polylines) / straight / curved (RF helpers); arrowhead markers
  (arrow/circle/cross, auto-start-reverse for the source end) defined inline
  per edge; solid/dashed/thick; hidden edges render nothing; a 16-px-wide
  invisible hit path for easy grabbing.
- Edge label chip at `labelT` (draggable — pointer drag updates `labelT` to
  the nearest point on the route, gesture-coalesced into ONE undo entry);
  opaque canvas background so labels stay legible over lines.
- Manual waypoints: dragging an elbow body inserts a waypoint at the drag
  position (transient frames in one gesture); D12 clear-on-endpoint-move is
  wired from M2's canvas gesture hooks.
- `ConnectionHandles` (§11.2): RF Handles on all four sides (id n/s/e/w) on
  every node kind — the drag affordance; the model always stores 'auto'.
- Arrow tool (A) + line tool (L): toolbar buttons, keymap keys;
  `connectEdge` action with last-used style inheritance (§10.1 delta 1 —
  session `lastEdgeStyle`).
- Edge selection (click) + deletion + undo; edges carry the `selected` flag
  since M2's selector fix.
- Tests: router side-case matrix (opposite/same/orthogonal sides, all-axis
  alignment + finiteness incl. overlapping rects, collapse/pointAtT), anchor
  goldens (center-line membership, ellipse radial, pinned midpoints,
  facingSide), actions tests (connect = one entry, style inheritance, label
  update, waypoint gesture coalescing, D12 clearing), and the
  `connections.spec.ts` web e2e (connect from handle with both tools,
  re-route on drag, select/delete/undo, label chip legibility).
- Perf (§17 M3): edge-reroute drag fps case in the perf spec; `docs/perf.md`
  extended (CI numbers to be filled from the first green run).

### M2 — Canvas MVP + perf gate (PLAN.md §17 M2)

Added:

- `src/shared/geometry/shapes.ts`: `shapePath(kind,w,h)` for all 16 ShapeKinds
  (§7.3) + `shapeBoundaryIntersection` (§11.2 analytic rect/ellipse/diamond).
- Theme system (§10.4): `src/renderer/theme/` — `palette.ts` (12 tokens ×
  light/dark pairs, Open Color-derived values, WCAG `contrastRatio`),
  `theme.css` (CSS variables), `colorStyle.ts` (token→var, hex→inline),
  `useEffectiveTheme.ts` (system/light/dark with live matchMedia).
- Canvas (§11.1): `Canvas.tsx` controlled React Flow wiring — no snapToGrid
  ever, `selectionOnDrag`, `panOnDrag={[1,2]}` (+ full pan with hand tool),
  pinch zoom, `onlyRenderVisibleElements`, min/max zoom 0.1/4, attribution
  kept; position/resize changes routed through transient store actions inside
  gestures (committed once per gesture); D12 waypoint clearing on endpoint
  move/resize. `rfSelectors.ts` (doc → RF nodes/edges; `extent:'parent'` for
  container children). Node components (memoized): `ShapeNode`, `TextNode`,
  `ContainerNode` (dashed frame + title). Minimal straight edges so fixture
  docs read (the real edge component lands in M3).
- Toolbar (M2 subset): select/hand, five toolbar shapes, text, grid toggle,
  theme cycle. Empty-canvas hint layer (I1).
- `useKeymap` (M2 subset of §10.2): tool keys V/R/O/D/H/T, Delete/Backspace,
  undo/redo, Shift+1/Shift+2 zoom-to-fit/selection (full keymap in M4).
- Shape/text tools place on canvas click (click-place; drag-size arrives with
  the M4 pointer layer).
- Test hooks: dev-only `window.__thalyxTest.loadDoc/getDocJson` (dev server or
  `?testHooks=1`) for e2e doc injection.
- Perf fixture generator `tests/perf/genDoc.ts` (500/1000/2000-node docs,
  mixed shapes, 1.5× edges, 10% containers).
- Playwright restructured into two tiers (§15.2): `web` project (vite preview
  serving the built renderer; `vite.preview.config.ts`) with
  `canvas.spec.ts` (create/move/resize/delete/undo, containers-from-fixture
  render + move-with-children, theme remap, grid) and `perf.spec.ts` (fps +
  drag-latency harness with loose CI floors); existing Electron smoke moved
  to `tests/e2e/electron/`. `tsconfig.e2e.json` added to the typecheck chain.
- Unit tests (92 total): shapePath goldens/degenerates, boundary
  intersections, palette contrast ≥ 4.5:1 in both themes (transparent against
  canvas), resolveColor, plus all M1 suites.

Changed / deviations from PLAN.md (§19.6–7):

- **Perf gate numbers (§11.7 / M2 acceptance)**: this implementation sandbox
  has no display and CI runners use software GL, so the *dev-class-machine*
  measurements (1000-node ≥ 50 fps, drag < 32 ms, both OSes) could not be
  taken here. Automated CI baselines are recorded in `docs/perf.md`
  (anti-regression floors + logged fps); **hardware measurements remain an
  open item** for a maintainer with a dev-class Mac + Linux box — methodology
  is documented in `docs/perf.md`.
- `@xyflow/react ^12.11.3` added (MIT, §5-listed); ledger regenerated.

### M1 — Document model, store, history (PLAN.md §17 M1)

Added:

- `src/shared/model/`: `types.ts` (§7.1 authoritative types), `schema.ts`
  (zod v4 with §14.6 bounds: labels ≤ 4 kB, ≤ 20 k nodes, finite geometry,
  size ≥ 8), `create.ts` (newDoc/newNode/newEdge factories with §10.4
  defaults), `restore.ts` (normalize-on-load per §7.5: DocTooNewError for
  version > 1, coercion, dangling/island edge dropping, parent/cycle repair,
  z-order fix, clamps, final zod assertion), `queries.ts` (absolute-position
  math, bounds, containment/descendants, edge selectors,
  `positionUnderParent` for invariant §7.2.7).
- `src/shared/files/thalyxFile.ts`: serializeDoc (2-space pretty + trailing
  newline, known-fields rebuild) / parseDoc (JSON.parse → restore).
- `src/shared/snap/snap.ts`: the `GuideLine` type only (session slice needs it
  per §8.1; the computeSnap engine lands in M4).
- `src/renderer/store/`: `history.ts` (snapshot undo/redo per §8.2 — commit /
  beginGesture / endGesture / undo / redo, LIMIT 100, structural sharing via
  reference identity), `store.ts` (zustand doc+session slices exactly per
  §8.1), `actions.ts` (§8.3 catalog for M1 scope: node/edge CRUD, transient
  move/resize inside gestures, delete/duplicate/paste with re-id + intra-edge
  preservation, align, z-order (block moves with descendants),
  group/dissolve containers with absolute-position-preserving re-parenting,
  waypoints + D12 clear-on-endpoint-move, canvas/direction/grid, session
  setters). Mermaid/layout actions arrive with M4–M8 per the milestone plan.
- Tests (70): restore garbage/idempotence (`restore(restore(x)) == restore(x)`),
  invariants 1–6, schema bounds, file round-trip/fixpoint, history semantics
  incl. gesture coalescing + limit + snapshot identity, action-level invariant
  enforcement (one history entry per intent), and the mutation-through-actions
  convention test (`setStore` only in store.ts/actions.ts; shared never imports
  renderer).

Changed / deviations from PLAN.md (§19.6):

- Dependency versions moved to current stable: `immer ^11.1.18` (plan said
  ^10), `nanoid ^6.0.1` (plan said ^5; API `nanoid(12)` verified unchanged),
  `zustand ^5.0.15`, `zod ^4.4.3` (as planned). THIRD_PARTY_LICENSES.md
  regenerated (9 bundled runtime deps now).

### M0 — Scaffold & guardrails (PLAN.md §17 M0)

Added:

- Electron + React + TypeScript scaffold via electron-vite, per the PLAN.md §6
  tree: `src/main` (window + lifecycle + security baseline), `src/preload`
  (contextBridge `window.thalyx` with stub `appx.version()`), `src/renderer`
  (splash), `src/shared` (doc-schema constants).
- Security baseline per §14.1–2: context isolation + sandbox + no node
  integration; `will-navigate` block; window-open deny; render-process-gone
  reload; CSP meta injected per build mode by a Vite HTML transform (strict in
  production, HMR allowances in dev).
- License gate: `scripts/check-licenses.mjs` (production violations fail CI,
  dev violations warn) + `scripts/gen-third-party-licenses.mjs` generating
  `THIRD_PARTY_LICENSES.md`; dompurify Apache-2.0 election map (D17).
- CI: typecheck + eslint + prettier + license gate + vitest on ubuntu; Playwright
  Electron smoke + unsigned electron-builder packaging on ubuntu & macos.
- vitest with the first shared-module test; Playwright smoke suite (launch,
  sandbox check, strict-CSP assertion on the packaged index.html).
- Renovate config (weekly; grouped minor/patch; electron majors individual;
  mermaid disabled per D16); CONTRIBUTING.md (Unlicense dedication policy);
  README skeleton.

Changed / deviations from PLAN.md (per §19.6 — reality verified 2026-08-23):

- **electron-builder `^26.15.3`** instead of the plan's `^27`: 26.15.3 is the
  current stable; 27 exists only as `27.0.0-alpha.7`. Will adopt 27 when
  stable.
- **typescript `~5.9.3`** instead of "current" (7.0.2): typescript-eslint
  8.67.0 peer-supports `typescript <6.1.0`. Revisit when typescript-eslint
  supports TS 7.
- **vite `^7.3.6`** instead of 8.2.2: electron-vite 5.0.0 peers
  `vite ^5||^6||^7`. Will move with electron-vite.
- `@vitejs/plugin-react ^5.2.0` (supports vite 4–8; 6.x requires vite 8).

Verified at M0 (task 3): Electron 43.4.1 (Chromium 150, Node 24.18.1; darwin
x64+arm64; macOS ≥ 12 "Monterey"; Linux built on Ubuntu 22.04, verified
Ubuntu 18.04+/Debian 10+/Fedora 32+); zustand current major is 5 (installed at
M1); Playwright 1.62.1 `_electron` API confirmed by the smoke suite; Open
Color license is MIT (ledger entry added).
