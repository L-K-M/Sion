# Thalyx research notes — document model, persistence, editor architecture

Researched 2026-08-23. All licenses verified at research time. Thalyx targets: Tauri (macOS + Linux),
React frontend, 500–2000 shapes, deep Mermaid import/export, public-domain (Unlicense) release —
so every dependency below is MIT/Apache-2.0/ISC unless flagged otherwise.

---

## 1. Document format

### 1.1 Excalidraw `.excalidraw` format (MIT — safe to copy ideas AND code)

- Repo: https://github.com/excalidraw/excalidraw — **License: MIT** (verified: https://github.com/excalidraw/excalidraw/blob/master/LICENSE). npm package `@excalidraw/excalidraw` also MIT.
- Format docs: https://docs.excalidraw.com/docs/codebase/json-schema
- Serialization internals: https://deepwiki.com/excalidraw/excalidraw/6.2-scene-serialization-and-file-formats and `packages/excalidraw/data/json.ts` (function `serializeAsJSON`).

Top-level structure (`ExportedDataState` type):

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://excalidraw.com",
  "elements": [ /* flat array of element objects */ ],
  "appState": { "gridSize": 20, "viewBackgroundColor": "#ffffff" },
  "files": { "<fileId>": { "mimeType": "image/png", "id": "...", "dataURL": "data:...", "created": 0 } }
}
```

Key design decisions worth copying:
- **Flat array of elements** (no nesting); z-order = array order. Grouping via `groupIds: string[]` on each element; frames via `frameId`.
- **Every element carries the same common props**: `id`, `type`, `x`, `y`, `width`, `height`, `angle`, `strokeColor`, `backgroundColor`, `fillStyle`, `strokeWidth`, `strokeStyle`, `roughness`, `opacity`, `groupIds`, `frameId`, `roundness`, `seed`, `version`, `versionNonce`, `isDeleted`, `boundElements`, `updated`, `link`, `locked`.
- **Linear elements (arrows/lines)** add: `points: [x,y][]` (relative to element x/y), `startBinding`/`endBinding` (`{ elementId, focus, gap }` — the logical connection!), `startArrowhead`/`endArrowhead`.
- **Text elements** add: `text`, `fontSize`, `fontFamily`, `textAlign`, `verticalAlign`, `containerId` (text bound inside a shape — labels on nodes).
- **Bindings are bidirectional**: shape has `boundElements: [{id, type}]`, arrow has `startBinding.elementId` / `endBinding.elementId`. This is exactly the data Thalyx needs to emit Mermaid edges (`A --> B`).
- **Soft delete**: `isDeleted: true` instead of removal (needed for sync/undo; elements are filtered out on export).
- `version` (int, increments per mutation) + `versionNonce` (random) per element = conflict resolution for collaboration; `seed` drives the roughjs randomness.
- File-level `version: 2` = **schema version**, only bumped on breaking changes; checked by `isValidExcalidrawData()`; constant `VERSIONS.excalidraw`.
- MIME types: `.excalidraw` = `application/vnd.excalidraw+json`; library files `.excalidrawlib` = `application/vnd.excalidrawlib+json`.
- Excalidraw can also **embed the JSON scene inside exported PNG/SVG** (`encodePngMetadata` writes it into a PNG tEXt chunk; SVG gets a base64 payload; decoded via `decodePngMetadata` / `decodeSvgBase64Payload` in `packages/excalidraw/data/blob.ts`, entry `loadFromBlob`). Great UX: a shared PNG stays editable.

### 1.2 Migration strategy: Excalidraw's `restore()`

Excalidraw does NOT keep per-field migration scripts. On load, `restoreElements(elements)` / `restoreAppState(appState)` (in `packages/excalidraw/data/restore.ts`) **normalize every element to the current shape**: fill in missing props with defaults, coerce legacy values, drop unknown junk. This "restore/normalize on load" approach is much easier for a weaker LLM to implement correctly than an ordered migration chain, and it's tolerant of hand-written/partial files (also good for Mermaid-imported docs).

### 1.3 tldraw store (REFERENCE ONLY — license NOT acceptable)

- **License: "tldraw license"** — source-available, production use requires a license key, watermark unless Business license, explicitly "not open source by any definition". https://tldraw.dev/community/license and https://tldraw.dev/legal/tldraw-sdk-3-x-license. **Do not depend on any `@tldraw/*` package. Do not copy code.** Reading the docs/architecture for ideas is fine.
- Store = reactive record database: a flat map `id -> record` of typed records (`TLRecord` union: `TLShape`, `TLPage`, `TLAsset`, `TLBinding`, `TLInstance`, `TLCamera`, …). IDs are prefixed: `"shape:xyz"`, `"page:abc"`. https://tldraw.dev/reference/store/Store
- Snapshot = `{ store: Record<id, record>, schema: { schemaVersion, sequences: {...versions} } }` — **the schema versions are serialized inside every snapshot**, so `loadSnapshot` knows exactly which migrations to run. `getSnapshot(editor.store)` / `loadSnapshot(store, snapshot)` split into `{ document, session }` — document (shapes/pages/bindings) vs session (camera, selection) — persist document, keep session per-user/local. https://tldraw.dev/docs/persistence
- Migrations: ordered up/down functions per record type (`createShapePropsMigrationSequence`), store-level migrations run first, then per-record. Powerful but significantly more code and more ways to get wrong than Excalidraw's normalize-on-load.
- Separate `TLBinding` records (v3+) for arrow↔shape connections — connection is a first-class record, not a prop. Conceptually nice for Mermaid export but adds indirection.

### 1.4 Recommended Thalyx document schema (synthesis)

Excalidraw-style single JSON file, but with **nodes and edges as distinct kinds** (Mermaid is a node/edge graph; React Flow is node/edge; keeping connectivity first-class makes `export to mermaid` a pure function over the doc):

```jsonc
{
  "type": "thalyx",
  "version": 1,                    // file schema version, bump only on breaking change
  "source": "thalyx@0.1.0",
  "pages": [
    { "id": "page1", "name": "Page 1",
      "nodes": [
        { "id": "n1", "shape": "rect", "x": 0, "y": 0, "width": 160, "height": 56,
          "angle": 0, "label": "Start", "style": { "fill": "#fff", "stroke": "#1e1e1e",
          "strokeWidth": 2, "fontSize": 14, "fontFamily": "sans" },
          "groupIds": [], "locked": false, "meta": { "mermaidId": "A" } }
      ],
      "edges": [
        { "id": "e1", "source": "n1", "target": "n2",
          "sourceAnchor": "auto", "targetAnchor": "auto",
          "kind": "orthogonal",          // straight | orthogonal | bezier
          "label": "yes", "markerStart": "none", "markerEnd": "arrow",
          "waypoints": [], "style": { "stroke": "#1e1e1e", "strokeWidth": 2 } }
      ]
    }
  ],
  "styles": { "themes": {}, "defaults": {} },   // named style presets
  "appState": { "activePageId": "page1" }       // strip volatile parts on save, like Excalidraw's cleanAppStateForExport
}
```

- Mermaid export = walk `edges`, map `source`/`target` node ids to labels/`meta.mermaidId`. Mermaid import = create nodes+edges, run layout (dagre/elk — other research topic), keep `meta.mermaidId` for round-tripping.
- Versioning rule: unknown fields preserved where possible, missing fields defaulted by a `restoreDocument()` normalizer (Excalidraw approach). Write `version` at top level; refuse only if `version > CURRENT`.
- Keep zod (MIT) schemas for the doc — gives validation + TS types + good errors for hand-edited files.

---

## 2. Undo/redo

### 2.1 What the reference apps actually use

- **Excalidraw**: rewrote history in PR #7348 ("feat: multiplayer undo/redo", merged 2024) from snapshot-based to **delta-based**: invertible increments (`ElementsChange` + `AppStateChange`, later `HistoryDelta` with an `applyTo(elements, appState)` method) stored in local-only undo/redo stacks; deltas can be calculated, applied, inverted, and merged, with conflict-resolution logic for multiplayer. Files: `packages/excalidraw/history.ts`, `packages/excalidraw/change.ts`. https://github.com/excalidraw/excalidraw/pull/7348, https://deepwiki.com/excalidraw/excalidraw/5.3-history-system. It also exposes an `onIncrement` store callback for custom history.
- **tldraw**: `HistoryManager` records **`RecordsDiff`** objects (before/after per record); helpers `reverseRecordsDiff`, `squashRecordDiffs`. Key UX API: **marks** — `editor.markHistoryStoppingPoint()` before an interaction, `squashToMark` collapses everything since the mark into a single undo step (used e.g. while cropping); `ignore`/ephemeral changes (camera, selection) never enter history. https://tldraw.dev/sdk-features/history
- Both apps converged on diffs/deltas because they need multiplayer. **Thalyx is single-user local-first — it does not need delta history.**

### 2.2 Options ranked by implementability for a weaker LLM

1. **Immutable snapshot history (RECOMMENDED)** — keep the whole document immutable (immer or plain spread updates); undo stack = array of previous document references. With structural sharing, a snapshot costs only the changed path, so 500–2000 shapes × a few hundred history entries is trivially fine in memory. Almost impossible to get wrong: no inverse operations, no command classes, no drift between do and undo.
   - **zundo** (https://github.com/charkour/zundo, npm `zundo`, **MIT**, <700 bytes) = `temporal` middleware for zustand that does exactly this: `temporal(config, { partialize, limit, equality, handleSet })`. `useStore.temporal.getState().undo() / .redo() / .clear()`; `partialize` limits tracking to the document slice (exclude camera/selection); `handleSet` + debounce or an explicit `pause()/resume()` gives drag-coalescing (one undo step per drag, tldraw's "mark" behavior).
2. **Immer patch history** — `enablePatches(); const [next, patches, inversePatches] = produceWithPatches(doc, draft => {...}); applyPatches(doc, inversePatches)` to undo. Patch format `{op: 'add'|'replace'|'remove', path: [...], value?}`. Memory-optimal and gives you a change feed (useful later for autosave diffing / collaboration), but the LLM must remember to route EVERY mutation through `produceWithPatches` and to pair patch/inverse arrays correctly. immer is **MIT**. This is the sensible v2 upgrade path; the `travels` library (https://libs.tech/project/1067001687/travels) packages this pattern but is niche — prefer hand-rolling ~50 lines if going this route.
3. **Command pattern** (each action a class with `do()`/`undo()`) — most code, easiest to get subtly wrong (every new feature needs a correct inverse). Not recommended; neither Excalidraw nor tldraw uses classic commands.

Concrete rules to encode in the plan:
- History records **document state only** (nodes/edges/pages/styles). Camera, selection, hover, tool = session state, never in history (both Excalidraw and tldraw do this; tldraw restores selection via diffs, but selection-in-history is a common bug source — skip it or store `selectedIds` alongside each snapshot cheaply).
- Coalesce pointer-move streams: push one history entry per gesture (pointerdown→pointerup), e.g. zundo `pause()` on dragstart, `resume()` + single set on drop.
- Cap history (`limit: 100` in zundo) to bound memory.

---

## 3. State management for a React canvas editor

- **React Flow (`@xyflow/react`, MIT) uses zustand internally** — its `useStore` hook literally re-exports zustand's, and the store holds `nodeLookup`/`connectionLookup` Maps (O(1) access), viewport `transform`, plus actions like `setNodes` (source: `packages/react/src/store/initialState.ts`; https://reactflow.dev/api-reference/hooks/use-store; https://deepwiki.com/xyflow/xyflow/4-react-flow-(@xyflowreact)).
- React Flow's own guidance ("Using a State Management Library", https://reactflow.dev/learn/advanced-use/state-management): for production apps, hold `nodes`/`edges` in **your own zustand store** and pass them in, rather than `useNodesState`/`useState`; Redux/Recoil/Jotai also work but zustand is the documented default.
- Verdict for Thalyx: **zustand** (npm `zustand`, pmndrs, **MIT**). Reasons a weaker LLM benefits: single-store mental model, plain-function actions, selector subscriptions prevent whole-canvas re-renders, works outside React (keyboard shortcuts, Tauri menu events), and both the canvas lib (React Flow) and the undo lib (zundo) are built for it. jotai (MIT) is fine but atom-graph design is easier to fumble; redux toolkit (MIT) adds boilerplate with no benefit here.
- Store layout: two slices — `doc` (persisted, in history) and `session` (camera/viewport, selection, active tool, dragging state; not persisted, not in history). Middleware order: `temporal(immer(creator))` with `partialize: s => ({ doc: s.doc })`.

---

## 4. Rendering approach for 500–2000 shapes

What the three reference editors do:
- **React Flow**: nodes = **HTML divs** absolutely positioned with `transform: translate(x,y)`; edges = **SVG `<path>`** in a separate layer; one wrapper div carries the whole pan/zoom as a single CSS `transform: translate(tx,ty) scale(k)` driven by **d3-zoom/d3-drag**. Perf props: `onlyRenderVisibleElements` (viewport culling — but degrades when fully zoomed out since everything is visible), memoized node components, avoid heavy CSS (shadows/gradients/`stroke-dasharray` animations), `will-change: transform`/3D transforms to force GPU layers. Sources: https://reactflow.dev/learn/advanced-use/performance, https://github.com/xyflow/xyflow/discussions/4975, https://www.visualflow.dev/blogs/scale-studio-pro. Community consensus: comfortable into the low thousands of nodes; 10k+ needs canvas/semantic zoom.
- **tldraw**: DOM too — React components emitting HTML+SVG per shape, dual pipeline (React component for editing, `toSvg` per shape for export), spatial index + viewport culling via `display:none` on off-screen shapes ("10,000 shapes might only render 50"), fine-grained reactivity so only the changed shape re-renders; recently moved selection indicators/overlays to Canvas2D for perf (issue #8314). https://tldraw.dev/sdk-features/performance
- **Excalidraw**: pure **Canvas2D** (roughjs), immediate-mode redraw. Fastest ceiling, but you must hand-build hit-testing, text editing overlays, accessibility — a large correctness burden.

Tradeoff table for the 500–2000 target:
- SVG-only: simplest export story, but 2000 stroked/filled SVG nodes + text re-layout on pan/zoom is the slowest DOM option; fine ≤ ~500.
- **HTML nodes + SVG edge layer + single CSS transform for pan/zoom (React Flow model): RECOMMENDED.** Proven at this scale, gets native text editing (contentEditable/inputs in nodes), CSS styling, DOM hit-testing free; export handled from the model, not the DOM (see §5).
- Canvas2D: only needed >5–10k shapes; wrong ergonomics for "drag-and-drop high-fidelity editing" built by a weaker model.

Strong recommendation: **build on `@xyflow/react` (React Flow v12, MIT)** rather than hand-rolling the canvas: it supplies viewport (d3-zoom), node drag, selection box, handles/anchors for connections, `onlyRenderVisibleElements`, minimap/background/controls components — and its node/edge arrays map 1:1 to the Thalyx doc model and to Mermaid graphs.

---

## 5. Export

Rule that avoids an entire class of bugs: **generate exports from the document model, not by scraping the live DOM.** Write one pure function `renderDocToSvg(doc, page): SVGElement` (plain SVG: `<rect>/<ellipse>/<path>/<text>`, no foreignObject) and derive every format from it. Excalidraw does exactly this (`exportToSvg`, `exportToCanvas`, `exportToBlob` in `@excalidraw/utils`, all operating on `elements` + `appState`, not on the live canvas; https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/utils/export).

- **SVG file**: `new XMLSerializer().serializeToString(svgEl)`; inline all styles as attributes (no external CSS), embed fonts only if using non-system fonts (`@font-face` with data: URI) — otherwise use system stack. Caveat if instead DOM-scraping via html-to-image `toSvg`: it wraps HTML in `<foreignObject>`, which Inkscape/Illustrator/most non-browser tools cannot open. Don't ship that as "SVG export".
- **PNG**: rasterize the same SVG string:
  ```ts
  const blob = new Blob([svgString], { type: 'image/svg+xml' });
  const url = URL.createObjectURL(blob);
  const img = new Image();
  img.onload = () => { const c = document.createElement('canvas');
    c.width = w * scale; c.height = h * scale;            // scale=2 for retina export
    c.getContext('2d')!.drawImage(img, 0, 0, c.width, c.height);
    c.toBlob(save, 'image/png'); URL.revokeObjectURL(url); };
  img.src = url;
  ```
  (No canvas tainting since the SVG blob is same-origin and contains no external resources.) Fallback/alternative for DOM capture: **html-to-image** (MIT) `toPng(el, { cacheBust: true })` — React Flow's official "Download Image" example uses it (https://reactflow.dev/examples/misc/download-image) but the community pins **html-to-image@1.11.11** because later releases broke exports (xyflow discussion #1061). Prefer the model-rendered SVG path; keep html-to-image out of core.
- **PDF**: **svg2pdf.js** (yWorks, https://github.com/yWorks/svg2pdf.js, **MIT**, v2.7.0, peer-dep **jsPDF** also MIT): `const pdf = new jsPDF({unit:'pt', format:[w,h]}); await pdf.svg(svgEl, {x:0,y:0,width:w,height:h}); pdf.save('diagram.pdf')`. Vector output, works offline in the webview. Do NOT plan on webview print-to-PDF in Tauri: wry has no cross-platform silent `print_to_pdf` (open issues wry#707, tauri#12284; WebKitGTK/WKWebView have native APIs but they're not exposed; `window.print()` opens the OS dialog and can't target a file programmatically). svg2pdf.js is the reliable route; `window.print()` can remain a bonus menu item.
- **Clipboard**:
  - PNG: `await navigator.clipboard.write([new ClipboardItem({ 'image/png': pngBlobPromise })])` — supported in all modern engines (web.dev pattern: https://web.dev/patterns/clipboard/copy-images/).
  - SVG: gate on `ClipboardItem.supports('image/svg+xml')` (Baseline API) — Chromium supports SVG clipboard; WebKitGTK/WKWebView may not → fall back to `navigator.clipboard.writeText(svgString)` (pasteable into text editors, and many apps accept SVG text). https://developer.chrome.com/blog/svg-support-for-async-clipboard-api
  - Also write a custom JSON flavor for internal copy/paste (Excalidraw uses `{"type":"excalidraw/clipboard", ...}` as text) so paste-within-app preserves full fidelity.
  - Tauri: official plugin `@tauri-apps/plugin-clipboard-manager` (v2.3.x, MIT/Apache-2.0) has `writeText` and `writeImage` (image = raw RGBA/PNG buffer, desktop only). If webview clipboard proves flaky under WebKitGTK on Linux, route clipboard through the plugin; community alternative with more formats (HTML/RTF/files/watching): `CrossCopy/tauri-plugin-clipboard` (MIT).
- Bonus (steal from Excalidraw): embed the Thalyx JSON in exported PNG (tEXt chunk) / SVG (comment or data attribute) so exported images can be re-opened as editable documents.

---

## 6. Autosave + crash recovery (Tauri)

Building blocks (all official Tauri v2 plugins, MIT/Apache-2.0):
- `@tauri-apps/plugin-fs` — `writeTextFile`, `readTextFile`, `rename`, `mkdir`, `exists`; scope-restricted to app dirs by default; `BaseDirectory.AppData` etc. must be created at runtime (`mkdir` with `recursive: true`) — the app-data dir is NOT auto-created (https://v2.tauri.app/plugin/file-system/).
- `@tauri-apps/plugin-dialog` — open/save dialogs.
- `tauri-plugin-window-state` — persists window geometry.
- `@tauri-apps/plugin-store` (key-value JSON store) — fine for preferences/recent-files list; not for documents.

Pattern to specify (matches what serious editors do):
1. **Atomic writes always**: write to `doc.thalyx.tmp` in the same directory, then `rename()` over the target (rename is atomic on the same filesystem on macOS/Linux). Never truncate-then-write the real file — a crash mid-write must not destroy the document. (Best done as a single Rust `#[tauri::command] fn save_atomic(path, contents)` using `tempfile` + `persist()`, so the fs-plugin scope juggling and fsync are handled in one place; call `f.sync_all()` before rename for durability.)
2. **Debounced autosave**: subscribe to the zustand `doc` slice; debounce 500–1000 ms after last mutation; if the doc has a file path, atomic-save in place (or to `~/.local/share/thalyx/autosave/<docId>.thalyx` if you don't want silent in-place saves); untitled docs always autosave to the recovery dir. Excalidraw does the same thing with a ~300 ms debounce into localStorage.
3. **Crash recovery journal**: keep `appDataDir()/recovery/<docId>.thalyx` + a `manifest.json` (`{docId, originalPath, savedAt, dirty}`). On clean exit (`onCloseRequested` — flush pending autosave, then delete recovery entry). On startup, if manifest has entries → "Restore unsaved changes?" prompt (the VS Code "hot exit" model).
4. **Don't lose the last good version**: before the first in-place save of a session, copy `file.thalyx` → `file.thalyx.bak` (cheap insurance, OmniGraffle-style).
5. Session state (camera per document, open tabs) → `plugin-store`, restored on launch; never mixed into the document file.

---

## 7. Testing strategy

- **Unit tests — Vitest** (MIT). Current major: **Vitest 4.0, released 2025-10-22** (https://vitest.dev/blog/vitest-4); Browser Mode is now stable, providers split into `@vitest/browser-playwright` / `@vitest/browser-webdriverio` / `@vitest/browser-preview`; built-in visual regression testing. Everything that matters most in Thalyx is a pure function and needs no DOM: document schema validation + `restoreDocument` normalizer, undo/redo semantics, **mermaid import → doc** and **doc → mermaid export (property test: import(export(doc)) preserves the edge set)**, SVG string generation (snapshot tests on `renderDocToSvg` output), geometry (anchor points, orthogonal routing). Put these in plain node-environment vitest — fast, and a weaker LLM can iterate on them locally.
- **Component/interaction tests**: **Playwright (Apache-2.0) against the web build (`vite dev`/`vite preview`) in plain Chromium** — this is the primary recommendation. The entire editor is a web app; drag-node, draw-edge, marquee-select, copy/paste, undo flows are all testable without Tauri, with mocked `window.__TAURI__` / `@tauri-apps/api` calls (or a small `platform` abstraction module with a browser fallback: localStorage saves + download-attribute exports). This keeps CI trivial (ubuntu runner, `npx playwright install chromium`).
- **Playwright cannot drive the real Tauri window on macOS/Linux**: Playwright needs CDP; only WebView2 (Windows) speaks CDP. Known workaround plugins exist (`tauri-plugin-playwright` embeds a control server) but are young — don't build the main suite on them.
- **Native E2E smoke tests (small number)**: Tauri v2's documented route is **WebdriverIO + `@wdio/tauri-service`** (https://v2.tauri.app/develop/tests/webdriver/). As of 2026 the service defaults to an **embedded WebDriver server inside the app** (optional plugins `tauri-plugin-wdio-webdriver`, `tauri-plugin-wdio`), which is how it supports **Windows, Linux AND macOS** (https://webdriver.io/docs/desktop-testing/tauri/platform-support/). The old `tauri-driver` path remains Windows/Linux-only ("macOS has no WKWebView driver tool"). Config: `npm create wdio@latest`, set `appBinaryPath`, `driverProvider: 'embedded'`. Keep this suite to launch/open-file/save/export smoke tests; run on Linux CI + macOS runner.
- Also worth one line in the plan: rendering caveat for tests — WebKitGTK (Linux Tauri) ≠ Chromium; test the web build in **both** Chromium and Playwright's WebKit to catch Safari-ish issues cheaply (Playwright ships a WebKit build).

---

## License ledger (everything evaluated)

| Package | License | OK for Unlicense project? |
|---|---|---|
| @excalidraw/excalidraw, @excalidraw/utils | MIT | yes (code + format reference) |
| tldraw / @tldraw/* (any) | tldraw license (source-available, watermark/key) | **NO — reference reading only** |
| @xyflow/react (React Flow 12) | MIT | yes — recommended base |
| zustand (pmndrs) | MIT | yes |
| zundo | MIT | yes |
| immer | MIT | yes |
| jotai / redux-toolkit | MIT | yes (not chosen) |
| zod | MIT | yes |
| svg2pdf.js (yWorks) v2.7.0 | MIT | yes |
| jsPDF | MIT | yes |
| html-to-image (pin 1.11.11) | MIT | yes (optional) |
| d3-zoom/d3-drag (via React Flow) | ISC | yes |
| Tauri + official plugins (fs, dialog, store, clipboard-manager, window-state) | MIT/Apache-2.0 | yes |
| CrossCopy/tauri-plugin-clipboard | MIT | yes (optional) |
| vitest 4 | MIT | yes |
| Playwright | Apache-2.0 | yes |
| WebdriverIO + @wdio/tauri-service | MIT | yes |
| mermaid (for parsing/round-trip; separate research topic) | MIT | yes |

## Key sources

- Excalidraw JSON schema: https://docs.excalidraw.com/docs/codebase/json-schema
- Excalidraw serialization deep-dive: https://deepwiki.com/excalidraw/excalidraw/6.2-scene-serialization-and-file-formats
- Excalidraw delta history PR: https://github.com/excalidraw/excalidraw/pull/7348 ; https://deepwiki.com/excalidraw/excalidraw/5.3-history-system
- Excalidraw export utils: https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/utils/export
- tldraw persistence/snapshots: https://tldraw.dev/docs/persistence ; store: https://tldraw.dev/reference/store/Store
- tldraw history/marks: https://tldraw.dev/sdk-features/history ; performance: https://tldraw.dev/sdk-features/performance
- tldraw license: https://tldraw.dev/community/license ; https://tldraw.dev/legal/tldraw-sdk-3-x-license
- React Flow state mgmt guidance: https://reactflow.dev/learn/advanced-use/state-management ; useStore: https://reactflow.dev/api-reference/hooks/use-store
- React Flow performance: https://reactflow.dev/learn/advanced-use/performance ; https://github.com/xyflow/xyflow/discussions/4975
- React Flow image export example: https://reactflow.dev/examples/misc/download-image ; html-to-image: https://github.com/bubkoo/html-to-image
- svg2pdf.js: https://github.com/yWorks/svg2pdf.js
- Clipboard: https://web.dev/patterns/clipboard/copy-images/ ; https://developer.chrome.com/blog/svg-support-for-async-clipboard-api
- Tauri fs plugin: https://v2.tauri.app/plugin/file-system/ ; clipboard-manager: https://v2.tauri.app/reference/javascript/clipboard-manager/
- Tauri PDF gaps: https://github.com/tauri-apps/wry/issues/707 ; https://github.com/tauri-apps/tauri/issues/12284
- Tauri testing: https://v2.tauri.app/develop/tests/webdriver/ ; https://webdriver.io/docs/desktop-testing/tauri/platform-support/
- Vitest 4: https://vitest.dev/blog/vitest-4
- zundo: https://github.com/charkour/zundo
