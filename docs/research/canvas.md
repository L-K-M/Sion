# Thalyx research — Canvas / diagram-editor library layer

Date: 2026-08-23. All npm versions/licenses verified directly against registry.npmjs.org; GitHub stats via GitHub API; package contents verified by downloading and inspecting tarballs. Thalyx constraints: public-domain (Unlicense) app → deps must be permissive (MIT/Apache/BSD/ISC preferred; weak-copyleft judged case by case; GPL/AGPL/source-available disqualified). Target: OmniGraffle-like node-and-edge editor, macOS+Linux desktop, deep Mermaid import/export, 500–2000 shapes.

---

## 1. Verified package facts (npm registry, 2026-08-23)

| Package | Latest | License | Last publish | Notes |
|---|---|---|---|---|
| `@xyflow/react` (React Flow) | 12.11.3 | MIT | 2026-08-12 | active; repo xyflow/xyflow 38,096 stars, pushed 2026-08-21 |
| `tldraw` | 5.3.2 | "SEE LICENSE IN LICENSE.md" (proprietary tldraw license) | 2026-08-18 | NOT open source — see §2.2 |
| `@excalidraw/excalidraw` | 0.18.1 | MIT | 2026-04-20 | repo 130,246 stars |
| `@excalidraw/mermaid-to-excalidraw` | 2.2.2 | MIT | 2026-03-24 | mermaid→excalidraw elements converter |
| `@joint/core` (JointJS) | 4.3.2 | MPL-2.0 | 2026-08-21 | repo clientIO/joint 5,358 stars, pushed 2026-08-21 |
| `konva` | 10.3.1 | MIT | 2026-08-15 | repo 14,709 stars |
| `pixi.js` | 8.20.0 | MIT | 2026-08-20 | 900KB min / 258KB gzip |
| `mxgraph` | 4.2.2 | Apache-2.0 | 2020-10-28 | repo jgraph/mxgraph **archived=true** — dead |
| `gojs` | 4.0.3 | proprietary ("SEE LICENSE IN license.html") | 2026-07-17 | commercial, ~$3,495–3,995/developer |
| `dagre` (original) | 0.8.5 | MIT | 2019-12-03 | dead; superseded by @dagrejs/dagre |
| `@dagrejs/dagre` | 3.1.1 | MIT | 2026-08-08 | ACTIVE. v2.0.0 2025-11-20, v3.0.0 2026-03-22, v3.1.0 2026-08-02. Ships own types (`dist/types/index.d.ts`), ESM+CJS, dep: `@dagrejs/graphlib` 4.0.5. Repo dagrejs/dagre 5,768 stars, language now TypeScript |
| `elkjs` | 0.12.0 | **EPL-2.0 OR GPL-3.0-or-later** (dual) | 2026-07-17 | repo kieler/elkjs 2,717 stars; see §4.2 |
| `d3-hierarchy` | 3.1.2 | ISC | 2022-04-02 | stable/finished, not dead |
| `d3-force` | 3.0.0 | ISC | 2021-06-05 | stable/finished |
| `mermaid` | 11.17.0 | MIT | 2026-08-19 | |
| `@mermaid-js/layout-elk` | 0.2.3 | MIT | 2026-08-19 | mermaid's optional ELK layout (wraps elkjs) |
| `@mermaid-js/parser` | 1.2.1 | MIT | 2026-08-19 | langium-based parser (newer diagram types only) |
| `@antv/x6` | 3.1.8 | MIT | 2026-08-11 | repo antvis/X6 ~6.7k stars; v3.x current |
| `@tisoap/react-flow-smart-edge` | 5.0.0 | MIT | 2026-08-16 | peerDeps `@xyflow/react >=12`; "Custom React Flow Edge that never intersects with other nodes" |
| `zundo` | 2.3.0 | MIT | 2024-11-17 | zustand undo/redo (temporal) middleware |
| `libavoid-js` | 0.5.0-beta.5 | **LGPL-2.1-or-later** | 2026-02-23 | orthogonal routing w/ obstacle avoidance — LGPL, avoid (see §4.4) |
| `fabric` | 7.4.0 | MIT | 2026-05-18 | generic canvas lib, no graph model |
| `reaflow` | 5.4.1 | Apache-2.0 | 2025-04-08 | elkjs-based React diagram lib; smaller community, less flexible than React Flow |
| `@projectstorm/react-diagrams` | 7.0.4 | MIT | 2024-02-15 | stale (no publish in ~2.5 yrs) — skip |

