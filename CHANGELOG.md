# Changelog

All notable changes to Thalyx are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). The authoritative roadmap is
[PLAN.md](PLAN.md) §17 — each milestone lands as its own PR and records any
deviations from the plan here (per PLAN.md §19.6–7).

## [Unreleased]

### M8 — Sync, polish, release (PLAN.md §17 M8)

Added:

- **reconcileDocument (§9.6)** — position-preserving re-import: matched
  nodes (by meta.mermaid.id) keep x/y/size/style; labels/shapes/links
  updated; coordinate frames converted across parentId changes (deferred
  pass after placement so NEW parents have final positions); new nodes at
  the barycenter of placed neighbors (+GRID_GAP) or below content, nudged
  until not overlapping; absent ids deleted with edges; hand-drawn
  (no mermaid id) nodes + their intra-edges kept untouched; edges matched
  by (source, target, occurrenceIndex) with waypoints surviving only when
  endpoints didn't move. 7 unit tests incl. rename/add-edge/delete/
  parentId-change/unmatched-keep/fixpoint.
- **applyMermaidText** — one history entry; islands replace their source.
- **Mermaid panel edit mode (§9.5)** — Edit button / double-click;
  textarea with Mod+Enter Apply, Esc/Revert; unapplied-changes notice;
  parse-error surface; the ONE permitted confirm-style interaction
  (leaving with unapplied changes) is a notice, not a dialog.
- **Updater (§12.6)** — electron-updater wired: background check 5 s
  after launch, manual handler, "Restart to update?" toast (never
  force); GitHub Releases feed (electron-builder publish config);
  Linux Wayland hint (ELECTRON_OZONE_PLATFORM_HINT=auto).
- **Release workflow** — .github/workflows/release.yml on v* tags:
  mac (dmg arm64+x64) + linux (AppImage/deb/rpm) with
  --publish always (latest-mac.yml/latest-linux.yml for the updater);
  macOS signing/notarization only when secrets exist (warning otherwise,
  §12.6).
- **a11y pass** — focus-visible rings everywhere, prefers-reduced-motion
  honored, aria labels on icon-only buttons.
- docs/qa-checklist.md finalized (M6 manual checks section added earlier).

Changed / deviations from PLAN.md (§19.6–7):

- Python-2.0 (PSF) added to the license allowlist for argparse
  (electron-updater → js-yaml transitive; BSD-class permissive) — §19.3
  note here and in scripts/lib/licenses.mjs.
- v0.1.0 tag + release verification happen from main right after this
  PR merges; auto-update verification from a v0.0.x throwaway build
  requires the release artifacts to exist (documented in
  docs/qa-checklist.md as the post-tag step).

### M7 — Files & desktop integration (PLAN.md §17 M7)

Added:

- **Complete IPC surface (§12.2)** — main `ipc.ts` (dialog/file/recovery/
  recents/prefs/shellx/clip/appx/export handlers; zod-validated inputs;
  §14.5 path-policy grant set + extension allowlist + 50 MB caps;
  `THALYX_ALLOW_ANY_PATH` dev loosening) + preload exposing exactly the
  §12.2 list (contextBridge; `pathForDropped` wraps `webUtils.getPathForFile`
  and main re-validates; `onMenu`/`onOpenFile`/`onRecoveryScratch` events).
- **Files (§12.4)** — `files.ts`: atomic writes (tmp+rename), per-session
  `.bak`, recovery store (`recovery/<docId>.thalyx` + manifest; docId =
  sha256(path).slice(16), scratch ids via prefs), prefs JSON (zod,
  normalize-on-load, existence-checked recents).
- **Menus (§12.3)** — role rule honored (roles only for app/window menus;
  Edit items are role-less custom items dispatching `menu:action` events the
  renderer routes by focus); File/View/Help per the plan; macOS
  `setDocumentEdited` + recents submenu.
