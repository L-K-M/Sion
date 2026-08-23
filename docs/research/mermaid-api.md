# Mermaid programmatic integration — research notes (2026-08-23)

All claims below were **empirically verified** by installing packages from npm (Node v22.22.2)
and running scripts in `/tmp/claude-0/-home-user-Thalyx/3bad5ff7-67a8-5ccd-8261-d90eb98fb882/scratchpad/research/mermaid-lab/`
(test scripts `test-*.mjs` kept there), except where a source URL is given.

---

## 1. Versions, license, cadence

| Package | Verified version (2026-08-23) | License | Notes |
|---|---|---|---|
| `mermaid` | **11.17.0** (published 2026-08-19) | **MIT** | dist-tags: latest=11.17.0, backport=10.9.8 |
| `@mermaid-js/parser` | **1.2.1** | MIT | Langium-based; ESM-only (`"type":"module"`, export `./dist/mermaid-parser.core.mjs`) |
| `@mermaid-js/layout-elk` | **0.2.3** | MIT | peerDep `mermaid: ^11.0.2` |
| `@mermaid-js/layout-tidy-tree` | **0.2.2** | MIT | newer layout addon, peerDep `mermaid: ^11.0.2` |
| `@mermaid-js/mermaid-cli` | **11.16.0** | MIT | peerDep `puppeteer ^23 || ^24 || ^25` (still browser-based rendering) |
| `mermaid-isomorphic` | 3.1.0 | MIT | Node rendering via **Playwright** (peerDep `playwright: 1`) |
| `beautiful-mermaid` | 1.1.3 | MIT | zero-DOM parse + sync SVG/ASCII render (Luki Labs / Craft), https://github.com/lukilabs/beautiful-mermaid |
| `@excalidraw/mermaid-to-excalidraw` | 2.2.2 | MIT | prior art for mermaid→editable-canvas import |

Release cadence (from `npm view mermaid time`): roughly **monthly minor releases**:
11.9.0 2025-07-16, 11.10.0 2025-08-19, 11.11.0 2025-09-04, 11.12.0 2025-09-18,
11.12.3 2026-02-17, 11.13.0 2026-03-09, 11.14.0 2026-04-01, 11.15.0 2026-05-11,
11.16.0 2026-06-25, 11.16.1 2026-08-04, **11.17.0 2026-08-19**. Repo: https://github.com/mermaid-js/mermaid

Registered diagram ids in mermaid 11.17.0 — `mermaid.getRegisteredDiagramsMetadata().map(d=>d.id)` (40 total):
`error, ---, flowchart-elk, mindmap, architecture, c4, kanban, classDiagram, class, er, gantt, info, pie, requirement, sequence, swimlane, flowchart-v2, flowchart, timeline, gitGraph, stateDiagram, state, journey, quadrantChart, sankey, packet, xychart, block, eventmodeling, treeView, radar, ishikawa, treemap, railroad, railroadEbnf, railroadAbnf, railroadPeg, venn, wardley, cynefin`.

---

## 2. Parsing mermaid text → machine-readable graph (mermaid core)

### 2.1 Public API surface (verified exports of `mermaid` default export)

```
startOnLoad, mermaidAPI, parse, render, init, run, registerExternalDiagrams,
registerLayoutLoaders, initialize, parseError, contentLoaded, setParseErrorHandler,
detectType, registerIconPacks, getRegisteredDiagramsMetadata
```

### 2.2 `mermaid.parse(text, parseOptions?)` — validation + type detection

```js
const r = await mermaid.parse('flowchart TD\n A[Start] --> B{Decide}');
// => { diagramType: 'flowchart-v2', config: {} }   (config = frontmatter config)
const bad = await mermaid.parse('flowchart TD\n A -->', { suppressErrors: true });
// => false   (instead of throwing)
```
Docs: https://mermaid.js.org/config/usage.html — `ParseOptions.suppressErrors: boolean`;
returns `ParseResult { diagramType }` or throws (or `false` with suppressErrors).

