# ANALYSIS.md — Sion review backlog

This document merges the full review originally written in `glm.md` (at
v0.2.0, commit 4194729), the independent `k3.md` review, and everything
learned during the follow-up implementation rounds. Completed items are archived at the bottom without
loss of detail; the list above them is the live, shovel-ready backlog.
Each entry names files and concrete mechanics so an LLM can pick one up
and implement it without re-deriving the analysis.

Verification environment note: Linux boxes can run `swift test`
(SionCore + core tests). All `SionKit`/AppKit work is compile-checked by
CI (`scripts/build.sh`, which runs the full test suite on macOS) and by
the GLM PR review workflow. Keep UI diffs surgical and land them via PR.

## In-flight PRs (do not duplicate)

| PR | Branch | Topic |
|----|--------|-------|
| #45 | `fix/element-compositing` | preserve whole-element compositing (opacity/blend/shadow once per element) |

## Bugs

### A2 (P1) Shadow direction on canvas vs SVG export needs a visual audit
Model is y-down; the default elevation shadow (`dy = +2`) renders
downward in exported SVG (`feDropShadow`). The canvas draws in a flipped
NSView and installs `NSShadow.shadowOffset` verbatim; NSShadow offsets
follow the unflipped base space, so the canvas shadow may render upward,
disagreeing with the export. Needs a screenshot on macOS; fix by negating
y when installing the shadow in flipped drawing. `applyShadow` also
ignores `ShadowStyle.spread`. (#38 touched the same drawing path and
landed; the audit should re-check against it.)

### A4 (P2) Corner-radius default inconsistency
`SceneElementDefaults.cornerRadius = 14` (Scene.swift) vs the editor's
insert path (`InteractionGeometry`-era default 12, see EditorDefaults /
Tool.shapeKind). Pick one constant in SionCore and use it everywhere.

### A5 (P2) Shape-precise hit testing (remainder of the rotation work)
Hit testing is now rotation-aware (frame test in local space), but every
shape still hit-tests as its rectangle: clicks in the corners of an
ellipse/diamond/triangle select it. Do point-in-path testing with the
already-built `shapePath` NSBezierPath (`contains(_:)`) under the
rotation transform, falling back to the frame for paths with strokes
only. Controller needs a path-provider hook or the test moves to the
view layer.

### A6 (P2) Cylinder renders as a barrel
`cylinderPath` (SionCanvasView) draws top rim bulging up and bottom rim
bulging down but omits the *front* arc of the top ellipse dipping into
the body — no "database" rim. Compare any OmniGraffle cylinder; fix the
bezier sequence and mirror it in SVGExporter's shapePath.

### A7 (P2) Gradient rendering loses start/end asymmetry
Canvas converts `LinearGradientFill(start:end:)` to
`NSGradient.draw(in:angle:)` (angle-only), while SVG export emits exact
start/end points. Non-centered gradients render differently in-app vs
exported. Draw with `CGContext.drawLinearGradient` clipped to the path.

### A8 (P2) `nsColor` uses the deprecated calibrated RGB space
Device-dependent; will drift from the sRGB hex used in SVG export.
Switch to `NSColor(srgbRed:...)`.

### A9 (P2) Text overflow behavior
`drawText` clamps measured height to the frame — labels longer than the
shape silently clip with no indicator; `TextAutoSizing.fitHeight` is
modeled but never grows a frame during editing; connector labels clip
into a fixed 120×36 box on canvas and in SVG. Decide: auto-grow frames
on commit, or draw overflow with a subtle fade/indicator.

### A10 (P2) `zoomToFit` initial timing hack
`showWindow` defers via `DispatchQueue.main.async` with
`didApplyInitialZoom`; with restored window frames the scroll view may
not be laid out on the first pass. Fit on first `layout()`/`viewDidLayout`
instead.

### A11 (P2) Blocking file I/O for image paste
`pasteImage(from:)` reads `Data(contentsOf: fileURL)` synchronously on
the main thread after only a size check. Move the read into the detached
task that builds the rendition.

### A12 (P3) Infinite canvas never shrinks
`editingCanvasBounds` only unions (by design, so drags stay stable).
A stray drag to x=500k leaves a huge scrollable void. Shrink on gesture
end when content fits inside the visible rect + margin.

### A13 (P3) Cut/Copy edge cases
`copy:` gives no feedback when nothing was copied; `cut:` copies then
deletes even if the delete fails on a locked element, leaving clipboard
content the user believes was moved.