Measured bundle sizes (bundlephobia / tarball inspection):
- `@xyflow/react@12.11.3`: 187,099 B min / **59,797 B gzip** (bundlephobia).
- `konva@10.3.1`: 183,127 B min / **54,638 B gzip**.
- `pixi.js@8.20.0`: 900,479 B min / **257,745 B gzip**.
- `@joint/core@4.3.2`: `dist/joint.min.js` 474,163 B min / **143,989 B gzip** (measured from tarball). Types = one hand-written 182KB `joint.d.ts` (JS source, not TS).
- `elkjs@0.12.0`: `lib/elk.bundled.js` **1,609,707 B min / 469,661 B gzip**; `lib/elk-worker.min.js` 1,595,334 B (464,625 B gzip). Huge (it's GWT-transpiled Java) but irrelevant for a desktop app; MUST run in a Web Worker (API supports it out of the box).
- `@excalidraw/excalidraw@0.18.1`: `dist/prod` is **18 MB** total (fonts, locales, chunks); main `index.js` 502KB (155KB gzip) + lazy chunks.

---

## 2. Editor-library evaluations

### 2.1 React Flow — `@xyflow/react` 12.11.3 (RECOMMENDED)
- **License**: MIT (repo + npm verified). React Flow **Pro** is only a paid subscription for example code / support — the library itself is fully MIT. Docs: https://reactflow.dev
- **Model**: controlled React state — `nodes: Node[]`, `edges: Edge[]` arrays with `id/type/position/data`, edges with `source/target/sourceHandle/targetHandle`. This maps 1:1 onto mermaid's node/edge graph → trivial mermaid export (walk `edges`, emit `A --> B`), and import = build arrays + run layout. This serialization-friendliness is the single biggest fit for Thalyx.
- **Custom shapes**: first-class. Custom nodes are arbitrary React components registered via `nodeTypes={{ shape: ShapeNode }}`; custom edges via `edgeTypes`. `<Handle type="source" position={Position.Right}/>` for connection points. SVG or HTML inside nodes both fine.
- **Edge routing**: built-in edge types `default` (bezier), `straight`, `step`, `smoothstep`, `simplebezier`; exported path helpers verified in d.ts: `getBezierPath`, `getStraightPath`, `getSmoothStepPath`, `getSimpleBezierPath`. **No built-in obstacle-avoiding orthogonal routing.** Mitigations: (a) ELK computes orthogonal, obstacle-avoiding routes at layout time (`elk.edgeRouting: 'ORTHOGONAL'`, see §4.2) and React Flow custom edges can render supplied bend points; (b) `@tisoap/react-flow-smart-edge` 5.0.0 (MIT, publishes Aug 2026, peerDep `@xyflow/react >=12`) does grid A*/pathfinding edges that never cross nodes; (c) custom A* router ~300 LOC.
- **Snapping / alignment guides**: `snapToGrid` + `snapGrid` props built in. **Alignment helper lines are NOT built in** — the official "Helper Lines" example is a Pro (paid) example (https://reactflow.dev/examples/interaction/helper-lines), so Thalyx must implement its own (well-understood: on `onNodeDrag`, compare dragged node bounds to other node bounds, render guide lines in a `<ViewportPortal>`; several OSS implementations exist to reference).
- **Multi-select / groups / resize / rotate**: multi-select built in (`selectionKeyCode` default Shift drag-box, `multiSelectionKeyCode` Meta/Ctrl click, `selectionOnDrag`, `selectionMode: 'partial'|'full'`). Grouping via `parentId` + `extent: 'parent'` (subflows) built in. **`<NodeResizer/>` built in** (verified export along with `NodeToolbar`, `EdgeToolbar`, `MiniMap`, `Background`, `Controls`, `Panel`, `ViewportPortal`). **Rotation NOT built in** — free example "Rotatable Node" (https://reactflow.dev/examples/nodes/rotatable-node) shows CSS-transform rotation; full OmniGraffle-style rotate handles = DIY.
- **Text editing on shapes**: trivial — nodes are React components, so a double-click → `<textarea>`/contentEditable swap inside the node. No library support needed.
- **Undo/redo**: **not built in**. Official "Undo and Redo" example is Pro-only (snapshot-based `useUndoRedo`/`takeSnapshot` hook). DIY is straightforward because state is plain arrays: keep past/future stacks of `{nodes, edges}` snapshots, or use `zundo` 2.3.0 (MIT, zustand temporal middleware). This is a deliberate implementation task, not a blocker.
- **Performance / virtualization**: DOM/SVG-based. `onlyRenderVisibleElements` prop (default false) = built-in viewport virtualization. Official perf guidance (https://reactflow.dev/learn/advanced-use/performance): memoize node/edge components with `React.memo`, `useCallback` handlers, avoid subscribing to the whole `nodes` array, avoid heavy CSS (shadows/gradients/animations). Maintainer statement in xyflow discussion #3003: "React Flow is not intended to be used at 1000+ node scales, though this really depends on the complexity of your nodes." Community consensus: fine to ~500–1000 simple memoized nodes; 2000 requires virtualization + zoom-based LOD (swap complex nodes for cheap placeholders below zoom ~0.5). For OmniGraffle-class documents (typically <500 shapes) this is acceptable; 2000-shape stress case is workable but is the main engineering risk — see recommendation.
- **TypeScript**: excellent; written in TS, generics for node data (`Node<MyData>`), `useNodesState`, `useReactFlow`, `useKeyPress`, `useOnSelectionChange`, `getNodesBounds`, `getViewportForBounds` (last two useful for PNG/SVG export via html-to-image).
- **Bundle**: 60KB gzip. **Maintenance**: very active (12.11.3 on 2026-08-12; 130 open issues on 38k-star repo; backed by commercial Pro subscriptions — sustainable funding model without license restrictions).
- **Extensibility**: the whole editor chrome is yours; React Flow only owns pan/zoom (d3-zoom), selection, drag, and rendering pipeline.

### 2.2 tldraw SDK 5.3.2 — DISQUALIFIED (license)
- npm license field: "SEE LICENSE IN LICENSE.md". Official terms (https://tldraw.dev/community/license): **not open source**; default use "permits use only in development". Production requires one of: Trial (100 days, license key, pings tldraw servers), **Hobby license (non-commercial, license key required, "the 'made with tldraw' watermark must be shown on the canvas")**, or paid Commercial license. Critically for Thalyx: "Open source projects can use tldraw, but you and your downstream users will require their own trial, commercial, or hobby license." The SDK "will not work in production without a valid license key."
- Verdict: fundamentally incompatible with a public-domain app. Do not use, regardless of technical quality.

### 2.3 Excalidraw — `@excalidraw/excalidraw` 0.18.1, MIT
- **License**: MIT (verified). Embeddable React component: `<Excalidraw initialData={...} excalidrawAPI={(api)=>...} onChange={...} viewModeEnabled gridModeEnabled theme .../>`; imperative API `api.updateScene()`, `api.getSceneElements()`; utility `convertToExcalidrawElements()` builds full elements from "skeletons". Docs: https://docs.excalidraw.com/docs/@excalidraw/excalidraw/api/props
- **Nature**: it is a complete whiteboard *application* you embed, not an engine you build on. UI customization is limited (UIOptions, render-prop slots); you'd be skinning Excalidraw, not building Thalyx's own OmniGraffle-like UX.
- **Custom shapes**: **fixed element-type set** (rectangle, diamond, ellipse, arrow, line, freedraw, text, image, frame, embeddable...). No API for new shape types — longstanding request, e.g. issue #5798 "How to add custom shape type?" — requires forking. Disqualifying for OmniGraffle-style stencils/high-fidelity shapes.
- **Edge routing**: straight + curved arrows with element binding (`startBinding`/`endBinding`, `boundElements`); **elbow (orthogonal) arrows** added via PR #8299 (Dijkstra + Manhattan-distance+bend-count heuristic; avoids the bound elements, not global obstacle avoidance; refined in PR #8952). Engineering write-ups: https://plus.excalidraw.com/blog/building-elbow-arrows-part-one (useful as an implementation reference for Thalyx's own router even if Excalidraw isn't used).
- **Editor features**: undo/redo, text editing (incl. bound container text), multi-select, groups, resize/rotate, snapping — all built in (it's a finished app). Performance: canvas-based, handles thousands of elements well.
- **Mermaid**: `@excalidraw/mermaid-to-excalidraw` 2.2.2 (MIT): `parseMermaidToExcalidraw(diagramDefinition, config) => { elements, files }` then `convertToExcalidrawElements(elements)`. Tarball inspection shows native converters for **flowchart, sequence, class, ER, state** (docs page claiming "only flowcharts" is stale); unsupported types fall back to a rendered image. Config: `flowchart.curve`, `themeVariables.fontSize`, `maxEdges` (default 500), `maxTextSize`.
- Verdict: not the right engine (no custom shapes, app-not-library), but **the best prior art**: steal the elbow-arrow algorithm design and the mermaid→elements conversion architecture. Its `mermaid-to-excalidraw` source is the reference implementation for Thalyx's mermaid import (it drives mermaid's parser to get the graph DB, then emits element skeletons).

### 2.4 JointJS — `@joint/core` 4.3.2, MPL-2.0 — best-in-class routing, but rejected
- **License**: MPL-2.0 (file-level weak copyleft). Per Apache Software Foundation policy (https://www.apache.org/legal/resolved.html) MPL-2.0 is **Category B**: may be included in binary form with labeling. So *legally usable* as an unmodified dep of a public-domain app, but any modifications to JointJS files must be published under MPL — friction for a public-domain project.
- **Routing (its killer feature, all in the FREE core)**: routers `'manhattan'` (orthogonal **with obstacle avoidance**; options verified from docs: `step` default 10, `padding`, `maximumLoops` default 2000, `maxAllowedDirectionChange` 90, `perpendicular`, `excludeEnds`, `excludeTypes`, `startDirections`, `endDirections`, `isPointObstacle`, `fallbackRouter`), `'metro'` (octolinear, also obstacle-avoiding), `'orthogonal'`, `'rightAngle'`, `'normal'`. Docs: https://docs.jointjs.com/api/routers/
- **BUT — paywall on editor UX**: verified by grepping the `@joint/core` 4.3.2 tarball: **no `CommandManager`, no `Snapline`** in the shipped dist. Undo/redo (`dia.CommandManager`), snaplines, stencil palette, halo (resize/rotate handles), inline text editor (`ui.TextEditor`), keyboard, clipboard are all **JointJS+ (commercial, `@joint/plus`, not on public npm)**. Confirmed by jointjs.com marketing: "Advanced editing features — undo/redo, clipboard, multi-select, snaplines — and UI components like the stencil and halo ship in JointJS+."
- **Custom shapes**: good (`dia.Element.define('thalyx.Box', {...}, { markup: [...] })`, SVG markup + attrs system). TypeScript: hand-written d.ts over JS source — OK but not TS-native. 144KB gzip. Backbone-style MVC (Backbone dependency removed in v4 but API style remains); mediocre React integration (`@joint/react` exists, new in 2025).
- Verdict: you'd re-implement all the JointJS+ features anyway (that's most of Thalyx's UX layer) on an MPL base with a company whose business model is selling exactly those features. Take its manhattan-router *design* as reference; don't build on it. (Also note: JointJS demo "Standalone Link Routing with Libavoid" — clientIO/joint discussion #2627 — confirms even they treat libavoid as the high-end router, but libavoid is LGPL.)

### 2.5 AntV X6 — `@antv/x6` 3.1.8, MIT — strong runner-up
- **License**: MIT core AND MIT plugins (all verified on npm): `x6-plugin-snapline` 2.1.7, `x6-plugin-history` 2.2.4 (undo/redo), `x6-plugin-selection` 2.2.2 (rubberband multi-select), `x6-plugin-transform` 2.1.8 (resize+rotate handles), `x6-plugin-clipboard`, `x6-plugin-keyboard`, `x6-plugin-dnd`, `x6-plugin-minimap`, `x6-plugin-export`, `@antv/x6-react-shape` 3.0.1 (2025-11-27).
- **Features**: SVG-based graph editing engine (Alipay/AntV); JointJS-inspired: built-in routers incl. `manhattan` (obstacle-avoiding orthogonal), `orth`, `er`, `metro`; ports; grouping/embedding; node/edge tools incl. `node-editor`/`edge-editor` (inline text editing); snaplines; history — i.e., the ONLY MIT library where orthogonal obstacle-avoiding routing AND snaplines AND undo/redo AND resize/rotate are all free out of the box.
- **Concerns**: docs primarily Chinese (English at https://x6.antv.antgroup.com/en/ is partial; GitHub issue #3605 requesting full English site); Western community small (~6.7k stars); plugins last published 2023–2024 while core moved to 3.x in 2026 (version skew risk — "Upgrade to 3.x" guide exists: https://x6.antv.antgroup.com/en/tutorial/update); far less LLM-training/StackOverflow coverage than React Flow — a real drawback given a weaker LLM implements the plan.
- Verdict: technically the most feature-complete permissive option; strategically riskier (docs language, ecosystem, plugin maintenance). Solid fallback if React Flow's DIY routing/snapline work is deemed too costly.

### 2.6 Konva 10.3.1 (MIT) / PixiJS 8.20.0 (MIT) / Fabric 7.4.0 (MIT) — custom-engine bases, not editors
- **Konva**: HTML5 2D-canvas scene graph with hit-testing, drag-and-drop, layers, caching, `Konva.Transformer` (built-in multi-node resize/rotate handles with `enabledAnchors`, `rotateEnabled`, `boundBoxFunc`), events. `react-konva` available. 55KB gzip, very active (10.3.1, 2026-08-15). No graph/edge model, no routing, no snapping (DIY), text editing = position an HTML textarea over the stage (documented pattern). Canvas rendering → easily 2000+ shapes at 60fps with layer caching; needs custom accessibility/text handling. Best base if Thalyx later outgrows DOM performance.
- **PixiJS**: WebGL/WebGPU renderer, 258KB gzip, v8 active. Massive perf headroom (10k+ sprites), but zero editor semantics — everything (selection, handles, text, routing, export) is DIY; text rendering is texture-based (blurry on zoom unless SDF/managed). Overkill/wrong altitude for v1.
- **Fabric**: object-model canvas lib with selection/transform built in, but oriented at design canvases, no edge/connector model; skip.
- Custom engine effort estimate: selection+handles+snapping+text+undo+routing+persistence ≈ months of work before feature-parity with React-Flow-day-1. Only justified at >2000-shape requirements.

### 2.7 mxGraph / drawio — DISQUALIFIED (dead / not a library)
- `mxgraph` 4.2.2 Apache-2.0, last publish 2020-10-28, **GitHub repo archived** (verified `archived: true`). jgraph/drawio itself is Apache-2.0 source but the README states it's "a diagramming and whiteboarding application", team does "not accept pull requests", and it is not offered as an embeddable library. The community TypeScript fork `maxGraph` exists but is a small effort; not competitive with React Flow's ecosystem. Skip.

### 2.8 GoJS 4.0.3 — DISQUALIFIED (proprietary)
- Commercial, license.html EULA, ~$3,495–3,995 per developer (nwoods.com/sales). Technically excellent (built-in AvoidsNodes routing, layouts) but impossible in a public-domain project. Skip.

---

## 3. Feature matrix (permissively-licensed finalists)

| Criterion | React Flow 12 (MIT) | AntV X6 3 (MIT) | @joint/core 4 (MPL) | Excalidraw (MIT) | Konva custom (MIT) |
|---|---|---|---|---|---|
| Custom shapes | ★★★ React components | ★★★ SVG/HTML/React | ★★★ SVG markup | ✗ fixed set | ★★★ DIY |
| Orthogonal + obstacle avoidance | DIY / ELK routes / smart-edge pkg | ★★★ built-in `manhattan` | ★★★ built-in `manhattan` | elbow arrows (local avoidance only) | DIY |
| Snap + alignment guides | grid yes; guides DIY (Pro example) | ★★★ snapline plugin MIT | JointJS+ paywall | built-in | DIY |
| Multi-select/groups/resize/rotate | ★★☆ (rotate DIY) | ★★★ plugins | halo = paywall | built-in | Transformer built-in |
| Text editing on shapes | ★★★ (React) | ★★☆ node-editor tool | paywall (ui.TextEditor) | built-in | HTML overlay pattern |
| Undo/redo | DIY (zundo/snapshots) | ★★★ history plugin MIT | paywall (CommandManager) | built-in | DIY |
| 500–2000 shapes | OK with `onlyRenderVisibleElements`+memo+LOD; strained ≥1000 complex | similar (SVG DOM) | similar (SVG DOM) | good (canvas) | ★★★ (canvas) |
| Virtualization | built-in prop | partial | manual | n/a | manual culling |
| TS quality | ★★★ TS-native, generics | ★★☆ TS-native | ★☆ hand-written d.ts | ★★★ | ★★★ |
| Ecosystem/docs/LLM-familiarity | ★★★ (best by far) | ★☆ (Chinese-first) | ★★☆ | ★★★ | ★★★ |
| Bundle (gzip) | 60KB | ~150KB+plugins | 144KB | 155KB+18MB assets | 55KB |
| 2025–26 activity | weekly releases | core active, plugins 2023-24 | active | active | active |

---

## 4. Layout engines for auto-layout of imported mermaid graphs

### 4.1 `@dagrejs/dagre` 3.1.1 — MIT — ALIVE and recommended as secondary
- Original `dagre` npm package is dead (0.8.5, 2019); **`@dagrejs/dagre` is actively maintained**: v1.1.5 2025-06-17 → v2.0.0 2025-11-20 (build modernization, added `dagre.esm.js` ES module) → **v3.0.0 2026-03-22 → 3.1.1 2026-08-08**; repo now TypeScript with shipped types. dagre README: "Use @dagrejs/dagre — only the one in the DagreJS org is receiving updates."
- Sugiyama layered layout; API: `const g = new dagre.graphlib.Graph(); g.setGraph({rankdir:'TB', nodesep:50, ranksep:50}); g.setNode(id,{width,height}); g.setEdge(a,b); dagre.layout(g); g.node(id).x/.y; g.edge(a,b).points`. Synchronous, fast, tiny (deps: `@dagrejs/graphlib` only). Edge `points` are polyline bend points (not orthogonal, no obstacle avoidance). This is what mermaid itself uses by default (via `dagre-d3-es`), so dagre layout ≈ what users expect a mermaid flowchart to look like.

### 4.2 `elkjs` 0.12.0 — EPL-2.0 OR GPL-3.0-or-later — ACCEPTABLE, recommended as primary
- Java ELK (Eclipse Layout Kernel) transpiled to JS. Algorithms: **layered** (flagship, Sugiyama with ports), stress, mrtree, radial, force, disco, box, fixed, random. Async promise API; **Web Worker support built in** (`new ELK({ workerUrl: '.../elk-worker.min.js' })`, or `elk.bundled.js` on-thread). `elk.layout(graphJson)` where graph = `{id, layoutOptions, children:[{id,width,height}], edges:[{id,sources,targets}]}`.
- **Killer feature vs dagre**: `org.eclipse.elk.edgeRouting` option, values `POLYLINE | ORTHOGONAL | SPLINES` (verified: https://eclipse.dev/elk/reference/options/org-eclipse-elk-edgeRouting.html), supported by ELK Layered — i.e. the layout engine itself returns **orthogonal, obstacle-respecting edge routes with bend points**, plus port constraints, `elk.hierarchyHandling: 'INCLUDE_CHILDREN'` for nested/group layout. Mermaid ships `@mermaid-js/layout-elk` (MIT wrapper) as its high-quality renderer option — so ELK layouts match "mermaid with elk renderer" output.
- **License analysis (the EPL-2.0 question)**: package is **dual-licensed `EPL-2.0 OR GPL-3.0-or-later`** — Thalyx takes the EPL-2.0 arm. EPL-2.0 is *weak, file/module-level* copyleft: obligations are to retain notices, include the license text, and keep source of the EPL'd module itself available (it's public on GitHub/npm); it does NOT infect the app that merely depends on and bundles it. Precedents: Apache Software Foundation policy (apache.org/legal/resolved.html) classifies **EPL-1.0/2.0 as Category B — "may include software under the following licenses in binary form within an Apache product if you label the inclusion appropriately"**; MIT-licensed mermaid depends on elkjs for `@mermaid-js/layout-elk`. Conclusion: **acceptable as an unmodified npm dependency of a public-domain app**, provided Thalyx (a) never vendors/modifies elkjs source in-tree, (b) ships the EPL-2.0 text + attribution in an About/licenses screen (a THIRD_PARTY_LICENSES file), (c) keeps Thalyx's own code Unlicense. If maximal license purity is ever demanded, the fallback is dagre-only (MIT) at some quality cost.
- Size: 1.6MB min / 470KB gzip — fine for a desktop app; load in worker to avoid jank (layout of ~1000 nodes can take hundreds of ms).

### 4.3 `d3-hierarchy` 3.1.2 / `d3-force` 3.0.0 — ISC — niche roles
- Stable, finished libraries (Observable/Bostock; no updates needed). `d3-hierarchy` (`d3.tree()`, `d3.cluster()`) only fits trees — useful for mermaid `mindmap` import. `d3-force` for undirected/organic graphs — possible fallback for mermaid `graph`s with cycles/no hierarchy, and mermaid uses a force-ish approach for mindmaps. Not suitable as the primary flowchart layout (no layering, no edge routing). Keep as optional per-diagram-type engines.

### 4.4 Rejected routing/layout deps
- `libavoid-js` 0.5.0-beta.5: best-in-class incremental connector routing (from adaptagrams), but **LGPL-2.1-or-later** — Apache Category X ("may NOT be included"); for a public-domain desktop app that statically bundles JS, LGPL relink obligations are murky. AVOID.
- `dagre-d3` / `dagre-d3-es`: rendering layer for dagre, not needed (React Flow renders).
- Graphviz-wasm (`@hpcc-js/wasm`, Apache-2.0) — viable alternative orthogonal router (`splines=ortho`), heavier and less JSON-friendly than ELK; not needed but note as plan-B.

---

## 5. Firm recommendation

**Editor layer: React Flow (`@xyflow/react` ^12.11.3, MIT).** Rationale: best-in-class ecosystem/docs (38k stars, weekly releases, enormous example corpus — maximally friendly to a weaker implementing LLM), MIT with zero strings, React-component custom nodes give OmniGraffle-fidelity shapes + trivial in-shape text editing, controlled `nodes`/`edges` arrays are effectively already the mermaid logical model (making mermaid import/export the thinnest layer possible), built-in `NodeResizer`, subflow grouping, multi-select, snap-to-grid, minimap, and `onlyRenderVisibleElements` virtualization. tldraw is license-disqualified; GoJS commercial; mxGraph dead; Excalidraw can't do custom shapes; JointJS paywalls undo/snaplines/halo on an MPL core; X6 is the only serious rival but loses on documentation language, plugin staleness, and community depth.

**Accepted DIY work under React Flow (bounded, well-trodden):** (1) undo/redo via snapshot stacks or `zundo` (MIT); (2) alignment helper lines (~200 LOC `onNodeDrag` bounds comparison + `<ViewportPortal>` overlay); (3) rotation handles if wanted (free Rotatable Node example as base); (4) interactive orthogonal edge routing: render ELK-computed `ORTHOGONAL` routes after layout/import, use `smoothstep` or `@tisoap/react-flow-smart-edge` 5.0.0 (MIT, v12-compatible) during hand editing, with JointJS's documented manhattan-router option set and Excalidraw's elbow-arrow blog posts as reference designs for a later custom A* router.

**Layout layer: elkjs ^0.12.0 (EPL-2.0 arm of dual license) as primary, in a Web Worker, using `elk.layered` + `elk.edgeRouting: 'ORTHOGONAL'` + port constraints for mermaid flowchart/state/class import; `@dagrejs/dagre` ^3.1.1 (MIT) as the lightweight/synchronous secondary** (matches mermaid's default look; also the safety net if EPL is ever re-judged). Optional: `d3-hierarchy` (ISC) for mindmap/tree layouts. EPL-2.0 as unmodified binary dependency is compatible with a public-domain app (Apache Category B precedent; mermaid itself depends on elkjs) — record attribution in THIRD_PARTY_LICENSES and do not vendor/patch its source.

**Explicitly rejected**: tldraw (proprietary source-available; production requires license key; watermark for hobby tier; each downstream user needs own license), GoJS (commercial $3.5–4k/dev), mxGraph/drawio (archived / app-not-library), libavoid-js (LGPL), JointJS+ (commercial), building a custom Konva/Pixi engine for v1 (months of undifferentiated work; revisit only if >2000-shape perf becomes a hard requirement — Konva 10 + `Konva.Transformer` is the designated escape hatch, and React Flow state arrays would port cleanly).

## 6. Key implementation snippets (verified API names)

```ts
// React Flow minimal editor surface
import { ReactFlow, Background, Controls, MiniMap, NodeResizer, Handle, Position,
         useNodesState, useEdgesState, addEdge, getSmoothStepPath,
         type Node, type Edge } from '@xyflow/react';
import '@xyflow/react/dist/style.css';
// <ReactFlow nodes={nodes} edges={edges} nodeTypes={nodeTypes} edgeTypes={edgeTypes}
//   onNodesChange={onNodesChange} onEdgesChange={onEdgesChange} onConnect={onConnect}
//   snapToGrid snapGrid={[8,8]} selectionOnDrag onlyRenderVisibleElements fitView />

// ELK layout with orthogonal routed edges (run in worker)
import ELK from 'elkjs/lib/elk-api';
const elk = new ELK({ workerUrl: new URL('elkjs/lib/elk-worker.min.js', import.meta.url).href });
const res = await elk.layout({
  id: 'root',
  layoutOptions: { 'elk.algorithm': 'layered', 'elk.direction': 'DOWN',
    'elk.edgeRouting': 'ORTHOGONAL', 'elk.layered.spacing.nodeNodeBetweenLayers': '60' },
  children: nodes.map(n => ({ id: n.id, width: n.width ?? 150, height: n.height ?? 48 })),
  edges: edges.map(e => ({ id: e.id, sources: [e.source], targets: [e.target] })),
});
// res.children[i].x/.y -> node.position; res.edges[i].sections[0].bendPoints -> custom edge path

// dagre fallback (synchronous)
import * as dagre from '@dagrejs/dagre';
const g = new dagre.graphlib.Graph().setGraph({ rankdir: 'TB', nodesep: 40, ranksep: 60 });
nodes.forEach(n => g.setNode(n.id, { width: 150, height: 48 }));
edges.forEach(e => g.setEdge(e.source, e.target));
dagre.layout(g); // then g.node(id).x/.y (center coords)

// Mermaid import prior art (MIT): @excalidraw/mermaid-to-excalidraw
import { parseMermaidToExcalidraw } from '@excalidraw/mermaid-to-excalidraw';
const { elements, files } = await parseMermaidToExcalidraw(mermaidText, { flowchart: { curve: 'linear' } });
// native converters exist for: flowchart, sequence, class, ER, state (verified in v2.2.2 dist)
```

Primary sources: reactflow.dev/api-reference/react-flow; reactflow.dev/learn/advanced-use/performance; github.com/xyflow/xyflow (disc. #3003, #4975); tldraw.dev/community/license; docs.jointjs.com/api/routers/; jointjs.com (JointJS+ feature split); github.com/kieler/elkjs; eclipse.dev/elk/reference/options/org-eclipse-elk-edgeRouting.html; apache.org/legal/resolved.html; github.com/dagrejs/dagre; docs.excalidraw.com; github.com/excalidraw/excalidraw PR #8299, issue #5798; github.com/antvis/X6 (+issue #3605); x6.antv.antgroup.com/en; nwoods.com/sales (GoJS); npm registry (versions/licenses/dates, retrieved 2026-08-23).