### 2.3 `mermaid.mermaidAPI.getDiagramFromText(text)` — THE import workhorse

Returns a `Diagram` object: `{ type, db, parser, renderer, text }`. `diagram.db` is the
populated per-diagram database. **This is exactly what `@excalidraw/mermaid-to-excalidraw` uses**
(docs: https://docs.excalidraw.com/docs/@excalidraw/mermaid-to-excalidraw/codebase/parser/flowchart —
they call `getDiagramFromText`, then `diagram.parser.yy.getVertices() / getEdges() / getSubGraphs()`;
`parser.yy` is the same object as `diagram.db`).

**GOTCHA (verified):** calling `mermaidAPI.getDiagramFromText()` before any `mermaid.parse()`/render
throws `UnknownDiagramError: No diagram type detected...` because diagram definitions are lazy-loaded.
Fix — eagerly register all built-ins once at startup:

```js
await mermaid.registerExternalDiagrams([], { lazyLoad: false });
```
(alternatively `await mermaid.parse(text)` first; it loads the needed diagram).

### 2.4 Flowchart db (`FlowDB` class — methods live on the prototype, not own-props)

Full verified method list (mermaid 11.17.0):
`sanitizeText, setDiagramId, lookUpDomId, addVertex, addSingleLink, addLink, updateLinkInterpolate,
updateLink, addClass, setDirection, setClass, setTooltip, setClickFun, setLink, getTooltip,
setClickEvent, bindFunctions, getDirection, getVertices, getEdges, getClasses, clear, defaultStyle,
addSubGraph, getSubGraphs, firstGraph, destructLink, getData, ...`

Verified dump for
```
flowchart LR
 A[Start] --> B{Decide}
 B -->|yes| C(Done)
 B -.->|no| D[[Redo]]
 subgraph S1[Group]
   C
   D
 end
 classDef hot fill:#f96
 class C hot
 A:::hot
```

- `db.getDirection()` → `'LR'` (**note:** `flowchart TD` normalizes to `'TB'`)
- `db.getVertices()` → **`Map<string, FlowVertex>`** (a Map, not object — `JSON.stringify` shows `{}`!):
  ```json
  ["A", {"id":"A","labelType":"text","domId":"flowchart-A-0","styles":[],"classes":["hot"],
         "text":"Start","type":"square","props":{}}]
  ["B", {... "text":"Decide","type":"diamond"}]
  ["C", {... "text":"Done","type":"round","classes":["hot"]}]
  ["D", {... "text":"Redo","type":"subroutine"}]
  ```
  Shape names in `type`: `square` `[]`, `round` `()`, `stadium` `([])`, `subroutine` `[[]]`,
  `cylinder` `[()]`, `circle` `(())`, `diamond` `{}`, `hexagon` `{{}}`, `odd` `>]`,
  `lean_right`/`lean_left`/`trapezoid`/`inv_trapezoid`, `doublecircle` `((()))`.
  v11.3+ `@{ shape: ..., label: ... }` syntax: `A@{ shape: cyl, label: "Database" }` →
  vertex `type: 'cyl'` (new-style shape names pass through, e.g. `cyl`, `diam`).
- `db.getEdges()` → array (has extra props `defaultStyle`/`defaultInterpolate` when `linkStyle default` used):
  ```json
  {"start":"A","end":"B","type":"arrow_point","text":"","labelType":"text","classes":[],
   "isUserDefinedId":false,"stroke":"normal","length":1,"id":"L_A_B_0"}
  ```
  Verified edge vocabulary:
  | syntax | type | stroke |
  |---|---|---|
  | `-->` | `arrow_point` | `normal` |
  | `---` | `arrow_open` | `normal` |
  | `-.->` | `arrow_point` | `dotted` |
  | `==>` | `arrow_point` | `thick` |
  | `--o` | `arrow_circle` | `normal` |
  | `--x` | `arrow_cross` | `normal` |
  | `<-->` | `double_arrow_point` | `normal` |
  | `o--o` | `double_arrow_circle` | `normal` |
  | `x--x` | `double_arrow_cross` | `normal` |
  | `~~~` | `arrow_open` | `invisible` |
  | `--->` | length: 2 (extra dash = +1) |
  | `e1@-->` | `id:"e1", isUserDefinedId:true` (v11.6+ edge ids) |
  Auto edge id format: `L_${start}_${end}_${counter}`.