### A14 (P2) Transient inspector popover fights the color panel
The inspector popover uses `.transient` behavior (Palette.present). Clicking
a color well opens the shared color panel; the focus change can dismiss the
popover and discard the user's context. Use `.semitransient` for palettes
containing color wells (or drive color changes through the detached panel).
Verify on-device; if confirmed, the fix is one line in `Palette.present`.

### A15 (P3) Window title never reflects the file
`SionDocumentWindowController.init` sets `window.title` once from
`document.title` ("Untitled"); the archive also stores that title forever.
After Save As the title bar may not follow the file name. Let NSDocument's
display-name synchronization own the title and stamp `document.title` from
the file URL on save.

### A16 (P3) Selection includes children of hidden parents
`selectAll` filters `visible && editable`, but a hidden group's visible
children are still selectable; moving such a selection does not move the
hidden parent, so the group visually tears. Decide: hide-lock cascades
(hiding a group hides children) or document the independence.

## Performance

### P1 (P1) Full-scene `validate()` on every gesture update
`SceneEditor.apply` validates the entire document on every
`updateGesture` (each mouse event): full element copy, ID dictionary,
magnet expansion, cycle checks. For 1k+ elements this is real cost per
event. Options: structural checks per update + full validation only at
`endGesture`; or a validated-snapshot fast path. Must preserve the
atomic-rollback contract (`candidate != document` comparisons).

### P2 (P1) Route only what's visible
Even with the per-scene-state route cache (landed), a drag re-routes
every connector in the document, including far off-screen ones, and the
bounds pass routes all of them too. During gestures, restrict routing to
connectors whose endpoint hull intersects the visible model rect +
margin. (#29's culling may cover the draw side; the bounds side is
separate.)

### P3 (P2) Grid path rebuilt and stroked every frame
`drawGrid` rebuilds the full line path per redraw. Cache the path per
(extent, spacing, visible-rect bucket) or move the grid to a CALayer
invalidated on scroll/zoom change.

### P4 (P2) `expandedMagnets` recomputed everywhere
Resolved magnets are recomputed per validation pass, per selected-element
draw, per endpoint resolution, per toggle. `perSegment(5)` over a
64-vertex custom outline allocates ~320 magnets each time. Cache per
(magnetConfiguration, frame, rotation) in the controller.

### P5 (P3) Observer fan-out per frame
Inspector `refresh` and history mapping run on every observer
notification — cheap alone, but during gestures non-canvas observers
could coalesce to gesture end.

### P6 (P2) Save-time cost on the main thread
`data(ofType:)` runs canonical JSON encode, SVG export, Mermaid export,
pure-Swift SHA-256 over every entry (including up to 256 MB assets, with
a whole-file `[UInt8]` copy up front), ZIP write, and then a full
decode to verify — synchronously, and `autosavesInPlace` makes it fire
on every autosave tick. Options: hash via CryptoKit on Apple platforms
(keep the portable one for Linux), skip verify-decode for autosaves, or
capture state and encode off the main actor.

### P7 (P3) Stored ZIP keeps JSON history uncompressed
By spec every entry is STORED; scene.json plus up to 120 history
snapshots are highly compressible JSON. Accepted deliberately for
deterministic, dependency-free recovery — if archive size ever matters,
deflate for non-asset entries is a format-v2 decision with a spec note.

## Missing features (IDs are stable; work the P1/P2/P3 tags top-down)

### M2 (P1) Group / Ungroup (⌘G / ⇧⌘G)
`GroupContent`, `parentID`, `setParent`, `descendantIDs` all exist; no
UI. Group = transaction [insert group element with union frame +
setParent members]. Ungroup = [setParent(nil) for children + remove
group]. Needs selection semantics (group selects whole; ⌘click or
double-click enters), a visible group outline treatment, and marquee/
z-order rules from the archived M1. Connectors attached to members must keep working
(they reference element IDs, not groups).

### M3 (P1) Rotation + corner-radius inspector fields
The canvas now has rotation and corner-radius handles (landed with the
editor-interactions work), but the Inspector exposes neither. Numeric
angle field (0–360°, ⇧ snaps 15°) and radius field for rounded
rectangles.

### M4 (P2) Pen/freehand path tool
`PathContent`, `VectorPath` (move/line/quadratic/cubic/close, normalized
or local space), rendering, and magnet outline extraction all exist with
no way to create a path. Polyline pen: click vertices, Enter/Esc finish,
double-click close; store as `.path` with localPoints coordinates.

