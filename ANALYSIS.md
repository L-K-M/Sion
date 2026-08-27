# ANALYSIS.md — Sion review backlog

This document merges the full review originally written in `glm.md` (at
v0.2.0, commit 4194729) with everything learned during the follow-up
implementation round. Completed items are archived at the bottom without
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
| #29 | `perf/canvas-drawing` | draw culling + further redraw-cost cuts |
| #30 | `fix/canvas-interactions` | live-text double-draw, dangling drag after mid-gesture undo |
| #35 | `feat/grid-and-snap` | grid visibility toggle + snap-to-grid |
| #37 | `feat/archive-preview` | render archive preview PNG on save |
| #38 | `fix/painted-bounds` | include painted effects (shadows) in bounds |

## Bugs

### A1 (P1) Self-connecting connectors are still allowed
Drag a connector from a shape and release over the same shape:
`insertConnector` (SionEditorController) creates element→itself with no
validation to stop it, rendering as a zero-length stub. Reject when
`sourceID == targetID` (beep or no-op), or route a visible loop.
A `SceneValidationError` case (`.connectorTargetsItself`) is the
format-level fix; needs a spec note if added to validation.

### A2 (P1) Shadow direction on canvas vs SVG export needs a visual audit
Model is y-down; the default elevation shadow (`dy = +2`) renders
downward in exported SVG (`feDropShadow`). The canvas draws in a flipped
NSView and installs `NSShadow.shadowOffset` verbatim; NSShadow offsets
follow the unflipped base space, so the canvas shadow may render upward,
disagreeing with the export. Needs a screenshot on macOS; fix by negating
y when installing the shadow in flipped drawing. `applyShadow` also
ignores `ShadowStyle.spread`. (#38 may touch the same drawing path —
coordinate.)

### A3 (P2) Grid subdivisions are modeled but never rendered
`CanvasGrid.subdivisions` is validated, schema'd, and ignored by
`drawGrid` (one line per `spacing`). Render faint subdivision lines, or
drop the field in a schema version.

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

## Missing features (value-ordered)

### M1 (P1) Duplicate (⌘D) and z-order Arrange commands — needs a redo
A previous implementation (#28, then #33) was closed pending stronger
semantics. Requirements gathered from review of both:
- duplicate: copy selection onto itself, fresh IDs, diagonal offset,
  one undo step, copy becomes selection;
- z-order bring forward/backward/front/back moving multi-selections as
  one block (destination measured against the array with the block
  removed — matches `SceneCommand.reorder`);
- must handle: group hierarchies (a group+child selection must not
  double-move descendants), locked/hidden members (fail atomically or
  skip with feedback), capability checks consistent with execution,
  anchor-editing state cleared on arrange, and no-op detection at stack
  edges;
- `insertSelectionPayload` already accepts an `actionName:` (see git
  history of #28 for the ready-made controller methods and tests).

### M2 (P1) Group / Ungroup (⌘G / ⇧⌘G)
`GroupContent`, `parentID`, `setParent`, `descendantIDs` all exist; no
UI. Group = transaction [insert group element with union frame +
setParent members]. Ungroup = [setParent(nil) for children + remove
group]. Needs selection semantics (group selects whole; ⌘click or
double-click enters), a visible group outline treatment, and marquee/
z-order rules from M1. Connectors attached to members must keep working
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

### N10 Print-to-scale for fixed canvases (P3)
Fixed extent + PDF export (M7) + NSPrintInfo gives real print dialogs.

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

## Archived: completed during the glm.md round

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
- **F2/F3 duplicate + z-order** (PR #28, closed pending M1's stronger
  semantics): ready-made controller methods and tests live in that PR's
  history (`duplicateSelection`, `changeSelectionZOrder`,
  `insertSelectionPayload(actionName:)`).
- Also landed from parallel work (context for future items): creation
  drag placement, connector anchor editing with magnet editing tools,
  8-way resize handles, lock-aware Inspector (#34), autosave checkpoint
  and display-PNG validation fixes.