- `db.getSubGraphs()` → `[{"id":"S1","nodes":["C","D"],"title":"Group","classes":[],"labelType":"text"}]`
  — with `direction LR` inside: adds `"dir":"LR"`.
- `db.getClasses()` → `Map`: `{"hot":{"id":"hot","styles":["fill:#f96"],"textStyles":[]}}`
- **Styling IS recoverable** (verified): `style A fill:#f9f,stroke:#333` → `vertex.styles:["fill:#f9f","stroke:#333"]`;
  `linkStyle 0 stroke:#ff3,stroke-width:4px` → `edge.style:["stroke:#ff3","stroke-width:4px","fill:none"]`;
  `click A href "https://example.com" "tooltip here"` → `vertex.link:"https://example.com/"`, `db.getTooltip('A')` → `"tooltip here"`.
- `db.getData()` — **unified render-model** (v11 unified rendering pipeline), returns
  `{ nodes, edges, other, config }` with fully resolved styling — richer than getVertices for import:
  ```json
  node: {"id":"A","label":"A","labelType":"text","padding":15,"cssStyles":[],"cssCompiledStyles":[],
         "cssClasses":"default ","look":"classic","isGroup":false,"shape":"squareRect"}
  edge: {"id":"L_A_B_0","start":"A","end":"B","type":"arrow_point","label":"go","labelpos":"c",
         "thickness":"normal","minlen":1,"arrowTypeStart":"none","arrowTypeEnd":"arrow_point",
         "pattern":"normal","curve":"basis"}
  ```
  Subgraphs appear in `getData().nodes` as `{"id":"S1","isGroup":true,"shape":"rect","dir":"LR",...}`.

### 2.5 Other diagram dbs (all verified on 11.17.0 via `getDiagramFromText(...).db`)

- **sequence** (`type:'sequence'`): `getActors()` → Map of
  `{name, description, type:'participant'|'actor', prevActor, nextActor, links, properties}`;
  `getMessages()` → `[{id,from,to,message,wrap,type,activate,placement?}]` where `type` is the
  numeric `LINETYPE` enum (extracted from dist):
  ```js
  LINETYPE = { SOLID:0, DOTTED:1, NOTE:2, SOLID_CROSS:3, DOTTED_CROSS:4, SOLID_OPEN:5,
    DOTTED_OPEN:6, LOOP_START:10, LOOP_END:11, ALT_START:12, ALT_ELSE:13, ALT_END:14,
    OPT_START:15, OPT_END:16, ACTIVE_START:17, ACTIVE_END:18, PAR_START:19, PAR_AND:20,
    PAR_END:21, RECT_START:22, RECT_END:23, SOLID_POINT:24, DOTTED_POINT:25 };
  PLACEMENT = { LEFTOF:0, RIGHTOF:1, OVER:2 };
  ```
  Also: `getBoxes, getCreatedActors, getDestroyedActors, getActorKeys, showSequenceNumbers`.
- **classDiagram**: `getClasses()` → Map (`{label, members:[...], ...}` — members are objects with `.id`
  like `"String name"`), `getRelations()` →
  `[{id1:"Animal",id2:"Dog",relation:{type1:1,type2:'none',lineType:0},relationTitle1,relationTitle2}]`,
  plus `getNotes, getNamespaces, getDirection, getData`.