### M5 (P2) Alignment / smart guides + distribute
No snapping while moving (element edges/centers), no align/distribute
menu. With `elementIDsIntersecting` and `InteractionGeometry` in place,
guide hit testing is one pass over sibling frames; draw transient guide
lines in the overlay pass (same layer as the marquee).

### M6 (P2) Inspector gaps (modeled, not editable)
Shadow (color/blur/offset), opacity, blend mode, text style (font
family/size/weight/alignment/color), line dash, connector decorations,
image scaling mode, element name, visibility toggle, canvas settings
(background, grid spacing/subdivisions/visibility, fixed size). Lock
awareness landed; the rest is open. Grid settings belong with #35's
toggle — coordinate.

### M7 (P2) Export formats
PNG/PDF export: one `NSBitmapImageRep` / `dataWithPDF` pass over the
canvas draw path with content-bounds framing.

### M8 (P2) Drag & drop
No drop destination for image files (paste works); library inserts at
view center instead of the drop point; no NSItemProvider promises.

### M9 (P2) Context menu
Right-click menu: duplicate, delete, z-order, group/ungroup, lock/hide,
connector decorations on connectors, "edit text".

### M10 (P2) Zoom affordances
Zoom % readout (window subtitle or toolbar), ⌘+scroll zoom, smart zoom
on double-tap, toolbar zoom controls.

### M11 (P3) Text auto-sizing honored (see A9).

### M12 (P3) Shape library breadth
Model renders rectangle, rounded rect, ellipse, diamond, triangle,
hexagon, capsule, cylinder; the tool bar/library exposes rectangle,
circle, text. Add the rest as tool/library entries (Tool enum or a
shape picker palette).

### M13 (P3) Accessibility depth
The canvas is one AX group with a count summary; individual shapes are
not AX elements. NSAccessibilityElement per shape (frame, role, label);
keyboard traversal already exists.

### M14 (P3) Stencils, templates, recent colors.
Standard diagramming furniture; nothing exists today.

### M15 (P2) Paste step-aside (redo of the #30 idea)
Paste always lands at the visible center; repeated pastes stack
invisibly on top of each other. Step successive pastes one grid pitch
aside (cap ~8). Caveat from the #30 closure review: image paste finishes
asynchronously, so the offset must advance only after the insert
actually lands, never when the decode is merely queued.

### M16 (P1) Grid visibility toggle + snap-to-grid (redo of #35)
The adaptive grid renders (with subdivisions), but nothing in the UI can
show or hide it, and no interaction snaps. Add View > Show Grid
(persisted via `scene.canvas`) and View > Snap to Grid (session toggle,
default on). Closure review of #35 demands: test-first, per-drag
cumulative snapping (or absolute-origin snapping) so sub-cell deltas are
not lost, snap inside shared insert paths, and `@objc validateMenuItem`
for the checkmarks.

### M17 (P2) Click-click connector creation
Connector creation requires one continuous drag. Click source, move,
click target is the more forgiving interaction (and trackpad-friendly).
The connector drag state machine (`Drag.connector`) already keeps a live
preview; make mouse-down arm it and the second click commit.

### M18 (P2) Copy as PNG/SVG to the pasteboard
`copy:` writes only the private selection type plus plain text; pasting
a Sion selection into Keynote yields bare strings. Render the selection
to PNG (reuse the #37 offscreen render path over selection bounds) and
the SVG exporter's fragment onto the pasteboard alongside the private
type. Large interop win for a diagramming tool.

### M19 (P2) On-canvas connector label and route editing
`ConnectorContent.labelPosition` and `ManualConnectorRoute` (orthogonal
waypoints, curved/bezier controls) are modeled, routed, and persisted
with no editing gesture. Drag the label along the route; drag a route
segment to insert a waypoint; drag bezier handles when a bezier route is
selected. Anchor editing (endpoints/magnets) landed separately — this is
the path-shape layer.

### M20 (P2) Mermaid import fidelity
Import flattens to a fixed 3-column grid and ignores `direction`,
subgraphs, and arrow variants (`==>`, `-.->` import as plain arrows).
A layered (Sugiyama-lite) placement honoring direction would transform
imported diagrams; pairs with N2's live palette.

### M21 (P3) Outline/layers panel
Elements have `name` (with an unused `rename` command), groups, lock,
and visibility state. A fourth palette with an NSOutlineView listing
elements — name editing, eye/lock columns, drag to re-parent — is the
natural home for several features at once.

## Visual / aesthetics

### V1 (P2) Canvas ignores dark mode
Fixed light `SionColor.canvas` + `underPageBackground` page matte under
dark chrome. Either theme the surrounding chrome and default new
documents from appearance, or ship a dark canvas variant. If a dark
canvas lands, revisit the custom resize cursors' visibility (black SF
Symbols over dark backgrounds — add a contrasting halo then).