- **Lifecycle wiring** — `useDocumentLifecycle`: 800 ms debounced autosave
  (path → atomic in-place; untitled → recovery), dirty/title/edited
  indicators, recovery clearing for saved docs, scratch-doc restore on
  launch, open-file/open-recent/import-Mermaid handling, menus→store actions.
- **Export pipeline (§13)** — `renderDocToSvg` (pure; background choice,
  containers-back, markers per arrowhead/color, Inter font-family, line
  breaking, island placeholder/embed, label chips; no CSS classes, no
  foreignObject), PNG (blob→Image→canvas at 1×/2×, font inlining via data:
  URI for the isolated SVG context), PDF (jsPDF+svg2pdf from the model SVG;
  Inter TTF registration best-effort), `.mmd` via the M6 exporter,
  internal clipboard flavor (thalyx JSON + PNG ClipboardItem), browser
  fallbacks (download anchors/localStorage) for web-mode.
- **Export dialog** — Mod+Shift+E: SVG/PNG/PDF/MMD, 1×/2×, background
  choice.
- **File associations** — electron-builder `fileAssociations` (.thalyx own
  icon+MIME, .mmd/.mermaid alternate); `open-file`/argv routing.
- **E2E** — `desktop.spec.ts` Electron suite (menu→store wiring, crash
  simulation: `destroy()` → relaunch restores the scratch doc via recovery,
  full `window.thalyx` surface check) + `export-pipeline.spec.ts` web suite
  (SVG self-containment/XML validity/background modes, PNG dimensions, PDF
  one-page golden smoke, clipboard flavor). Virtual e2e modules exposed by
  the preview config.

Changed / deviations from PLAN.md (§19.6–7):

- `jspdf ^4.2.1` / `svg2pdf.js ^2.7.0` added (MIT, §5-listed). Transitive
  `pako` is `(MIT AND Zlib)` — **Zlib added to the license allowlist**
  (BSD-style permissive, same class as the listed licenses; CHANGELOG note
  per §19.3). Ledger regenerated.
- PNG save in Electron currently uses the download-anchor path (the §12.2
  text-bridge cannot carry binary save dialogs); native binary save-file IPC
  is an M8 polish candidate. Clipboard PNG uses `clip.writePng`.
- Wayland hint, updater wiring, About/licenses dialog: M8 scope per plan.

### M6 — Mermaid export & round-trip (PLAN.md §17 M6)

Added:

- **`exportMermaid` (§9.4, pure)** — returns `{text, idAssignments}` without
  touching the doc: frontmatter verbatim; `flowchart <dir>`; node lines in
  z-order (skip-eligible nodes — label==id, rect, in an edge — omit the
  declaration; edge-less nodes always get one); containers as `subgraph`
  blocks with `direction` and nesting; the 22-body emit table exactly
  (degrade rule + minlen extension, `~~~` for hidden); `|label|` edge labels;
  `id@` user edge ids; style tail (classDef/class/style/click-with-tooltip).
  Empty labels emit a quoted space (`A[""]` is a parse error — verified).
  Islands: mixed docs export the flowchart only; callers surface the
  "N islands not included" notice (the panel does).
- **`ensureMermaidIds` (§8.3)** — the ONE untracked doc mutation (comment at
  the definition): applies idAssignments, idempotent, never pollutes undo,
  triggered by viewing the panel.
- **Round-trip machinery (§15.1)** — `semanticallyEqual` (canonicalized
  heads, mermaid-id keying, containment/dir/link) + fixpoint assertion.
- **Corpus round-trip** — every flowchart fixture: import → export → import →
  semantic equality + `export(M2) === export(M1)` byte-equal. Emit-table
  coverage test (all 21 bodies in one doc), degrade/hidden/lone-node/blocklist
  tests, and a 25-iteration deterministic property test (random docs → export
  → import → semantic equality + fixpoint).
- **Mermaid panel (§9.5)** — `Mod+Shift+M` toggle; live export debounced
  300 ms (read-only `pre`, selectable); `ensureMermaidIds` applied untracked;
  island notice; single-island docs show the island source; direction
  dropdown (TB/BT/LR/RL → `setDirection`, one undo step); Copy button.