- **stateDiagram-v2** (`type:'stateDiagram'`): `getRootDocV2()` → nested stmt tree
  `{id:'root',doc:[{stmt:'relation',state1:{id:'root_start',start:true},state2:{id:'Idle'}},
  {stmt:'relation',state1:{id:'Idle'},state2:{id:'Busy'},description:'work'},...]}`;
  also `getStates, getRelations, getClasses, getData`.
- **er**: `getEntities()` → Map keyed by name; `getRelationships()` →
  `[{entityA:'entity-CUSTOMER-0',roleA:'places',entityB:'entity-ORDER-1',
     relSpec:{cardA:'ZERO_OR_MORE',relType:'IDENTIFYING',cardB:'ONLY_ONE'}}]`; `getDirection, getData`.
- **pie**: `getSections, getShowData`; **gantt**: `getTasks, getSections, getDateFormat, getExcludes, getLinks`;
  **mindmap**: `getMindmap` (tree), `getData`; **timeline**: `getSections, getTasks`;
  **journey**: `getSections, getTasks, getActors`; **quadrantChart**: `getQuadrantData`;
  **xychart**: `getXYChartData, getDrawableElem`; **C4**: `getC4ShapeArray, getBoundaries, getRels`;
  **block**: `getBlocks, getBlocksFlat, getEdges, getColumns`; **kanban**: `getSections, getData`;
  **sankey**: `getNodes, getLinks, getGraph`; **gitGraph**: `getCommits` (Map), `getBranchesAsObjArray,
  getCurrentBranch, getDirection`; **architecture**: `getServices, getJunctions, getGroups, getEdges,
  getNodes, getLayoutHints`.
  → **Every built-in diagram type exposes a usable db**; flowchart/sequence/class/state/er are the
  richest and are the ones Thalyx should support for editable import first.

### 2.6 `mermaid.detectType(text)` (public, verified)

`detectType('sequenceDiagram\nA->>B: hi')` → `'sequence'`. `'graph TD'` → `'flowchart'`,
`'flowchart TD'` → `'flowchart-v2'` — but `getDiagramFromText('graph TD...').type` is
`'flowchart-v2'` in both cases (legacy renderer removed; both use FlowDB, identical db shape).

---

## 3. `@mermaid-js/parser` (Langium) — coverage as of v1.2.1 (2026-08)

- **Works fully headless in Node — verified, no DOM/jsdom needed.** ESM only. Dep: `@chevrotain/types`
  (langium/chevrotain bundled in dist).
- Verified `parse()` overloads (= complete grammar coverage):
  `info, packet, pie, treeView, architecture, gitGraph, eventmodeling, radar,
   railroad, railroadEbnf, railroadAbnf, railroadPeg, treemap, wardley, cynefin`
- **NOT covered: flowchart, sequence, class, state, ER, gantt** — verified:
  `parse('flowchart', ...)` throws `Unknown diagram type: flowchart`.
  Those still use the deprecated **Jison** parsers inside mermaid core
  (tracking issue: https://github.com/mermaid-js/mermaid/issues/4401 — Langium migration in progress
  since 2023; new diagrams get Langium, big legacy grammars have not migrated yet).
- Verified usage:
  ```js
  import { parse, MermaidParseError } from '@mermaid-js/parser';
  const ast = await parse('pie', 'pie title Pets\n "Dogs": 386\n "Cats": 85');
  // {$type:'Pie', title:'Pets', showData:false,
  //  sections:[{$type:'PieSection',label:'Dogs',value:386}, ...]}
  const g = await parse('gitGraph', 'gitGraph\n commit id: "a"');
  // {$type:'GitGraph', statements:[...]}   (AST nodes carry Langium's $type/$cstNode)
  ```
- Signature: `declare function parse<T extends DiagramAST>(diagramType: keyof typeof initializers, text: string): Promise<T>`;
  throws `MermaidParseError`.
