# UX Research: Best-in-Class Diagramming Tools (for Thalyx)

Researched 2026-08-23 via web search + primary vendor docs. Every claim below is tagged
[verified] (found in a cited source) or [rec] (my synthesis/recommendation — safe defaults, not vendor facts).
Thalyx context: cross-platform (macOS + Linux) desktop diagramming app, public-domain licensed,
deep Mermaid round-trip + native high-fidelity drag-and-drop editing. Priority: simple, fast, user-friendly.

---

## 1. Tool-by-tool findings

### 1.1 OmniGraffle (macOS/iPad, The Omni Group) — what is loved, what feels heavy

Loved [verified]:
- Stencil ecosystem: huge library of quality stencils at Graffletopia, searchable *from inside the app*
  (https://www.hungrybrowser.co.uk/7-reasons-love-omnigraffle-ux-design).
- Shared layers (repeated headers/footers across canvases), template variables (canvas name, page number
  auto-substituted), "Copy as PDF" smart-object masters, duplicate-canvas for page states, outstanding PDF export.
- Focused wireframing: "when wireframing at low or medium fidelity, OmniGraffle shines … less clutter to slow
  users down" vs bigger tools (https://www.uxmatters.com/mt/archives/2012/11/agile-omnigraffle-and-native-mobile-wireframing.php).
- Magnets model: with no magnets, lines connect to shape *center*; with magnets, each line snaps to the nearest
  magnet. Magnet Tool places magnets at arbitrary points; common N/S/E/W points available in the Properties
  inspector. "OmniGraffle uses magnets to ensure that lines and connections are never broken when moved."
  (OmniGraffle 7 reference manual, https://support.omnigroup.com/documentation/omnigraffle/mac/7.19/en/diagramming-basics/)
- Smart Guides align shapes AND magnets ("When an object has more than one magnet, Smart Guides will appear so
  you can align the magnets as well") — there is a dedicated Smart Guides tutorial video
  (https://www.omnigroup.com/video/set/omnigraffle-7-for-mac/smart-guides/).
- Auto layout exists but is an *inspector setting* (Canvas inspectors → "Diagram Layout and Style" → Auto layout),
  and the docs advise turning it OFF before manual connecting — i.e., it is modal and fights manual editing. [verified]

Heavy / disliked [verified]:
- Learning curve: "mastering the more advanced tools and functionalities can require considerable time and effort";
  "may not be the easiest tool to pick up for newcomers" (Capterra reviews,
  https://www.capterra.com/p/161414/OmniGraffle-Pro/reviews/).
- Deep inspector-sidebar UI (Object/Canvas/Document inspector stacks) is the main source of perceived weight —
  power is buried in nested inspectors rather than surfaced contextually. [verified re: inspectors existing;
  characterization synthesized from reviews]
- Price: Standard $149.99 one-time; Pro subscription $12.49/mo ($124.99/yr)
  (https://www.getapp.com/it-management-software/a/omnigraffle/pricing/). Apple-only. No Linux/Windows.
- Weak at data: no live data sources, no import/export of hierarchical/relational data structures
  (softwareworld.co review) — exactly the gap Mermaid round-trip fills for Thalyx.
- iPad version notorious for crashes/data loss in reviews; long-time users complain about reliability decline. [verified]

Takeaway for Thalyx: steal the *magnet/connection-integrity* model and smart guides; reject the
inspector-stack-first UI and modal auto-layout toggle.

### 1.2 Excalidraw (web, MIT license) — the speed benchmark

- Opens instantly, no account, straight onto the canvas; hand-drawn aesthetic is "psychologically freeing —
  it signals that nothing is final" (https://atlas.wrxstack.com/guides/excalidraw-vs-drawio,
  https://aistackpicks.com/reviews/excalidraw-alternatives-2026/). [verified]
- Keyboard-first tool selection (single letter OR digit) [verified, csswolf.com/excalidraw-keyboard-shortcuts-pdf/]:
  - Selection V/1, Rectangle R/2, Diamond D/3, Ellipse O/4, Arrow A/5, Line L/6, Draw P/7, Text T/8,
    Image 9, Eraser E/0, Frame F, Hand H, Laser K.
  - Duplicate: Ctrl/Cmd+D or **Alt/Option+drag**.
  - Group Ctrl+G / Ungroup Ctrl+Shift+G; Lock Ctrl+Shift+L.
  - Align: Ctrl+Shift+Arrow (top/bottom/left/right).
  - Zoom: Ctrl+ +/-, Ctrl+0 reset, **Shift+1 zoom-to-fit-all, Shift+2 zoom-to-selection**.
  - Text: Enter on selected shape = edit/add label; Esc or Ctrl+Enter = finish editing.
  - Z-order: Ctrl+[ / Ctrl+] (one step), Ctrl+Shift+[ / ] (to back/front).
  - Help overlay: **Shift+/** shows all shortcuts. Theme toggle: **Shift+Alt+D** (Cmd+Shift+D noted for Mac;
    known clash with Chrome tab-duplicate — a desktop app avoids this) [verified,
    github.com/excalidraw/excalidraw/issues/7578].
- Flowchart keyboard creation (shipped Aug 2024) [verified, x.com/excalidraw/status/1823079626156961937]:
  **Cmd/Ctrl+ArrowKey on a selected node creates a new node in that direction, already connected by an arrow;
  hold Cmd/Ctrl and press Arrow repeatedly to chain nodes; press Tab while creating to cycle the new node's
  shape (rectangle → diamond → ellipse).**
- Elbow (orthogonal) arrows: pathfinding-based 90°-bend routing, added because hand-managed arrows were slow;
  two-part engineering writeup: https://plus.excalidraw.com/blog/building-elbow-arrows-part-one and -part-two. [verified]
- Quick styling philosophy: curated limited palette; "colors look good by default so users don't have to spend
  time picking them, and a limited selection promotes consistency"; a custom picker exists but is secondary;
  palette built on the open-source Open Color system (https://plus.excalidraw.com/blog/open-colors,
  github.com/excalidraw/excalidraw/issues/5931). [verified]
- Mermaid import: toolbar "Mermaid" dialog → paste text → converted to **native editable elements** for
  flowcharts; unsupported diagram types fall back to an embedded image. Library:
  `@excalidraw/mermaid-to-excalidraw` on npm, API `parseMermaidToExcalidraw(definition, config)`
  (https://docs.excalidraw.com/docs/@excalidraw/mermaid-to-excalidraw/api,
  https://github.com/excalidraw/mermaid-to-excalidraw — MIT). [verified]
- Known gripe: no shortcuts for changing colors of selection (issue #8064 "without shortcuts for changing
  colors it is absolutely unbearable") — styling shortcuts are a real power-user want. [verified]
- No auto-layout of existing diagrams; no minimap. [verified by absence in docs/shortcuts]

### 1.3 Whimsical (web/desktop, proprietary) — fastest flowchart ergonomics

[verified, https://whimsical.com/learn/get-started/flowcharts and https://whimsical.com/learn/boards/connectors]
- "Quick add" buttons on the 4 sides of a selected shape; clicking one creates a connected shape in that direction.
  **Option/Alt + any ArrowKey does the same from the keyboard.** Toggle visibility of the quick-add buttons with `Q`.
- Style persistence: "When you add new shapes with the quick add buttons, the same styles will be used for the
  next shape." (Style inheritance = consistent diagrams for free.)
- Shape shortcuts: `S` opens diagram-shapes toolbar; `R` rectangle, `C` connector (help-center shortcut list).
- Connector attachment: while dragging a connector end over an item, a **purple box** highlights the whole item;
  release and it attaches ("magnetic edges" — attach to shape, not to a specific point).
- Connector styles: elbow or curved (toggle icon in toolbar); 8 endpoint types, each end independently settable.
- Connector labels: **double-click a connector to type on it**; drag the label to reposition it along the path;
  optional white background behind label text.
- Navigation trick: Cmd/Ctrl+click one end of a connector jumps selection to the other end.
- Auto-layout as an *action*, not a mode: select ≥2 connected shapes → "Lay out vertically (top to bottom)" or
  "Lay out horizontally (left to right)"; it rearranges elements and re-routes connectors.
- Snapping modifiers: hold Cmd/Ctrl while dragging to *ignore* snapping to other shapes / to the grid.
- 2026 release added a command menu (Cmd+K-style) and custom colors
  (https://whimsical.com/releases/2026-2-command-menu-and-colors).
- Widely cited as fast because shapes are always created "equidistant and perfectly aligned" via quick add.

### 1.4 FigJam (Figma) — approachability benchmark

[verified, help.figma.com articles 1500004291601, 1500004414542]
- Quick create: hover the **blue dot at a shape's edge** → a quick-create icon appears → click to create a
  connected shape+connector in that direction, **with its text field immediately active**; or drag the preview
  anywhere to place it. Clicking repeatedly on the same side stacks more shapes.
- Keyboard: **Cmd+Return / Ctrl+Enter creates a connected shape to the right with text field active.**
- Connector shortcuts: `X` or `Shift+L` = bent (elbow) connector; `L` = straight line. Connectors "snap onto
  existing shapes and stickies" and "update automatically as you move items".
- Three connector types: bent (routes around objects), curved, straight.
- Shape tool: pick a shape, a *preview follows the cursor*, click to drop (placement preview pattern).
- Why it feels light [verified, multiple 2026 comparisons e.g. codepic.cc/blog/miro-vs-figjam]:
  skeuomorphic bottom toolbar ("a pen that looks like a pen"), playful stamps/cursor-chat, and
  "non-technical participants can jump in without training".
- Figma design editor's Smart Selection (relevant pattern, verified,
  https://www.figma.com/blog/introducing-smart-selection/ and
  https://help.figma.com/hc/en-us/articles/360040450233): when a selection forms a row/column/grid,
  **pink handles appear between items to drag-adjust uniform spacing**, and a pink ring per item lets you
  **drag to reorder** while others reflow. **Tidy Up** (⌥⌘T / Ctrl+Alt+T) snaps a messy selection into an
  evenly-spaced row/column/grid in one action.

### 1.5 draw.io / diagrams.net (Apache-2.0) — most complete connection model, heaviest chrome

[verified, https://www.drawio.com/doc/faq/connect-shapes, /docs/manual/connectors/, /docs/manual/editor/]
- Hover a shape → **four blue directional arrows** appear.
  - Click an arrow: clones the shape in that direction + auto-connects (first entry of a popup shape picker).
  - Hover the arrow: shows 4 basic shape choices; click the arrow proper: full shape-picker popup.
  - If a shape already exists in that direction, clicking the arrow just draws a connector to it.
  - Ctrl+drag from a directional arrow: place the clone anywhere, release to add + connect.
- Keyboard clone-and-connect: **Alt+Shift+ArrowKey clones the selected shape in that direction and connects it.**
  `Alt+X`/`Option+X` + click a library shape: adds it to canvas connected to the current selection.
- Two connection kinds (core concept worth copying): **floating connections** (attach to the shape outline as a
  whole; endpoint slides as shapes move) vs **fixed connections** (attach to a specific connection point/port,
  shown as small × marks on hover). Hovering shape outline shows blue halo = floating; hovering an × = fixed.
- Shape picker also opens by **double-clicking empty canvas** (type to search shapes) — text-first shape insertion.
- Canvas nav: Space+drag OR right-click-drag OR middle-click-drag to pan; scroll = vertical, Shift+scroll =
  horizontal; **Ctrl/Cmd+scroll = zoom** (Alt+scroll also zooms); Ctrl+Shift+H = fit page/reset view.
- **Outline panel = minimap**: small always-visible panel with a draggable blue viewport rectangle for
  navigating large diagrams (https://drawio-app.com/blog/simplify-diagram-navigation-in-draw-io/).
- Auto-layout: Arrange → Layout menu (horizontal/vertical flow, tree, org chart, circle, radial) applies a
  one-shot layout; also special containers ("tree container", "flow container") that keep auto-laying-out
  children (https://www.drawio.com/docs/manual/shapes/automated-layout-shapes/).
- Criticism [verified, 2026 comparisons e.g. atlas.wrxstack.com/guides/excalidraw-vs-drawio]: "tries to cover
  every diagramming use case", enormous shape library + dense Format panel = overwhelming vs Excalidraw's
  deliberate minimalism. Its UI is the canonical example of "powerful but cluttered".

### 1.6 Lucidchart (proprietary, web)

[verified, lucid.co/blog/lucidchart-shortcuts, help.lucid.co article 15154609056916]
- Space+drag pan; right-click-drag pan; Ctrl/Cmd+scroll zoom; Ctrl+ +/-/0; F1 opens in-app shortcut list.
- Same quick-connect family: drag from shape edge, pick "add shape" from popup. Feature-rich but subscription
  SaaS; commonly reviewed as more formal/enterprise than Whimsical/FigJam.

### 1.7 Miro (proprietary) — cautionary tale

[verified, G2/Capterra/TrustRadius 2026 review roundups]
- Praised: infinite canvas, templates, real-time collaboration.
- Complaints: "cluttered interface, lag on large boards, uneven depth in some features"; "first-time users can
  feel overwhelmed by the number of features"; diagram-specific tasks (connecting widgets with lines) called
  cumbersome. Boards degrade into clutter. Performance drops with big boards.
- Lesson: breadth of features + template-picker-first onboarding = the "heavy" feeling Thalyx must avoid.

### 1.8 tldraw — UX reference only, NOT a dependency

- tldraw's SDK is under a **source-available watermark license — NOT acceptable** as a dependency for a
  public-domain project. Its UX patterns (context toolbar above selection, quick 12-color palette, snapping)
  may still be *studied*. Do not import any tldraw code. [license fact widely documented at tldraw.dev/legal]

---

## 2. Cross-tool pattern catalog (with the consensus behavior)

| Pattern | Consensus implementation across tools |
|---|---|
| Create-connected-node from keyboard | Excalidraw Ctrl/Cmd+Arrow (+Tab cycles shape); Whimsical Option/Alt+Arrow; draw.io Alt+Shift+Arrow; FigJam Cmd+Enter. All create node+edge in one gesture, style-inherited, equidistant. |
| Create-connected-node from mouse | Hover affordance on shape edge (draw.io 4 blue arrows; FigJam blue dot → quick-create icon; Whimsical quick-add buttons); click = create in direction; drag = place freely; if a node already exists there, connect instead of clone (draw.io). |
| Connector attachment | Two-tier: whole-shape "floating" attach (endpoint slides along boundary; Whimsical purple-box highlight) + optional fixed ports (draw.io × marks, OmniGraffle magnets). Default should be floating. |
| Orthogonal routing | Elbow connectors with auto 90° routing that re-routes live as shapes drag (Excalidraw elbow arrows, FigJam bent connectors, draw.io orthogonal edge style). |
| Duplicate | Alt/Option+drag AND Ctrl/Cmd+D everywhere. |
| Smart guides | Alignment lines to edges/centers of nearby shapes + equal-spacing indicators; Figma adds draggable pink spacing handles + Tidy Up (⌥⌘T). Modifier (Cmd/Ctrl in Whimsical) suppresses snapping. |
| Grid vs magnetic snap | Tools default to *smart/magnetic* snapping; grid snap is optional. Modifier key inverts. |
| Quick styling | Small curated palette (Excalidraw/Open Color; tldraw ~12 colors) beats full pickers; full picker demoted to secondary UI. Style of last-created shape is inherited by next (Whimsical). |
| Inline text | Double-click shape OR select+Enter to edit label (Excalidraw Enter); FigJam auto-activates text field on node creation; double-click connector to label it (Whimsical); double-click empty canvas = new text (Excalidraw) or shape picker (draw.io). |
| Canvas nav | Space+drag pan (universal), middle/right-drag pan (draw.io/Lucid), Ctrl/Cmd+scroll zoom (universal), plain scroll = pan vertical, Shift+scroll = pan horizontal, Ctrl+0 = 100%, zoom-to-fit (Excalidraw Shift+1) and zoom-to-selection (Shift+2). |
| Minimap | Only draw.io (Outline panel) and Miro ship one; the fast tools (Excalidraw, Whimsical, FigJam) do not — zoom-to-fit replaces it. |
| Context UI | Fast tools: floating context toolbar/panel scoped to selection (Excalidraw left panel shows only relevant props; FigJam toolbar above selection). Heavy tools: persistent inspector stacks (OmniGraffle) / dense Format panel (draw.io). |
| Auto-layout | As one-shot *action on selection* (Whimsical lay-out-vertically/horizontally; draw.io Arrange→Layout; Figma Tidy Up), never as an always-on mode (OmniGraffle's modal auto-layout is documented as something to turn off). |
| Dark mode | Excalidraw Shift+Alt+D toggle, canvas + UI both theme; draw.io has dark UI theme. Table stakes for a dev-audience tool. |
| Onboarding | Excalidraw: zero-friction — no account, canvas immediately, hint text, Shift+/ help overlay. Miro/Lucid: template pickers and panels first = "heavy" first impression. |
| Shape libraries | OmniGraffle/draw.io: huge stencil trees (power, but clutter). Fast tools: one small shape set + search. |

---

## 3. (a) The 18 interactions that define "simple, fast, user-friendly" — MVP spec

Each entry: Trigger → Behavior → Details a weaker model needs. Keys use Cmd on macOS / Ctrl on Linux (call it `Mod`).

### Canvas & navigation

**I1. Instant empty canvas + hint layer.**
App opens directly onto an empty canvas (no template picker, no dialog). Show one line of dimmed hint text
centered: "Double-click to add a shape — or press R. Paste Mermaid text to import." Hint disappears on first
element created and never returns for that document. A `?`/`Shift+/` shortcut opens a searchable keyboard-shortcut
overlay (modeled on Excalidraw's Shift+/ dialog).

**I2. Pan.**
Space+drag pans (cursor becomes grab hand while Space held; releasing Space returns to previous tool).
Middle-mouse-drag also pans. Two-finger trackpad scroll pans in both axes. Plain mouse-wheel scroll pans
vertically; Shift+wheel pans horizontally. (draw.io/Lucidchart consensus.)

**I3. Zoom.**
Mod+scroll and trackpad pinch zoom, centered on the cursor position (not canvas center). Mod+Plus / Mod+Minus
step zoom (steps: 10,25,50,75,100,125,150,200,300,400%). Mod+0 = 100%. **Shift+1 = zoom-to-fit all content
(with ~10% padding); Shift+2 = zoom to selection** (exact Excalidraw bindings). Show current zoom % in a corner
control that clicks to reset. No minimap in MVP (fast tools don't have one; zoom-to-fit covers it).

### Creating & connecting

**I4. Single-key tool switching.**
`V`=select (default), `R`=rectangle, `O`=ellipse, `D`=diamond, `A`=arrow/connector, `L`=line, `T`=text,
`H`=hand. Number keys 1-8 as aliases (Excalidraw does both). After drawing one shape the app returns to Select
tool automatically; hold Alt when clicking a tool (or press the key twice) to keep the tool active for multiple
placements (Excalidraw's "keep tool active" behavior via lock — a simple lock toggle is fine).

**I5. Keyboard grow-a-flowchart: Mod+Arrow.**
With a node selected, **Mod+ArrowKey creates a new node one "step" away in that direction, connected by an
elbow arrow from the source's facing side to the new node's opposite side, inherits the source's style and size,
selects the new node, and opens its label editor immediately.** Repeated presses chain nodes. While the new node
is pending/selected, **Tab cycles its shape type rectangle → diamond → ellipse.** Step distance: source extent in
that axis + fixed gap (rec: gap = 48 px at 100% zoom, snapped to grid). If a node already exists at the target
position, connect to it instead of creating (draw.io behavior). (Pattern verified in Excalidraw + draw.io
Alt+Shift+Arrow + Whimsical Alt+Arrow; distance value is [rec].)

**I6. Hover quick-connect handles on shapes.**
When the pointer hovers a node (select tool, nothing being dragged), show 4 small directional chevrons just
outside the N/S/E/W edges (draw.io blue arrows / FigJam blue dot / Whimsical quick add).
- Click a chevron → same result as I5 in that direction.
- Drag from a chevron → rubber-band a new connector; on release over empty canvas, show a small shape-picker
  popup (recently-used shapes first, "just these 4 basic shapes" row) to create the target node there;
  on release over an existing node, attach to it.
- Chevrons must be suppressible: hide while text-editing and at zoom < ~40% [rec], and Q toggles them
  globally (Whimsical).

**I7. Connector drawing with magnetic edges (floating attach by default).**
With the Arrow tool (or dragging from a chevron): hovering any node highlights its **entire outline** (Whimsical
purple-box equivalent) meaning "attach to shape". Release attaches a *floating* connection: the endpoint is bound
to the node id, and the actual endpoint position is computed each frame as the intersection of the connector path
with the node boundary, so it slides smoothly as either node moves (draw.io floating connection; OmniGraffle
no-magnet=center behavior). Fixed ports (N/S/E/W anchor points shown as small dots when hovering near the edge)
are optional per-endpoint: releasing directly on a port pins to it (draw.io × marks; OmniGraffle magnets).
Data model note: an edge stores `{sourceId, targetId, sourceAnchor?: 'n'|'s'|'e'|'w'|'auto', targetAnchor?: ...}` —
exactly what Mermaid export needs; never store only absolute endpoint coordinates for attached ends.

**I8. Live orthogonal (elbow) routing.**
Default connector style = elbow: orthogonal segments, rounded corners optional, auto-routed to leave the source
side perpendicular and enter the target side perpendicular, re-computed live while either endpoint's node is being
dragged (Excalidraw elbow arrows; FigJam bent connectors). MVP routing can be the standard 3-5 segment
Manhattan heuristic (side selection by relative position of the two nodes) — full obstacle-avoiding pathfinding
(Excalidraw's A*-style approach, see plus.excalidraw.com/blog/building-elbow-arrows-part-one/-two) is a later
milestone. Offer straight and curved as the other two styles (FigJam's trio), toggled per-connector in the
context toolbar. Connectors never detach when a node is moved (OmniGraffle invariant).

**I9. Connector labels.**
Double-click a connector → inline text editor at the click point on the path. The label is stored on the edge
(→ Mermaid `A -->|label| B`). Label sits on a solid canvas-background chip so it stays readable over the line
(Whimsical white-background option, on by default). Drag the label along the path to reposition (store as
0..1 parameter along the route).

### Editing & text

**I10. Inline node text: select-and-type, double-click, Enter.**
Three equivalent entries into label editing: (a) double-click a node; (b) select a node and press Enter;
(c) select a node and just start typing a printable character (Whimsical/FigJam behavior — the char becomes the
first letter). Esc or click-away commits (Excalidraw: Esc / Ctrl+Enter to finish). Text is edited in place,
centered in the shape, same font/size as rendered — never in a detached field. Double-click on empty canvas
creates a text element at that point (Excalidraw).

**I11. Alt-drag duplicate + Mod+D.**
Alt/Option+drag on a selected element (or selection set) drags away a copy, leaving the original; smart guides
active during the drag so the copy can be aligned or evenly spaced. Mod+D duplicates in place with a small
(rec: +16,+16 px) offset. Duplicating a node does NOT duplicate its edges; duplicating a set of nodes together
with edges whose both ends are inside the set duplicates those edges too (standard behavior). [pattern verified
Excalidraw/universal; edge rule rec]

**I12. Smart guides + equal-spacing indicators (magnetic snapping default ON, grid OFF).**
While dragging/resizing, snap (threshold rec: 6 screen px) to: canvas-neighbor edges (left/right/top/bottom),
horizontal & vertical centers, and same-size on resize. Draw 1-px accent-colored guide lines while snapped.
**Equal-spacing:** when a dragged shape's gap to a neighbor matches the gap between two other aligned shapes,
show the gap distance chips/ticks on both gaps and snap (Figma smart selection visual language). Holding Mod
during a drag disables all snapping (Whimsical). Optional grid: view menu toggle; when on, positions/sizes snap
to an 8-px grid [rec], and smart guides win over grid when both apply. Arrow keys nudge selection 1 px,
Shift+Arrow 8 px [rec, matches common tools].

**I13. Tidy Up / one-shot auto-layout as an action, never a mode.**
Two buttons (context toolbar, on multi-selection):
- "Tidy up" (shortcut Ctrl+Alt+T / ⌥⌘T, matching Figma): snaps selected *unconnected* shapes into an
  evenly-spaced row/column/grid inferred from their current rough arrangement.
- "Auto-layout" on a selection containing connected nodes: runs a layered layout (dagre/ELK — both permissively
  licensed: dagre MIT, elkjs EPL-2.0 — verify EPL acceptability, otherwise dagre) top-to-bottom or left-to-right
  (Whimsical's two options), then re-routes connectors. Applied once, fully undoable; there is no persistent
  auto-layout mode (OmniGraffle's modal version is the anti-pattern).
This is also the landing behavior for Mermaid import: imported graphs get auto-layout, then become fully
hand-editable.

### Styling & UI chrome

**I14. Curated quick palette; full picker demoted.**
Selection styling shows a single row of ~9-12 curated fill colors + matching auto-derived stroke, plus
none/transparent (Excalidraw's Open Color-based approach: "colors look good by default … limited selection
promotes consistency"). A "custom…" swatch opens a full picker as an escape hatch. Stroke width: 3 choices
(thin/medium/bold). Corner radius: sharp/round toggle. Font size: S/M/L/XL. Every option is a segmented control
with all values visible — no dropdowns for ≤5 options. New shapes inherit the style of the last-styled/created
shape (Whimsical style persistence).

**I15. Context panel scoped to selection — no inspector stack.**
One floating panel (docked left like Excalidraw, or floating above selection like FigJam — pick one and keep it)
that shows ONLY the properties relevant to the current selection type (node: fill/stroke/corner/text;
edge: line style/arrowheads/label; nothing selected: canvas background + grid toggle + theme). Max ~8 controls
visible at once [rec]. No OmniGraffle-style multi-tab inspector stacks, no draw.io-style 3-tab Format panel.
Arrowhead control: per-end dropdown of none/arrow/triangle/dot (subset of Whimsical's 8 endpoints).

**I16. Selection mechanics.**
Click selects; Shift+click adds/removes; drag on empty canvas rubber-band selects (touching, not enclosing
[rec — feels faster; Excalidraw behavior]); Mod+A select all; Esc deselects; drag any part of a selected
shape's body to move (no dedicated move tool); 8 resize handles + rotation disabled for MVP (rotation breaks
Mermaid semantics and elbow routing — Excalidraw got elbow+rotation bugs; skip it). Group Mod+G /
Ungroup Mod+Shift+G. Z-order: Mod+[ , Mod+] , Mod+Shift+[ , Mod+Shift+] (Excalidraw bindings).

**I17. Dark mode (canvas + UI), one shortcut.**
Full light/dark theming of both chrome and canvas colors; default follows OS; manual toggle Shift+Alt+D
(Excalidraw binding — safe in a desktop app). The curated palette must define per-theme variants so user
diagrams stay legible in both themes (Excalidraw remaps its palette in dark mode). Exports always render on
an explicit background (user-chosen light or dark, defaulting to light) — never "whatever theme I happened
to be in".

**I18. Undo/redo everything + zero-friction persistence.**
Mod+Z / Mod+Shift+Z (and Mod+Y) with unlimited depth in-session; every operation including auto-layout,
Mermaid import, style changes, and tidy-up is one undo step. Documents autosave continuously (desktop app:
save-on-change to file once a path exists; recover unsaved scratch canvas on relaunch, Excalidraw-style
localStorage equivalent). No "unsaved changes?" dialogs during normal flow.

### Mermaid-specific UX hooks (bridging to Thalyx's core requirement)

- **Paste-to-import**: pasting text that parses as Mermaid (starts with `flowchart`/`graph`/`sequenceDiagram` etc.)
  onto the canvas offers/performs import at the cursor position, auto-laid-out (Excalidraw's Mermaid dialog is
  a toolbar button + paste box; Thalyx can do one better with direct paste detection, with a toast to undo /
  "paste as text instead").
- Node/edge data model must stay graph-first (ids + labels + directed edges + edge labels + shape kind) so
  "copy as Mermaid" is a pure serialization of selection. Excalidraw's `@excalidraw/mermaid-to-excalidraw`
  (MIT) proves flowchart→shapes conversion is tractable and is a reference implementation for parsing via
  mermaid's own parser API.

---

## 4. (b) Explicitly DO NOT BUILD (bloat list, with the tool that proves the cost)

1. **Persistent/modal auto-layout** that re-arranges while you edit (OmniGraffle docs literally tell users to
   turn it off before connecting things). Layout is always a one-shot, undoable action.
2. **Inspector stacks / multi-tab format panels** (OmniGraffle inspectors, draw.io Format panel) — the #1 cited
   source of "heavy". One selection-scoped context panel only.
3. **Giant stencil trees in the MVP** (draw.io's "enormous shape library" is its own criticism). Ship
   rectangle/rounded/ellipse/diamond/cylinder/text + a search-first insert popup. A stencil *format* can come later.
4. **Minimap** — Excalidraw/Whimsical/FigJam ship without one; zoom-to-fit (Shift+1) + zoom-to-selection cover it.
5. **Full color picker as the primary styling surface** — curated palette first (Excalidraw's documented philosophy).
6. **Free rotation of nodes** — breaks Mermaid round-trip semantics and complicates elbow routing for near-zero
   diagram value.
7. **Real-time multiplayer collaboration** in MVP — it is the single biggest complexity driver in Miro/FigJam
   and irrelevant to a local-first desktop tool's core loop. (Design file format so it isn't foreclosed.)
8. **Template galleries / onboarding wizards / account walls** — Excalidraw's zero-friction open-to-canvas is
   the loved pattern; Miro's template-first onboarding is the complained-about one.
9. **Presentation modes, comments, voting, timers, stamps, cursor chat** — FigJam/Miro collaboration theater;
   out of scope for a diagramming editor.
10. **Live data / spreadsheet import, org-chart-from-CSV** etc. — Lucidchart enterprise surface area; Mermaid
    text IS Thalyx's data interface.
11. **Multi-page/canvas documents in MVP** — one canvas per file keeps file format, tabs, and Mermaid mapping
    trivial (OmniGraffle's canvases+shared layers are a Pro feature serving print/wireframe workflows, not graphs).
12. **Hand-drawn "sketchy" rendering engine** — it is Excalidraw's brand, not a UX requirement; clean vector
    rendering is cheaper and matches "high-fidelity" positioning. (If ever added, it's a style, not a mode.)
13. **Custom scripting/AppleScript-style automation** (OmniGraffle) — post-1.0 at best.
14. **Freehand pen/eraser tools** as core — whiteboard territory; only if trivially cheap after MVP.

---

## 5. Implementation-facing notes & snippets

- Snap engine sketch [rec]:
  ```
  candidates = edges/centers of shapes within viewport ∪ grid lines (if grid on)
  for dragged bounds B: for each candidate c: if |proj(B,axis) - c| < 6 / zoom → snap, record guide
  equal-spacing: for aligned triples (a,b,dragged): if |gap(a,b) - gap(b,dragged)| < 6/zoom → snap + show both gap chips
  Mod held → skip entirely (Whimsical)
  ```
- Elbow routing MVP [rec]: pick source side = side of source bbox facing target center (unless pinned anchor);
  route = perpendicular stub (16 px) → midline → perpendicular stub into target side; recompute on every
  drag frame; this matches FigJam "bent" quality without pathfinding.
- Edge data invariant (Mermaid round-trip): `edge = {id, sourceId, targetId, label?, sourceAnchor: 'auto'|side,
  targetAnchor, style: 'elbow'|'straight'|'curved', arrowStart, arrowEnd}` — geometry is derived, never authoritative,
  for attached endpoints.
- Reference libs (licenses checked): `@excalidraw/mermaid-to-excalidraw` MIT (github.com/excalidraw/mermaid-to-excalidraw);
  dagre MIT; elkjs EPL-2.0 (check policy; EPL is weak-copyleft — prefer dagre if strict); mermaid itself MIT.
  tldraw SDK: watermark/source-available — EXCLUDED.
- Keyboard map source of truth: mirror Excalidraw where a binding exists (largest muscle-memory pool among the
  target audience), fill flowchart-growth from the Excalidraw/Whimsical/draw.io consensus (Mod+Arrow).

## 6. Primary sources

- Excalidraw shortcuts: https://csswolf.com/excalidraw-keyboard-shortcuts-pdf/ ; flowchart Cmd+Arrow announcement:
  https://x.com/excalidraw/status/1823079626156961937 ; elbow arrows: https://plus.excalidraw.com/blog/building-elbow-arrows-part-one ,
  https://plus.excalidraw.com/blog/building-elbow-arrows-part-two ; palette philosophy: https://plus.excalidraw.com/blog/open-colors ,
  https://github.com/excalidraw/excalidraw/issues/5931 ; color-shortcut gripe: issues/8064 ; theme shortcut clash: issues/7578.
- Whimsical: https://whimsical.com/learn/get-started/flowcharts ; https://whimsical.com/learn/boards/connectors ;
  https://whimsical.com/releases/2026-2-command-menu-and-colors.
- FigJam: https://help.figma.com/hc/en-us/articles/1500004291601-Build-faster-with-quick-create-in-FigJam ;
  https://help.figma.com/hc/en-us/articles/1500004414542-Create-diagrams-and-flows-with-connectors-in-FigJam.
- Figma smart selection / Tidy Up: https://www.figma.com/blog/introducing-smart-selection/ ;
  https://help.figma.com/hc/en-us/articles/360040450233-Arrange-layers-with-Smart-selection.
- draw.io: https://www.drawio.com/doc/faq/connect-shapes ; https://www.drawio.com/docs/manual/connectors/ ;
  https://www.drawio.com/docs/manual/editor/ ; https://www.drawio.com/docs/manual/shapes/automated-layout-shapes/ ;
  https://drawio-app.com/blog/simplify-diagram-navigation-in-draw-io/ ; https://drawio-app.com/blog/pan-and-zoom/.
- OmniGraffle: https://support.omnigroup.com/documentation/omnigraffle/mac/7.19/en/diagramming-basics/ ;
  https://www.omnigroup.com/video/set/omnigraffle-7-for-mac/smart-guides/ ;
  https://www.hungrybrowser.co.uk/7-reasons-love-omnigraffle-ux-design ;
  https://www.capterra.com/p/161414/OmniGraffle-Pro/reviews/ ; pricing https://www.getapp.com/it-management-software/a/omnigraffle/pricing/.
- Lucidchart: https://lucid.co/blog/lucidchart-shortcuts ; https://help.lucid.co/hc/en-us/articles/15154609056916.
- Miro complaints: https://www.g2.com/products/miro/reviews ; https://www.trustradius.com/products/miro/reviews/all ;
  https://cpoclub.com/tools/miro-review/.
- Comparisons: https://atlas.wrxstack.com/guides/excalidraw-vs-drawio ; https://codepic.cc/blog/miro-vs-figjam ;
  https://aistackpicks.com/reviews/excalidraw-alternatives-2026/.
- Mermaid import reference: https://docs.excalidraw.com/docs/@excalidraw/mermaid-to-excalidraw/api ;
  https://github.com/excalidraw/mermaid-to-excalidraw (MIT).