- **`copyAsMermaid` (`Mod+Shift+C`)** — export selection-or-doc, apply ids,
  clipboard write.
- e2e `mermaid-export.spec.ts`: panel open/close + live content (subgraph,
  labeled edges), byte-stability across a doc change, direction round-trip
  with undo, island notice, single-island source, and the M4 demo graph
  exported → re-imported → identical labels/counts.

Deviations from PLAN.md: none. (Known-loss list §9.4.7 untouched by design;
manual mermaid.live check noted in qa-checklist for M8.)

### M5 — Mermaid import (PLAN.md §17 M5)

Added:

- **`src/shared/mermaid/tables.ts` (§9.2)** — ground-truth tables: vertex
  type→ShapeKind (+ `@{shape:}` alt names), the two orthogonal import
  lookups (edge.type→heads, edge.stroke→line/hidden), the 21-entry emit
  table + `~~~`, `canonicalizeHeads` (degrade rule), `extendBody` (minlen
  middle-char rule), the id blocklist, and the FULL sequence LINETYPE table
  (0–34) + PLACEMENT.
- **`src/shared/mermaid/entities.ts`** — `decodeMermaidLabel` (placeholder
  decode → EXACTLY ONE entity pass → `<br>`→newline; verified raw
  `ﬂ°quot¶ß` forms) and `encodeLabel` (order-sensitive escaping:
  `#`→`#35;` then `&`→`#38;` then `"`→`#quot;` then newline→`<br>`;
  always quoted).
- **`src/shared/mermaid/detect.ts`** — `isProbablyMermaid` prefilter
  (frontmatter + `%%` skipping, keyword headers).
- **`src/shared/mermaid/import.ts` (§9.3)** — `importMermaid(text, parse)` →
  flowchart nodes/edges/meta (subgraphs topologically parent-first via
  nesting depth, vertices with classDef-composed styles, edges with
  heads/line/minlen/user-id meta, frontmatter preserved, TD→TB) |
  island {diagramType, source} | error {message, line/col}. Awaited
  ParseFn (the renderer supplies the D9 runtime; tests the jsdom shim).
- **Renderer runtime (§9.1, D10)** — `src/renderer/mermaid/runtime.ts`
  (htmlLabels always off; parse-first D9 sequence; error positions from
  `hash.loc`).
- **`importMermaidAsNew` action** — one history entry; island or
  dagre-laid-out flowchart (direction from the parsed doc); selects the
  result. `updateNodeMermaidSource` for the island editor.
- **`MermaidIslandNode` (§9.8)** — `mermaid.render` → DOMPurify
  (svg profile, foreignObject forbidden) → injected; placeholder/error
  states; Enter opens the modal editor (textarea + Apply/Cancel) which
  updates the source in one entry.