- **Conclusion for Thalyx:** `@mermaid-js/parser` is NOT sufficient for the core use case
  (flowcharts/sequence). Use mermaid core's `getDiagramFromText` + db accessors instead.

---

## 4. Running mermaid core in Node without a browser

Verified matrix (Node 22, mermaid 11.17.0):

| Operation | Bare Node | With jsdom globals | Notes |
|---|---|---|---|
| `import('mermaid')` | ✅ works | ✅ | module loads fine |
| `mermaid.parse()` / `getDiagramFromText()` (flowchart etc.) | ❌ `DOMPurify.addHook is not a function` | ✅ works | DOMPurify needs a `window`; sanitizeText runs during db population |
| `mermaid.render()` | ❌ | ❌ `CSSStyleSheet is not defined` → ✅ with polyfills | see below |

Minimal jsdom setup that makes **parse + db extraction** work (verified):
```js
import { JSDOM } from 'jsdom';
const dom = new JSDOM('<!DOCTYPE html><body></body>');
global.window = dom.window;
global.document = dom.window.document;
global.DOMParser = dom.window.DOMParser;   // do NOT assign global.navigator (getter-only in Node 22)
const { default: mermaid } = await import('mermaid');
await mermaid.registerExternalDiagrams([], { lazyLoad: false });
```

`mermaid.render()` under jsdom additionally requires (verified to produce a full SVG string):
```js
global.CSSStyleSheet = class { insertRule(){} replaceSync(){} get cssRules(){return [];} };
dom.window.SVGElement.prototype.getBBox = () => ({x:0,y:0,width:100,height:20});
dom.window.SVGElement.prototype.getComputedTextLength = () => 100;
const { svg } = await mermaid.render('graphDiv', 'flowchart TD\n A[Start]-->B{End}');
// svg = '<svg id="graphDiv" ... aria-roledescription="flowchart-v2">...'  (10990 chars)
```
**BUT** text measurement is faked, so node sizes/wrapping are wrong → jsdom render is fine for
smoke tests, wrong for production previews. Production options: render inside the app's webview
(Tauri/Electron — Thalyx will have one anyway), `@mermaid-js/mermaid-cli` (`mmdc -i in.mmd -o out.svg`,
puppeteer peer-dep), or `mermaid-isomorphic` (MIT, Playwright-based, API `createMermaidRenderer()`).
In Thalyx: do parse/db-extraction in the UI process or in Node-with-jsdom; do preview rendering in the webview.

---

## 5. Generating mermaid text FROM a graph model

- **No mature general-purpose JS "graph model → mermaid" serializer exists on npm** (checked 2026-08-23).
  Closest: `mermaid-builder` 0.0.9 (seamapi) — ER diagrams only, stale; `excalidraw-to-mermaid` 0.2.1
  (flowchart-ish, MIT, small); various one-off `*-to-mermaid` converters (nx-graph-to-mermaid, scl-to-mermaid).
  → **Hand-roll the serializer.** For flowcharts it is ~200 LOC given the db model above.
- Mermaid's own text is line-oriented; serializer skeleton:
  ```
  flowchart TB
    id1["Label"]            %% one line per node: id + shape brackets + quoted label
    id1 e1@-->|"edge label"| id2
    subgraph sg1["Title"]
      direction LR
      id3
    end
    classDef hot fill:#f96
    class id1 hot
    style id2 fill:#f9f,stroke:#333
    linkStyle 0 stroke:#ff3,stroke-width:4px
    click id1 href "https://..." "tooltip"
  ```

### Escaping rules (empirically verified on 11.17.0)

- **Always emit labels wrapped in double quotes** — `A["label"]` — this makes `()[]{}|;`, unicode,
  and spaces safe. Unquoted `A[unquoted (parens)]` is a **parse error**.