### V2 (P2) Magnet dots always shown on selection
Selection draws every magnet dot at all times — clutter that implies
interactivity that isn't there. Show magnets only when relevant (magnet
hover during connector drag, or a modifier).

### V3 (P2) Default grid hidden; empty-canvas onboarding
First launch is a blank expanse. A subtle dot grid by default plus a
fading hint ("⌘⌥L library · double-click text") that disappears on first
insertion. (#35 adds the visibility toggle; default + hint remain open.)

### V4 (P3) Selection styling
Dashed rect + square handles is serviceable but dated; solid 1.5–2pt
accent outline + circular white handles with accent ring + hover outline.

### V5 (P3) Connector drag affordances
While dragging a connector: highlight the hovered target shape, pulse
the nearest magnet dot inside snap tolerance, show the intended
attachment. Currently only a dashed preview path.

### V6 (P3) Toolbar aesthetics
Document title as subtitle, zoom % readout in the trailing group.

## Novel / delightful

### N1 "Tidy up" auto-layout (P2)
The router knows the topology. One button runs layered placement (rank
by longest path, order by connectivity, route orthogonally, snap to
grid). Highest-wow feature per effort in this codebase.

### N2 Mermaid live palette (P2)
Paste Mermaid already imports; export exists. A palette with a text
field re-importing per keystroke makes Sion a two-way Mermaid scratchpad.

### N3 Magnet gravity animation (P3)
When a connector endpoint enters a magnet's snap radius, animate the
snap (80 ms ease-out) instead of teleporting.

### N4 Element hop on connect (P3)
One-shot 120 ms scale-settle (1.00→1.02→1.00) on the target shape when a
connector is created; presentation-only transform, undo stays clean.

### N5 Spotlight for shapes (P3)
⌘⇧P palette: type "hex 200" → inserts a hexagon at view center.
Keyboard-first diagram building.

### N6 Minimap palette (P3)
Fourth PaletteKind: cached offscreen thumbnail + draggable viewport
rect. Pairs with A12's infinite-canvas navigation.

### N7 Ambient document stats (P3)
Window subtitle "12 shapes · 7 connectors" from the existing
accessibility-summary path.

### N8 Zen mode (P3)
⌘. hides chrome and dims non-selected elements to 30% while a selection
exists.

### N9 Snap tick sound, off by default (P3)
Subtle tick when alignment guides first engage (needs M5). Opt-in.
An `NSHapticFeedbackManager` tick is the trackpad-native variant; offer
either.

### N10 Print-to-scale for fixed canvases (P3)
Fixed extent + PDF export (M7) + NSPrintInfo gives real print dialogs.

### N11 Connector crossing hops (P3)
Orthogonal routes that cross unrelated connectors get small jump arcs —
the classic "pro diagramming" touch. Renderer-only: detect polyline
intersections between cached routes, insert arc segments at crossings.
Cache crossings alongside the route cache.

### N12 Sketch / hand-drawn stroke style (P3)
A `handDrawn` style flag rendering strokes with deterministic jitter
seeded by element ID (stable per element and export-stable). Charming
for wireframes; the SVG exporter can reproduce it with the same seed.
Format-additive (one style field) — needs a spec note.

### N13 Presentation mode (P3)
Full-screen, chrome hidden, arrow keys step through saved viewport
"scenes". Needs a scene-bookmark list in document extensions. A new
use-case, not just polish.

### N14 Paste-drag positioning (P3)
Hold after ⌘V to drag the pasted copy into place before committing the
transaction. Small state machine on top of insertSelectionPayload;
quirky and satisfying.

### N15 ASCII-art paste (P3)
Paste a box-drawing/ASCII diagram and get native shapes and connectors.
The parser is pure SionCore and testable on Linux; a signature quirky
feature.

### N16 QuickLook extension + Finder thumbnails (P3)
Generate from `previews/preview.png` now that #37 keeps it fresh. A
QuickLook preview extension reading the archive's stored PNG avoids any
render dependency.

## Code quality

### Q1 (P3) Split SionCanvasView
The view is ~2.2k lines mixing event interpretation, selection UI,
drawing, text-editing hosting, pasteboard, cursors, and coordinates.
Natural split: `SionCanvasRenderer` (pure draw), text-editing
coordinator, pasteboard controller. Do opportunistically with feature
PRs.

### Q2 (P3) No UI test infrastructure
SionCore coverage is excellent (160+ tests). No XCUITest or snapshot
tests exist; A2/A6/A7 (visual divergences) shipped because nothing
compares pixels. One offscreen-render snapshot test of a canned scene
would have caught all three.

### Q3 (P3) `SionArchiveGenerator.current` reads `Bundle.main` at type
init; test bundles report the fallback version. Harmless; consider
injecting the generator in tests.

---

## Archived: completed during the implementation rounds

### k3.md round (this document's second source)
- **A1 self-loops** (PR #43): `insertConnector` throws
  `ConnectorInsertionError.selfLoopNotSupported` when source == target.
  Remaining format-level idea: a `.connectorTargetsItself` validation case
  (needs a spec note) so hand-edited files reject them too.
- **A3 grid subdivisions** (PR #39): adaptive major/minor grid lines with
  legibility-driven collapsing.
- **Archive preview** (PR #37): `renderPreviewPNG` draws content bounds
  through a flipped-focus context; `data(ofType:)` refreshes a stale
  `previewPNG` before archiving; pixel-mapping tests pin origin and
  y-axis. Unblocks N16.
- **M1 Arrange + Duplicate** (PR #44): z-order as one block with boundary
  no-op detection, align/distribute over painted bounds, lock/unlock,
  hide/reveal (locked+hidden recoverable), power duplicate with offset
  repeat and cap; group records excluded from arrange semantics.
- **B6 text double-draw** (main): canvas skips text of the element being
  inline-edited (shape, standalone, connector label).
- **B7 dangling drag after mid-gesture undo** (PR #42): externally ended
  gestures recover the view's drag state.
- **#27/#29/#30/#35/#36 closed unmerged**: superseded by #22/#31/#38/#41/
  #42/#43 or deferred for test-first redos (see M15/M16 for the salvaged
  ideas and their closure caveats). SVG text wrap/parity is parked pending
  the compositing/export-parity pass (#45 lineage).

### glm.md round

- **PF1/PF2/PF5/PF6 render caches** (PR #22): per-scene-state connector
  route cache shared by bounds/draw/hit-testing (`SionEditorController`
  routeCache, cleared in `notifyModelChange`; selection-only
  notifications bypass), provider-based `editingCanvasBounds`
  (`SceneRenderGeometry.ConnectorRouteProvider`), NSCache image
  renditions (entry + decoded-byte cost limits), measured-text layout
  cache keyed by (content, style, half-point width bucket).
- **PF3 linear commands** (PR #20): translate/remove/reorder use one
  adjacency pass for descendants and one index map per command; tests
  pin multi-root groups, non-group-root mid-transaction semantics,
  locked-descendant rollback.
- **F1 marquee + B4 Escape** (PR #24): rubber-band selection (shapes by
  frame, connectors by route crossing), Shift sampled at mouse-up,
  `elementIDsIntersecting(_:)` on the controller with tests, Escape
  cancels text editing → live gesture → selection (`cancelInteraction`),
  `select(Set)` prunes unknown IDs.
- **V1 cursors** (PR #25): crosshair for creation tools, open/closed
  hand for moves, diagonal SF-Symbol resize cursors for corner handles
  (axis cursors for edges), tracking-area + `resetCursorRects`
  coexistence, `.activeInActiveApp`, drag-aware enter/exit,
  topmost-under-pointer refresh on state change.
- **B2 grid at zoom** (PR #31): grid lines stay on true model spacing,
  fade between 12pt and 6pt screen spacing, hairline width divided by
  magnification, KVO redraw on magnification change.
- **B1 rotation awareness** (PR #32, closed as superseded by #19's
  InteractionGeometry): rotation-aware resize with opposite-handle
  anchoring, rotation + corner-radius handles, rotated hit testing —
  landed on main via the editor-interactions work; the shape-precise
  remainder is A5 above.
- **F2/F3 duplicate + z-order** (PR #28, closed pending stronger
  semantics — those semantics landed as #44, see the k3 archive):
  ready-made controller methods and tests live in that PR's
  history (`duplicateSelection`, `changeSelectionZOrder`,
  `insertSelectionPayload(actionName:)`).
- Also landed from parallel work (context for future items): creation
  drag placement, connector anchor editing with magnet editing tools,
  8-way resize handles, lock-aware Inspector (#34), autosave checkpoint
  and display-PNG validation fixes.