- **Paste import (§9.7)** — `usePasteImport`: mermaid-looking paste →
  import + fit + toast ("Imported Mermaid — ⌘Z to undo" + "Paste as text
  instead" escape hatch); garbage → text node; plain text → text node at
  the viewport center.
- **Corpus (§15.1 import half)** — 12 fixtures (all 21 arrow bodies +
  minlen extensions, every shape bracket, `#quot;`/`&`/`&lt;`/`<br>`/unicode/
  backtick labels, nested subgraphs with `direction`, classDef/style/
  linkStyle/click/tooltips, `~~~`, `e@-->` ids, `@{shape: cyl}`,
  frontmatter, sequence island) + shim; 30 new unit tests incl. the
  mermaid-upgrade-gate version assertion (D16).
- e2e `mermaid-import.spec.ts`: native import (3 nodes, 2 edges, ranks
  separated, diamond mapped, one-undo), island render, garbage→text,
  escape hatch, island editor Apply, 50-node import.

Changed / deviations from PLAN.md (§19.6–7):

- `mermaid 11.17.0` exact-pinned and `dompurify ^3.4.14` added (both
  §5-listed; dompurify's Apache-2.0 arm elected per D17); ledger
  regenerated (130 bundled runtime deps — mermaid's tree).
- `@types/jsdom` dev-dep added for the shim's types.
- Import-ground-truth deltas recorded: mermaid decodes `&lt;` itself in db
  text when the source contains it literally (the plan's `#38;lt;` flow
  is the export side); `click` hrefs are URL-normalized (trailing slash).
  Both asserted per observation, not per assumption.

### M4c — Editing UX floor, part 3: chevrons / grow / layout-actions (PLAN.md §17 M4, final part)

Added:

- **`src/shared/layout/dagreLayout.ts` (§11.5, D3)** — `@dagrejs/dagre ^3.1.1`
  added (MIT, §5-listed; ledger regenerated): compound+multigraph, default
  edge labels, minlen from `meta.mermaid.minlen`, containers as clusters with
  member-derived sizes, container-endpoint edges skipped (cluster-edge
  limitation per plan), centers→top-left with parent-relative conversion.
- **`src/shared/layout/tidy.ts`** — Tidy Up: row/column/grid inference from
  the current arrangement, 24 px gaps, dominant-axis alignment.
- **Actions** — `autoLayout` (selection's subgraph or whole doc, direction
  from `meta.mermaid.direction`, one history entry), `tidyUpSelection`,
  `growConnectedNode` (§11.6: 48 px corridor — connect to an existing node or
  create with inherited style/size + last-used edge style; one entry; select
  + open label editor).
- **`QuickConnectChevrons` (§11.6)** — ViewportPortal overlay: 4 chevrons on
  the hovered node (select tool, zoom ≥ 40%, Q toggle, hidden while editing);
  click = grow in that direction.
- **Keymap completion** — `Mod+Arrow` grow (gated while a label editor is
  open), `Alt+Shift+T` / `Alt+Shift+L` layout chords (e.code matching).
- **ContextPanel** — Tidy + Auto buttons in the ≥2-nodes row.
- **Tests** — 8 layout unit cases (chain ranks, LR, containered-doc acceptance
  incl. children-in-bounds, subset-only, minlen spacing; tidy row/column/grid
  with 24 px gaps); `grow-layout.spec.ts` e2e (grow ± corridor connect, one
  undo entry, chevrons + Q toggle, Alt+Shift+T gaps, Alt+Shift+L ranks, and
  the full M4 login-flow acceptance demo). `docs/qa-checklist.md` draft
  (I1–I18 + §10.2 + demo timing) per §15.3.
- Dev hooks: `selectNode` / `addNodeToSelection` for e2e selection driving.

### M4b — Editing UX floor, part 2: panel / palette / keymap (PLAN.md §17 M4, split per the plan)

Added:

- **ContextPanel (§10.3)** — one floating left-docked panel scoped to the
  selection: nothing selected → grid/theme/direction; node(s) → fill palette
  (12 tokens + custom-hex escape hatch), stroke width (3-segment), font size
  (4-segment), corner sharp/round toggle (rect/rounded only — swaps the
  ShapeKind per §7.1), shape swap popup (full §7.3 set, toolbar five
  starred), link field (`setNodeLink` action → `meta.mermaid.link`), lock
  toggle; ≥2 nodes → alignment row (6 align actions); edge(s) → line style /
  route kind / arrowheads per end / label field. Segmented controls for ≤5
  options; nothing nests.
- **HelpOverlay (Shift+/)** — searchable shortcut sheet (35 bindings,
  filtered by keys/action/group; Esc closes).
- **Keymap completion (§10.2)** — `Shift+Alt+D` theme cycle, `Q` chevron
  toggle, `Shift+/` help (Alt chords matched on `e.code` per the matching
  rules).
- Session gains `helpOpen`; actions gain `setHelpOpen`/`toggleChevrons`/
  `setNodeLink`.
- e2e `panel.spec.ts`: canvas panel round-trips, palette token + custom hex
  in the doc, stroke/font segmented controls, shape swap + corner toggle,
  alignment row, connector controls (dashed round-trip), help overlay search,
  theme chord.

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