- **A literal `"` inside a label CANNOT be backslash-escaped** (`"\"x\""` = parse error, verified).
  The only mechanism is HTML-style entity codes with `#`: `#quot;` → `"`, `#35;` → `#`,
  `#9829;` → ♥ (docs: https://mermaid.js.org/syntax/flowchart.html "Entity codes to escape characters").
  Serializer rule: `label.replace(/#/g,'#35;').replace(/"/g,'#quot;')` then wrap in quotes.
- **Import-side decoding:** db `.text` contains mermaid's internal placeholders for entities:
  `#quot;` is stored as `ﬂ°quot¶ß`, `#9829;` as `ﬂ°°9829¶ß` (verified). Exact decode (from mermaid dist
  `decodeEntities`): `text.replace(/ﬂ°°/g,'&#').replace(/ﬂ°/g,'&').replace(/¶ß/g,';')` — then run a
  standard HTML entity decode to get the display string. Also: raw `&`/`<` in quoted labels are
  sanitized into `&amp;`/`&lt;` in db text; `<br/>` normalized to `<br>`.
- **Markdown labels:** ``A["`**bold**`"]`` → `labelType:'markdown'`, `text:'**bold** _md_'`
  (backticks stripped). Serializer: if labelType==='markdown', wrap in `"` + backticks.
- **Node ids:** dashes and dots are legal (`id-with-dash`, `x.y` verified). Docs gotchas:
  id `end` (lowercase) breaks flowcharts; ids starting with `o`/`x` next to `---` are parsed as
  circle/cross edges (`dev---ops`); safest is to generate ids matching `[A-Za-z_][A-Za-z0-9_]*`
  and keep display text in the label.
- Direction tokens: `TB`/`TD` (synonyms; db always reports `TB`), `LR`, `RL`, `BT`. Emit `TB`.
- Comments: `%%` line comments — stripped before parse, never reach the db.

---

## 6. Layout

- **Default:** dagre (bundled, `dagre-d3-es` fork). Per-diagram `curve` config, `flowchart.useMaxWidth` etc.
- **ELK addon** (`@mermaid-js/layout-elk` 0.2.3, MIT) — verified working headless:
  ```js
  import elkLayouts from '@mermaid-js/layout-elk';
  mermaid.registerLayoutLoaders(elkLayouts);
  mermaid.initialize({ layout: 'elk' });   // or 'elk.stress' etc.
  ```
  Registered algorithm names (verified): `elk`, `elk.stress`, `elk.force`, `elk.mrtree`, `elk.sporeOverlap`.
  Layout selectable per-diagram via frontmatter: `---\nconfig:\n  layout: elk\n---`.
  Docs: https://mermaid.js.org/config/layouts.html (elkjs itself is EPL-2.0 — permissive-compatible,
  but note EPL is a weak copyleft; the npm addon wrapping it is MIT; elkjs is a transpiled artifact —
  acceptable to depend on, verify policy).
- **Tidy-tree addon** `@mermaid-js/layout-tidy-tree` 0.2.2 (MIT), used by mermaid-cli as optional dep.
- For Thalyx's own canvas layout of imported diagrams, options: run mermaid render once and scrape
  positions from SVG (what mermaid-to-excalidraw does), or run your own ELK/dagre on the extracted
  db graph (cleaner; `elkjs` or `@dagrejs/dagre` 1.x MIT).

## 7. Rendering SVG previews

- Browser/webview: `const { svg, bindFunctions } = await mermaid.render('uniqueId', text)` —
  set `securityLevel`, `startOnLoad:false` via `mermaid.initialize`. This is the recommended path
  inside Thalyx's webview.
- Node headless: jsdom + polyfills works mechanically but with wrong text metrics (see §4).
  Real options: `@mermaid-js/mermaid-cli` (`mmdc -i diagram.mmd -o out.svg`, puppeteer),
  `mermaid-isomorphic` (Playwright), or **`beautiful-mermaid`** (1.1.3, MIT, zero-DOM, synchronous
  `renderMermaidSVG(text)` — verified working in bare Node, 2.7KB SVG for a 2-node flowchart; own
  ELK-based sync layout; supports flowchart/state/sequence/class/ER/XY only; visual style differs
  from stock mermaid).
- `beautiful-mermaid` also has a verified secondary parser API (`parseMermaid(text)` →
  `{direction, nodes: Map<string,{id,label,shape}>, edges:[{source,target,label?,style,hasArrowStart,hasArrowEnd}],
  subgraphs:[{id,label,nodeIds,children}], classDefs, classAssignments, nodeStyles, linkStyles}` —
  simpler than FlowDB but flowchart-family only; shape vocab: `rectangle|rounded|diamond|stadium|circle|
  subroutine|doublecircle|hexagon|cylinder|asymmetric|trapezoid|trapezoid-alt|state-start|state-end`).

## 8. Round-trip limitations (mermaid → model → mermaid)

Verified/known losses when importing via db and re-serializing:
1. `%%` comments and blank lines/whitespace/statement order — stripped pre-parse, unrecoverable.
2. `TD` vs `TB` — db normalizes to `TB`. `graph` vs `flowchart` keyword — not distinguishable from db
   (detectType distinguishes, db does not; safe to always emit `flowchart`).
3. Auto edge ids (`L_A_B_0`) are synthetic — only re-emit `id@` syntax when `isUserDefinedId:true`.
4. Statement sugar collapses: `A & B --> C` becomes two edges; `A --> B --> C` becomes two edges;
   node declared inline vs standalone is indistinguishable. Re-serialized text will be normalized —
   acceptable, but means **byte-identical round-trip is impossible by design**; aim for semantic round-trip.
5. Entity-code labels come back as internal `ﬂ°...¶ß` placeholders (decode rule in §5); `&`,`<` are
   HTML-escaped in db text by sanitizer (securityLevel-dependent).
6. Subgraph `direction` is preserved in db (`dir`), BUT mermaid itself ignores it at render time if any
   subgraph node links outside (documented in flowchart docs).
7. Styling is NOT lost at db level (classDef/class/style/linkStyle/click/tooltip all recoverable — §2.4);
   what IS lost: `linkStyle default ...` interpolation details live on `edges.defaultStyle/defaultInterpolate`
   array props (easy to miss), and `curve` config from frontmatter must be read from `mermaid.parse()`'s
   returned `config`, not the db.
8. Sequence diagrams: control-flow blocks (loop/alt/par/rect) appear inline in `getMessages()` as
   typed marker messages (LOOP_START=10 etc.) — an editor must reconstruct nesting from these markers.
9. mermaid version pinning matters: db shapes are internal API, not covered by semver guarantees —
   pin exact mermaid version and add a round-trip test corpus (mermaid-to-excalidraw does the same;
   parse-error issue precedent: https://github.com/mermaid-js/mermaid/issues/3901).

## 9. Recommended architecture for Thalyx (concrete)

1. **Import:** webview-side (or Node+jsdom) `mermaid.registerExternalDiagrams([], {lazyLoad:false})`
   once; `mermaid.detectType(text)`; `mermaidAPI.getDiagramFromText(text)`; per-type db → Thalyx model.
   Start with flowchart (FlowDB — richest, table in §2.4), then sequence, state, class, ER.
2. **Export:** hand-rolled serializer per §5 escaping rules; store `labelType` to know when to emit
   backtick-markdown; always quote labels; entity-encode `#` and `"`.
3. **Preview:** `mermaid.render` in the webview; `layout: 'elk'` optional via `@mermaid-js/layout-elk`.
4. **Testing:** Node + jsdom harness (verified in §4) gives fast headless unit tests of import/export
   without a browser; golden corpus of .mmd files, assert `parse(serialize(parse(x)))` fixpoint.
5. All required deps are MIT (mermaid, layout-elk, jsdom is MIT; elkjs EPL-2.0 only if own-layout uses it;
   `@dagrejs/dagre` MIT as alternative).
