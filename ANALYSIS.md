# Sion implementation backlog

Source audit: `sol.md` at `531b9f3` against v0.2.0, reconciled with
`origin/main` at `9ea715d`. This file contains unfinished work only. Recheck
main before starting an entry; each change still lands through its own PR.

## Working rules

- Preserve the dependency chain: AppKit view → editor controller → SionCore
  use case → model/geometry → archive drivers. UI code issues semantic commands;
  it never mutates scene arrays or ZIP data.
- Keep canonical coordinates top-left/y-down. Convert only at AppKit boundaries.
- One user intent produces one atomic transaction and one undo entry. A rejected
  transaction leaves the document, selection, clipboard, and controls coherent.
- Never silently approximate a declared format feature. Implement it, reject it,
  or report the loss.
- Write a failing regression before a bug fix. Run `swift test`; AppKit changes
  also require macOS `scripts/build.sh` CI and GLM review.
- Measure complete gestures and visible frames. Microbenchmarks alone do not
  prove interactive performance.

## P0 — correctness and interaction cost

### P0.1 Replace per-sample scene transactions with a preview pipeline

**Evidence.** Each pointer update and text keystroke copies the document,
executes a command, validates the whole scene, compares whole values, notifies
all observers, recomputes bounds/routes, and invalidates the canvas
(`SceneEditor.apply`, `SionEditorController`, `SionCanvasView`). Existing route,
image, and text caches reduce repeated mechanics but not this transaction
fanout; Inspector refresh and History mapping also run on gesture notifications.

**Scope.** Build revision-scoped element, parent, and connector indexes. Keep
move/resize/rotate/radius previews in transient view state, repaint only their
dirty bounds, then submit one validated semantic transaction at mouse-up. Emit
typed change sets containing changed IDs and old/new painted bounds. Coalesce
non-canvas observers until commit.

```text
pointer samples → transient overlay → dirty viewport repaint
                                      │
mouse-up ───────→ one validated transaction + one undo entry
                                      │
                             changed IDs + bounds
```

**Accept.** Cancel restores the exact starting document; commit and undo each
notify once; one gesture creates at most one undo entry. Fixtures at 1,000,
10,000, and 25,000 elements show work proportional to the changed set, with
frame-time and allocation results recorded before and after.

**Depends.** P0.2 and P0.3 should consume the same revision/change-set API. Do
not mix this contract change with visual feature work.

### P0.2 Cull and invalidate painting by painted bounds

**Evidence.** `SionCanvasView.draw(_:)` walks the full scene and largely ignores
`dirtyRect`; paths and gradients are rebuilt even offscreen. Whole-view
`needsDisplay` calls remain common. The adaptive grid bounds its line count but
still reconstructs paths on each draw.

**Scope.** Add a revision-scoped spatial index keyed by conservative painted
bounds. Query the visible model rect intersected with the dirty rect, preserve
stable z-order, and cache immutable shape/path/gradient artifacts. Invalidate
tiles or layers only where a typed change set says pixels can differ. Cache grid
paths by extent, effective lattice, magnification bucket, and viewport bucket.

**Accept.** Offscreen elements are not traversed or rendered; culling never
drops rotated paths, wide strokes, shadows, labels, or connector markers.
Pan/zoom fixtures with 25,000 elements and 100 images remain visually identical
to an uncullable reference and report bounded frame work.

**Depends.** P0.1 supplies revision/change sets. This entry owns the shared
spatial index; P0.3 consumes it. Use `SceneRenderGeometry.paintedBounds`.

### P0.3 Create one routing/render context per geometry revision

**Evidence.** A scene-state route cache exists, but any geometry mutation can
still rebuild every route. Bounds and drawing can request all connectors, each
route scans all obstacles, and orthogonal routing can construct 16,384 nodes
before falling back. Obstacle and fallback boundary geometry remains
rectangle-based for rotated shapes. Expanded magnets are recomputed at several
call sites; `perSegment(5)` on a 64-vertex outline allocates about 320 magnets.

**Scope.** Create an immutable render context owning a spatial obstacle index,
expanded-magnet cache, and connector routes. Resolve routes lazily: painting
requests only corridor candidates intersecting the visible dirty model rect,
and extent/bounds queries must not eagerly route every connector each frame.
Invalidate connectors attached to changed endpoints or whose route corridor
intersects changed painted bounds. During a drag, render a cheap provisional
path for affected connectors and refine once at commit. Keep conservative
painted-bound obstacles in this work; P1.5 later supplies tighter shape-aware
boundaries. Make router quality degradation explicit rather than an abrupt
hidden fallback.

**Accept.** Tests pin selective invalidation, moved endpoints, moved obstacles,
rotated obstacles, fallback determinism, and bounds/draw route reuse. Benchmarks
cover 100 and 500 connectors in sparse and dense scenes; moving one remote node
does not route unrelated connectors. Panning routes only newly visible
candidates; a bounds-only pass does not route offscreen connectors.

**Depends.** P0.1 supplies revision/change sets; P0.2 supplies the shared
spatial index. P1.5 owns tighter shape geometry. Preserve
`ConnectorRouteProvider` as the high-level boundary.

### P0.4 Define and implement hierarchy semantics

**Evidence.** `parentID`, `GroupContent`, and `GroupClipping.clipToBounds` are
stored and validated, but Canvas/SVG render a flat array. Groups paint nothing;
parent visibility, clipping, selection, and lock inheritance are undefined.
Flat arrange/hide operations therefore cannot be correct for nested content.

**Scope.** Write the normative rules first: traversal/z-order, group frame,
clipping, inherited visibility, lock behavior, selection entry, and command
ownership. Implement one hierarchy traversal and clip stack concept shared by
Canvas and SVG, then route all group-aware commands through SionCore.

**Accept.** Portable and pixel/SVG tests cover cycles, nested clips, hidden
parents, locked ancestors, group-plus-child selection, reorder, duplicate,
delete, undo, and connectors attached to descendants. No child draws or
receives hit/accessibility focus outside an active ancestor clip.

**Depends.** Resolve D2 before lock behavior. Group/Ungroup UI is P2.1.

## P1 — fidelity, reliability, and responsiveness

### P1.1 Make document and asset work asynchronous and cancellable

**Evidence.** Save synchronously routes, renders preview/recovery outputs,
hashes assets, writes a stored ZIP, and decodes it again. File-image paste reads
up to 256 MiB on the main thread. Selection copy rejects guaranteed asset
overflow cheaply, but exact sizing still base64-encodes assets before the final
output limit. Rendition jobs lack ordering, progress, and cancellation.
Validation rehashes and reparses identical assets; SHA conversion copies `Data`
into bytes and PNG validation concatenates buffers. New archive previews are
supplied by a live canvas, so a windowless save cannot create one.

**Scope.** Snapshot small immutable state on the main actor, then move
encoding/import to cancellable services. Stream SHA and ZIP I/O. Keep STORED as
the v1 archive contract; evaluate deflating non-asset entries only as a
format-v2 change with a spec note and deterministic recovery tests. Preflight
the complete clipboard payload beyond the shipped asset-overflow guard, or
encode through a bounded sink. Deduplicate verified asset metadata and keep a
derived-save cache by document revision. Give paste jobs stable ordering and
cancel them on close or replacement. Move preview generation behind the same
renderer service so headless saves do not depend on window/view lifecycle.

**Accept.** Save/open and file paste keep the main actor responsive; progress
and precise errors are visible; cancelled or out-of-order jobs cannot insert or
overwrite content. Tests cover size limits, close-during-import, repeated
assets, malformed bytes, cancellation, and a save/reopen round trip with 120
history entries. Windowed and windowless saves produce equivalent previews.

**Depends.** Keep archive parsing and image validation below document/UI
layers. Preview rendering is already provider-backed and must remain
selection-independent.

### P1.2 Bound undo and recovery history by bytes

**Evidence.** Live undo retains up to 100 whole-document scene values; archive
history retains up to 120 encoded scene snapshots. Count limits do not bound
memory or archive bytes for large element arrays, paths, text, or extensions.

**Scope.** Store semantic inverse/delta commands or structurally shared scene
revisions. Enforce separate byte budgets for live undo and recovery history;
coalesce continuous gestures and key repeat while retaining named user intents.

**Accept.** Small geometry edits do not retain a distinct full element array or
encoded scene per revision. Eviction is deterministic and never removes the
current state; undo/redo and archive recovery survive budget boundaries. Record
peak memory, archive bytes, and save time for a 120-revision large-scene/path
fixture.

**Depends.** Prefer the command/change-set contract from P0.1.

### P1.3 Complete shadow semantics

**Evidence.** Canvas and SVG render only the first `ShadowStyle`; later shadows
and spread are ignored during painting. Shadow offsets now remain in canvas
space across Canvas, SVG, and shared painted bounds. Format v1 does not define
array compositing direction or spread geometry.

**Scope.** Define array compositing direction and signed spread geometry without
changing the canvas-space offset rule. Then implement all shadows and spread in
Canvas, SVG, and
`SceneRenderGeometry.paintedBounds`. If faithful support is not viable, add a
format decision and explicit export warning instead of substitution.

**Accept.** Renderer fixtures prove multi-shadow ordering, spread, opacity,
and x/y offset parity for rotated and unrotated elements. Positive and negative
spread fixtures prove Fit/export/culling bounds. Pixel samples and SVG fixtures
agree within documented antialiasing tolerance.

**Depends.** Build on the shipped single artwork group and P1.7's renderer
harness. D4 governs rejection or warnings if the format is narrowed.

### P1.4 Unify text layout, editing, auto-sizing, and SVG output

**Evidence.** `TextAutoSizing.fitHeight` and `.fitWidthAndHeight` are modeled but
inert. Paint clamps to the frame; connector labels use a small fixed frame.
Default connector insets leave roughly 12 points of content height. Editing
forces symmetric insets while committed rendering supports four edges. SVG
wraps only at explicit newlines, hardcodes leading, and maps justification to
start.

**Scope.** Introduce one measured layout abstraction for standalone text, shape
labels, and connector labels. Honor four-edge insets, font/alignment, line and
paragraph spacing, wrapping, vertical placement, and all auto-size modes.
Apply frame growth only on a semantic commit; expose overflow before commit.
Make Canvas editor geometry, Canvas paint, bounds, SVG, and preview consume the
same layout result or a conformance-equivalent representation.

**Accept.** Edit and commit do not jump; fixed mode shows a defined overflow
indicator; fit modes grow deterministically and undo once. Fixtures cover long
words, Unicode, explicit newlines, empty text, each alignment, connector
labels, rotations, and Canvas/SVG/bounds parity.

**Depends.** Preserve the exact nil/empty edit semantics already shipped.

### P1.5 Use shape-aware hit testing and obstacle geometry

**Evidence.** Rotation-aware local-frame hit testing exists, but ellipses,
diamonds, triangles, cylinders, and custom paths still claim transparent frame
corners. Routing protects painted protrusions with conservative rotated bounds,
but over-avoids transparent corners of nonrectangular shapes.

**Scope.** Put reusable shape/path geometry in SionCore. Use bounds for broad
phase, then fill-rule and stroked-path tests in local coordinates. Add
click-cycling for intentional overlap selection. Feed the same painted outline
or a conservative rotated hull to routing.

**Accept.** Transparent corners select visible content below; stroke-only and
open paths remain selectable within tolerance; rotations and nonzero origins
work. Repeated click cycling is deterministic. Router tests prove safe, tighter
clearance around rotated diamond, ellipse, and custom-path fixtures.

**Depends.** Share artifact/index work with P0.2/P0.3; do not expose AppKit
`NSBezierPath` through the controller.

### P1.7 Establish renderer conformance and performance gates

**Evidence.** Core coverage is broad, and recent compositing/bounds work
established deterministic offscreen Canvas pixel tests plus focused SVG
structure tests. A complete `BlendMode` matrix now pins portable SVG properties
and fixed-sRGB Canvas pixels against Core Graphics. Focused Canvas coverage also
verifies quadratic continuation after a closed subpath. Other renderer enums,
direct Canvas/SVG comparison, an XCUITest suite, and performance threshold gates
remain untested.

**Scope.** Extend those harnesses with compact portable SVG and deterministic
offscreen macOS pixel fixtures for every shape, path, fill, stroke, shadow,
blend, text mode, image mode, connector route, and decoration. Add `os_signpost`
spans for input, validation, routing, layout, paint, save, and open.

**Accept.** CI detects semantic drift without brittle whole-window snapshots.
Performance fixtures cover drag/typing at 1k/10k/25k elements, 100/500
connectors, pan/zoom with 100 images, save/open with 120 revisions, peak
allocations, archive bytes, and missed frames. Store baselines and explicit
regression thresholds. Use asymmetric glyph fixtures in Canvas and archive
previews so mirrored or upside-down text fails.

**Depends.** Tests must use sRGB, explicit flipped context setup, fixed scale,
and documented pixel tolerances.

### P1.8 Replace silent command failures with coherent feedback

**Evidence.** Inspector controls now restore model values after a rejected
semantic edit. Canvas and other palette paths still often use `try?` plus
`NSSound.beep()`. Arrange logs and beeps, but most failures have no stable
user-facing explanation.

**Scope.** Add one typed editor-result/feedback channel. Roll controls back to
model values and show a compact nonmodal banner with details or retry when
actionable. Preflight any future intent spanning model and system state before
visible mutation. Keep sound optional and never the only signal.

**Accept.** Locked, invalid, oversized, unsupported, and I/O failures have
specific messages and VoiceOver announcements. Tests pin document, selection,
undo, and control state after each failure. Successful commands do not create
duplicate announcements.

**Depends.** Reuse typed model errors; accessibility delivery joins P2.7.

### P1.10 Correct the cylinder primitive

**Evidence.** Canvas and SVG cylinder paths bulge the top rim upward and bottom
rim downward but omit the front arc of the top ellipse dipping into the body,
so the database symbol reads as a barrel.

**Scope.** Define one platform-neutral cylinder outline/rim recipe, then map it
to Canvas and SVG paths. Keep fill, stroke, hit testing, magnets, and bounds in
agreement.

**Accept.** Geometry tests pin the body and both visible rim arcs at wide,
square, and tall aspect ratios; Canvas pixels and SVG commands agree under
rotation and thick strokes.

**Depends.** Reuse P1.5 shape geometry and P1.7 fixtures.

### P1.11 Define connector decoration appearance once

**Evidence.** Canvas and SVG now share the same paint rule: open arrows are
stroked, closed decorations are filled with the connector stroke color, and a
nil or zero-width stroke paints no decoration. Scale and anchoring still
diverge: Canvas uses fixed point geometry while SVG markers scale with stroke
width, and the two renderers place diamonds differently. Connector hit testing
also excludes decoration lobes.

**Scope.** Unify fixed Canvas geometry with stroke-scaled SVG markers, including
diamond anchoring, and include decoration lobes in connector hit testing.
Implement one geometry description consumed by Canvas, SVG, hit testing, and
bounds.

**Accept.** A matrix covers none/open arrow/filled arrow/circle/diamond at each
endpoint, short segments, diagonals, opacity, thick strokes, and all line caps.
Canvas pixels and SVG fixtures show the same fill/stroke contract.

**Depends.** Build on shipped whole-element compositing and P1.7 fixtures.

## P2 — editing surface and native product

### P2.1 Expose grouping only after hierarchy works

**Evidence.** `setParent`, `descendantIDs`, and group content exist without
Group/Ungroup UI.

**Scope.** Group inserts one group from the union of selected roots' painted
bounds and reparents only top-level selected roots. Ungroup reparents direct
children and removes the container atomically. Define single-click group
selection and an explicit way to enter/select descendants. Add group outline
and clipping controls.

**Accept.** ⌘G/⇧⌘G, menus, context menus, and accessibility actions share one
capability predicate. Nested groups, connectors attached to children, undo,
reorder, marquee, duplicate, locked/hidden members, and selection restoration
are covered.

**Depends.** P0.4 and D2.

### P2.2 Add smart guides, grid snap, lasso, pan, and autoscroll

**Evidence.** Adaptive subdivision rendering and marquee selection exist, but
move/resize does not snap to grid, edges, centers, or equal spacing. There are
no visible snap toggles, lasso, spacebar hand tool, or drag autoscroll.

**Scope.** Land three focused PRs. First compute snap/guide candidates from
sibling painted bounds through the shared spatial index, apply model-space
tolerances derived from screen points, render transient guides, and add Snap to
Grid/Smart Guides toggles plus modifier bypass. Second add polygon lasso using
shape/path geometry. Third add spacebar pan and edge-triggered autoscroll.
Keep Snap to Grid as a validated session toggle. Snap from the drag origin or
cumulative delta so sub-cell samples are not lost, and reuse the placement
policy in every insert path.

**Accept.** Snapping is zoom-independent, deterministic under ties, disabled
when requested, and does not enter undo separately. Tests cover rotated/wide
effects, multi-selection, fixed/infinite canvases, autoscroll in every
direction, and lasso crossings. Guides meet contrast and Reduce Transparency
settings. Menu checkmarks, repeated sub-cell updates, and
shape/image/Mermaid/text insertion are covered.

**Depends.** P0.2's spatial index, P0.1's overlay pipeline, and P1.5 geometry
for lasso precision.

### P2.3 Expand the Inspector with mixed-value editing

**Evidence.** Lock-aware controls exist, but the UI exposes only a small subset
of modeled state. Missing fields include rotation, rounded-corner radius,
shadow, opacity, blend, text style, dash/cap/join, connector decorations,
image scaling/interpolation/description, element name, visibility, and canvas
background/extent/grid settings. The transient Inspector popover may dismiss
when its color well opens the shared color panel.

**Scope.** Build a scrollable, sectioned Inspector for Geometry, Text,
Connector, Appearance, Image, and Canvas. Show mixed values explicitly; batch
changes through one semantic command. Add numeric angle 0–360° with 15° Shift
snap, radius bounds, accessible units, and aligned `NSGridView` columns.
Reproduce the color-panel focus transition on macOS; if confirmed, use
semitransient palette behavior or a detached color workflow.

**Accept.** Single and mixed selection tests cover enablement, lock state,
validation rollback, one undo step, tab order, field formatting, and palette
retargeting between documents. Canvas-only settings never leak into element
commands. Opening, dragging, and closing the color panel preserves Inspector
context and target.

**Depends.** P1.8 feedback; group visibility/lock fields wait for P0.4/D2.

### P2.4 Add direct connector editing and better connect feedback

**Evidence.** Creation, magnet attachment, and custom anchor editing exist, but
users cannot directly detach/reattach endpoints, edit manual bends/control
points, move label position, or choose decorations from the canvas. Connector
drag shows only a dashed preview; all magnet dots clutter every selection.

**Scope.** Add endpoint and route handles for orthogonal, curved, and Bézier
manual routes; route/decorations/label-position controls; detach and reattach;
and semantic reset to automatic routing. During connect, highlight the hovered
shape and pulse only the nearest eligible magnet within tolerance. Otherwise
hide magnets until relevant or modified. Offer click-source, move,
click-target creation beside press-drag, with Escape cancellation, through the
same connector state machine.

**Accept.** Editing preserves endpoint IDs and fallback points, invalidates only
the affected route, creates one undo entry, and survives target deletion.
Hit-testing works at every zoom and rotation. Visual feedback respects Reduce
Motion and never obscures the eventual attachment. Both creation modes share
preview, snapping, fallback-point, and undo behavior.

**Depends.** P0.3 routing context and P1.5 shape geometry.

### P2.5 Add a pen/path creation tool

**Evidence.** `PathContent` and `VectorPath` support move, line, quadratic,
cubic, close, normalized/local coordinates, rendering, and magnet extraction;
the UI cannot create them.

**Scope.** Start with a polyline pen: click vertices, drag optional handles,
Enter/double-click commits, Escape cancels, and clicking the first point closes.
Store local-point coordinates and normalize only through an explicit command.
Follow with pressure-free sampled freehand smoothing as a separate PR.

**Accept.** Open/closed, zero-length, resize/rotation, fill-rule, undo, cancel,
serialization, SVG, hit-test, and magnet fixtures pass. One path gesture creates
one element and undo entry.

**Depends.** Reuse P1.5 path geometry and P0.1 gesture state.

### P2.6 Improve import, drag/drop, and repeated paste placement

**Evidence.** Paste accepts images/Mermaid/text, but the canvas is not a drop
destination and Library insertion uses view center. Repeated successful pastes
stack exactly. A safe sequence must not advance before asynchronous image
insertion completes or carry offsets across clipboard identities.

**Scope.** Add `NSDraggingDestination`/item-provider imports with a drop-point
preview. Track a paste sequence by pasteboard `changeCount` or payload identity
plus a tolerant viewport anchor. Offset only after confirmed insertion, cap the
diagonal sequence, reset for new content, and preserve async job ordering.

**Accept.** Payload, image, Mermaid, and text drops land at the pointer. The
second identical paste steps aside; new clipboard content starts at center;
subpixel scroll does not reset; meaningful navigation does; failed/cancelled
imports do not consume an offset.

**Depends.** P1.1 async services and P1.8 feedback.

### P2.7 Build object-level accessibility

**Evidence.** The canvas exposes one AX group with element and selection counts;
VoiceOver cannot inspect, traverse, or edit objects.

**Scope.** Expose virtual `NSAccessibilityElement` children for rendered
viewport objects with role, type, name/text/image description, screen frame,
selected/locked state, and connector endpoint/direction summaries. Add
select, edit, move, delete, enter-group, and traversal actions plus logical
focus repair after insertion/deletion. Announce selection, errors, and document
changes. Respect Reduce Motion, Increase Contrast, and Reduce Transparency.

**Accept.** Automated AX tests cover tree order, clipped/hidden descendants,
actions, focus, announcements, multiple documents, and scrolling. Canvas AX
omits hidden or fully clipped descendants; Layers may expose them as hidden.
Every mouse editing path has a keyboard equivalent and no feedback is
sound-only.

**Depends.** P0.2 viewport query, P0.4 hierarchy, and P1.8 feedback.

### P2.8 Replace the fixed Library with shapes, styles, and stencils

**Evidence.** `ShapeKind` renders eight built-in primitives plus custom paths.
The toolbar exposes rounded rectangle and ellipse; Library exposes all eight
built-in primitives at the viewport center. Custom paths have no creation
surface. There are no reusable stencils, recent colors, favorites, or style
tokens.

**Scope.** Build a searchable keyboard-accessible icon grid for every built-in
shape, then add drag-to-place, recent/favorite styles, reusable user stencils,
and named node/connector style tokens. Offer contrast-aware text colors without
silently changing stored styles.

**Accept.** Every built-in shape inserts at click, drag frame, keyboard center,
and drop point; search/favorites persist; stencil asset references round-trip
safely; all controls have labels and full keyboard navigation.

**Depends.** P2.6 for drop placement; P2.3 for style editing.

### P2.9 Add Layers/Outline and minimap navigation

**Evidence.** There is no searchable hierarchy or overview for large/infinite
documents. Visibility, lock, rename, parentage, and z-order are hard to inspect.

**Scope.** Add a selection-synchronized outline with hierarchy, search, rename,
visibility, lock, and drag reorder. Pair it with a cached offscreen minimap and
draggable viewport rectangle. Virtualize rows and request thumbnails/render
artifacts through high-level providers.

**Accept.** Nested reparent/reorder is atomic and capability-checked; hidden and
locked states are recoverable; canvas/outline focus stays synchronized; 25,000
elements do not create 25,000 live views. Minimap drag preserves model center
at every zoom.

**Depends.** P0.4 hierarchy, P0.2 spatial/render artifacts, P1.1 renderer
service, and D2 lock semantics.

### P2.10 Turn History into an inspectable restore browser

**Evidence.** History controls restore immediately without preview, diff,
current marker, or confirmation. Archives now persist a deterministic preview,
but revision-level thumbnails and summaries are not exposed.

**Scope.** Add a selectable revision list with timestamp, current marker,
thumbnail, and changed-element summary. Require explicit Restore; provide Open
as Copy. Generate/cache previews off the main actor and tolerate a missing or
corrupt preview without losing the revision.

**Accept.** Selecting a row never mutates the document; Restore is one undoable
intent or a clearly documented history boundary; Open as Copy preserves the
source. Large histories scroll smoothly and cancellation closes all jobs.

**Depends.** P1.1 async pipeline and P1.2 byte-budgeted revisions.

### P2.11 Improve zoom, extent, and ambient status

**Evidence.** Toolbar zoom commands expose the live magnification percentage,
and populated windows apply initial Fit synchronously after their first usable
layout without overwriting later zoom input. Infinite canvas bounds only grow,
and there are no dimensions, selection summary, or explicit fit target. A stray
drag can leave hundreds of thousands of points of empty space.

**Scope.** Apply initial zoom after the first valid layout. Add zoom percentage,
⌘-scroll and double-tap smart zoom, selection coordinates/dimensions, and
compact document stats. Put zoom and ambient status in the toolbar or native
subtitle, never on the canvas. Shrink infinite bounds after gestures when
content and viewport fit inside a named margin while preserving the visible
center. Expose Fit Page, Fit Drawing, and Fit Selection once D3 is resolved.

**Accept.** Restored/new windows fit deterministically; zoom centers on the
pointer or chosen target; bounds never move under an active pointer; post-drag
shrink removes remote void without jumping; VoiceOver receives status changes.

**Depends.** Painted bounds are available; D3 selects command naming/semantics.

### P2.12 Add context, command, and search surfaces

**Evidence.** Common operations require palettes or undiscoverable shortcuts;
there is no contextual menu, command palette, object search, or jump-to-object.

**Scope.** Build one capability registry consumed by menus, context menus,
toolbar validation, and a ⌘⇧P command palette. Include edit text, duplicate,
delete, arrange, group, lock/hide, connector options, shape insertion, search,
and jump. A compact grammar may support commands such as `hex 200` without
bypassing semantic controllers.

**Accept.** Every surface has identical enablement and error behavior. Keyboard
search moves logical and canvas focus, reveals the target, and remains usable
with hidden/locked/grouped objects under their defined policies.

**Depends.** P1.8 feedback and relevant editing commands; P0.4 for groups.

### P2.13 Make the first-run canvas legible and useful

**Evidence.** A new document is a blank light expanse. The grid defaults hidden,
there is no editable sample, and toolbar creation omits most shapes.

**Scope.** Test a subtle dot/subdivision grid default and a short fading hint
for Library, text, and connectors. Add templates, a disposable editable
onboarding diagram, and a small sample gallery. Persist dismissal without
embedding tutorial state in document data.

**Accept.** Onboarding is keyboard/VoiceOver operable, disappears after the
first meaningful insertion or explicit dismissal, never contaminates undo or
saved files, and remains legible in both appearances.

**Depends.** D5 decides the new-document grid/default appearance; P2.8 supplies
Library and P2.14 appearance.

### P2.14 Refresh canvas chrome and appearance

**Evidence.** New documents use a fixed light canvas color under adaptive
system chrome, and there is no app-level canvas appearance mode. Selection uses
a dashed rectangle and square handles; selected shapes always show every
magnet, and the connector tool shows magnets on every visible shape. Custom
black resize cursors can disappear on dark backgrounds. The detailed castle
icon is weak at 16 px.

**Scope.** Define system-aware page/matte colors or an explicit dark-canvas
mode. Use a restrained solid accent selection outline, circular white/accent
handles, hover outlines, and contrasting cursor halos. Create simplified small
icon variants. Respect contrast/transparency settings.

**Accept.** Pixel/contrast checks cover light, dark, Increase Contrast, and
Reduce Transparency at common zooms; handles and cursors remain distinct over
black, white, saturated, and transparent artwork. No appearance change mutates
document colors unless explicitly requested.

**Depends.** P1.7 visual harness; connector-specific feedback and magnet
visibility are P2.4. D5 governs canvas/theme ownership.

### P2.15 Add export and print workflows

**Evidence.** User-facing SVG and Mermaid export exist, but users lack PNG,
PDF, JPEG, save-panel type enforcement, Page Setup, and print-to-scale. Copy
exposes only Sion's private selection payload and plain text, so other design
apps receive no artwork.

**Scope.** Extend the P1.1 renderer service to frame content, page, or selection
and export PNG at explicit scale, color space, and transparency; vector PDF;
and quality-controlled JPEG. Add extension/type validation. For fixed canvases,
map document units to `NSPrintInfo` with named scale/fit policies. Also publish
selection-framed PNG and SVG pasteboard representations, without selection or
grid chrome, while retaining the private payload.

**Accept.** Dimensions, orientation, bounds, color space, transparency,
metadata, extension, and multi-page print tiling are deterministic. Export has
no selection/grid chrome unless requested and runs cancellably off the main
actor. Keynote-style consumers receive artwork; Sion-to-Sion paste retains
editable objects.

**Depends.** Shipped compositing plus P1.3/P1.4 fidelity, P1.1 async service,
and D3 framing terms.

### P2.16 Honor Mermaid direction and topology

**Evidence.** `MermaidImporter` honors TB/TD/BT/LR/RL direction in its simple
order-based grid, but does not rank nodes from graph topology. Unsupported,
malformed, and unparsed statements are skipped without import diagnostics.
Subgraphs and arrow variants such as `==>` and `-.->` are ignored or flattened.
Valid same-line statements after a header are rejected as a whole rather than
partially imported.

**Scope.** Build a deterministic layered graph layout: rank by topology, order
to reduce crossings, honor direction, reserve node/label bounds, and define a
stable strongly-connected-component fallback. Keep parsing and layout separate.
Return a structured deterministic import report and warn or reject before
partial insertion. Preserve supported arrow semantics and include every
ignored statement/type and count in the structured omission report.

**Accept.** Fixtures cover every direction, branches, joins, disconnected
components, cycles, long labels, and stable repeated import. No nodes overlap;
edges begin with a usable route and the import is one undo step. Fixtures cover
ignored statements and malformed lines; cancelling leaves the document
unchanged. Subgraph and arrow-variant fixtures either import faithfully or
produce exact deterministic omissions.

**Depends.** P0.3 routing, P1.4 text bounds, P1.8 feedback, and D4 loss policy.
The same engine can seed X1.

### P2.17 Complete native app integration

**Evidence.** Standard Settings, Page Setup, and Print flows are incomplete.
`NSDocumentController` documents automatic Open Recent
insertion, but a native finished-launch probe found that a plain programmatic
submenu is not populated. A retained menu delegate now reads AppKit's document
history at display time and routes opening and clearing through the document
controller. Launch coverage injects URL/open/clear dependencies without
mutating persistent recent state. The Services submenu is registered for
AppKit-managed providers. Find and one-shot spelling commands work in the active
inline text editor; document-wide search/replacement and persistent spelling
preferences remain open. Window minimum size, localization hooks,
signing/notarization/update strategy, sandbox/file access, and
strict-concurrency migration of the AppKit targets remain open. `SionCore` and
its tests use Swift 6 language mode; the AppKit targets still inherit Swift 5
mode under the Swift 6.3.3 toolchain. Save As now keeps the native display name
and archived title synchronized without dirtying the document.
Revert to Saved now routes through `NSDocument`; archive reads discard pending
inline edits and restore canvas focus. The Help menu opens a localized bundled
help book; packaging generates and verifies its search index.

**Scope.** Add responder-chain menus and native panels in small PRs. Decide the
sandbox/security-scoped bookmark model, then configure Developer ID signing,
hardened runtime, notarization, and updates. Introduce localization keys. Enable
strict concurrency incrementally per target with actor/sendability fixes. Set a
tested minimum window size before the toolbar and palettes overlap.

**Accept.** Launch/menu/document smoke tests pass on supported macOS versions;
recent/revert/file-access behavior survives relaunch; release artifacts are
signed and notarized reproducibly; strict-concurrency diagnostics are clean at
the selected migration stage. Untitled, Save, Save As, reopen, and duplicate
windows show matching filenames and archive metadata.

**Depends.** P2.15 supplies Page Setup/Print. Treat sandbox choice as an
explicit product/security decision.

## Quality and maintainability

### Q1 Split `SionCanvasView` behind stable abstractions

**Evidence.** The view is nearly 3,000 lines spanning event interpretation,
drawing, selection chrome, text hosting, pasteboard, cursors, coordinates, and
preview rendering.

**Scope.** Extract a pure renderer façade, text-editing coordinator, paste/drop
coordinator, and interaction state machine as their owning features change.
Keep fields private and expose domain operations, not Core Graphics or raw
scene arrays.

**Accept.** Existing behavior tests remain unchanged; extracted components have
focused unit tests; no layer calls past its immediate lower neighbor. Avoid a
standalone rewrite PR unless a concrete feature needs the boundary.

**Depends.** Natural seams are P0.1, P0.2, P1.1, P1.4, and P2.6.

### Q2 Broaden automated robustness coverage

**Evidence.** There is no XCUITest target, accessibility action suite,
generated malformed-model corpus, launch gate, full renderer matrix, or
performance gate. A fixed-seed editor corpus now applies mixed shape,
connector, geometry, style, text, canvas, ordering, undo, and redo operations;
every state validates and canonical checkpoints round-trip deterministically.
Archive tests reject every truncated prefix and use fixed-seed minimal byte
mutations to prove deterministic rejection or valid recovery. Archive generator
metadata crosses a tested SionKit bundle boundary, and Core tests use fixed
provenance.

**Scope.** Add launch/document lifecycle UI tests, AX action tests, malformed
archive and model property/fuzz tests, and the renderer/performance fixtures in
P1.7. Inject archive generator/version metadata rather than reading global
bundle state in tests.

**Accept.** Tests reproduce fixed seeds, archive crashes produce minimal
fixtures, UI failures retain diagnostics, and no test depends on host bundle
version or animation timing.

**Depends.** P1.7 defines renderer/performance conventions.

## Product experiments

Each experiment starts as a reversible flag or prototype. Ship only after a
short usability test confirms the stated benefit.

### X1 Tidy Up auto-layout

Use graph topology to rank nodes, order by connectivity, place on the current
grid, and reroute orthogonally. Accept when a mixed branch/join fixture improves
overlap, crossing, and spacing metrics, is deterministic, previews before
commit, and undoes once. Reuse P2.16; do not hide destructive rearrangement.

### X2 Mermaid live palette

Add a debounced text palette that parses and previews Mermaid without mutating
the document, then applies one replace/insert transaction. Preserve the last
valid preview and show line-specific errors. Test fast typing, invalid→valid
recovery, cancellation, direction, and one-step undo. Depends on P2.16 for
direction-aware layout.

### X3 Quick-grow nodes

Dragging a connector into empty space opens a four-choice strip for Process,
Decision, Note, or Database; digits select and Escape cancels. Accept when the
new node and connector form one atomic undo step, keyboard and VoiceOver paths
match pointer use, and the strip never blocks ordinary free endpoints.

### X4 Diagram Doctor

Build read-only detectors for crossings, overlaps, clipped labels, dangling
connectors, weak contrast, and inconsistent spacing. Present evidence and a
previewable semantic fix per finding. Accept when findings are deterministic,
false-positive rates are recorded on a fixture corpus, and every fix is
reversible independently.

### X5 Keyboard graph authoring

Return adds a child, Tab a sibling, arrows traverse graph neighbors, and typing
edits immediately. Combine with command-palette insertion such as `hex 200`,
but retain standard text/keyboard conventions. Accept with cyclic/disconnected
graphs, group focus, screen-reader navigation, and single-step command tests.

### X6 Trace Flow

Prototype a restrained pulse along outgoing edges as an ephemeral overlay.
Disable motion under Reduce Motion. Accept when playback never changes document
or undo state, keyboard navigation works, and cycles terminate by policy.

### X7 Presentation paths

First decide whether named traversal steps are document content or app state.
If stored in the document, authoring must be undoable; playback never mutates
layout. Accept when keyboard/VoiceOver navigation works and export can include
or omit named steps explicitly. Prototype full-screen playback with chrome
hidden and arrow-key traversal of saved viewport steps.

### X8 Magnetic feedback

When a connector endpoint first enters snap radius, prototype an 80 ms overlay
ease-out into the magnet, a guide flare, and optional trackpad haptic; keep
sound off by default. Accept only if it improves snap recognition without
repeated events while staying inside tolerance. Respect Reduce Motion and user
preferences.

### X9 Target settle on connect

Test a one-shot 1.00→1.02→1.00 target settle after connect. Keep it ephemeral
and disable it under Reduce Motion. Accept only if rapid selection and repeated
connects never stack or disturb hit geometry.

### X10 Zen mode

Test a ⌘. mode that hides chrome and dims non-selected objects without changing
document state. Accept with no-selection, export, keyboard escape, contrast,
and multiple-window checks.

### X11 Connector crossing hops

Detect intersections between cached orthogonal routes and insert deterministic
jump arcs, excluding endpoints, shared segments, and selected crossings. Accept
with Canvas/SVG parity, stable z-order ownership, and routing-cache performance
fixtures.

### X12 Deterministic hand-drawn strokes

Prototype a format-additive style rendered with element-ID-seeded jitter shared
by Canvas and SVG. Accept when resize, zoom, export, reopen, and undo never
change the stroke and a spec note defines the field.

### X13 Paste-drag placement

Let a held paste gesture preview and position the inserted copy before one
commit. Accept when release commits once, Escape leaves document/history
unchanged, and asynchronous image paste preserves ordering.

### X14 ASCII-art import

Build a pure-SionCore parser for box-drawing and ASCII diagrams with a
structured ambiguity/loss report. Accept on mixed line styles, labels,
malformed input, deterministic layout, and one-step undo.

### X15 Quick Look and Finder thumbnails

Add an extension that reads `previews/preview.png` directly from the archive,
with bounded decoding and a safe fallback for missing or corrupt previews.
Accept when Finder thumbnail and Quick Look work without launching Sion and
never render stale selection chrome.

## Product decisions

Resolve these with a short format/UX note and tests before implementation.

### D1 Self-loop policy

Drawn same-element connectors are rejected, but imported/model-authored loops
can still exist and route degenerately. Choose either a real visible loop route
with attachment/obstacle rules, or a model/import validation error with a
lossless warning path. Test Mermaid `A --> A`, archive decoding, SVG recovery,
selection, deletion, and round-trip behavior.

### D2 Group lock and visibility ownership

Choose whether parent lock is inherited and whether hidden locked descendants
can always be recovered through Reveal All. Flat arrange/hide skip ineligible
locked items, and flat Reveal All restores directly hidden locked elements
without unlocking them; decide whether inherited locks preserve those
partial-operation rules or make hierarchy-aware commands reject atomically.
Also decide whether deleting an editable endpoint may cascade-delete its
attached locked connector. Capability predicates, commands, menus, Inspector,
Layers, rendering, and accessibility must use the same rules.

### D3 Fit and framing vocabulary

Do not overload “Zoom to Fit.” Prefer explicit Fit Page, Fit Drawing, and Fit
Selection, then use the same page/drawing/selection terms in export and print.
Define empty-document and hidden-element behavior.

### D4 Unsupported feature policy

For every format enum/case, choose faithful rendering, validation rejection, or
an explicit approximation warning. Apply the policy consistently to Canvas,
SVG recovery, Mermaid, preview, export, and future platform implementations.
Silent approximation is not an option. `MermaidCoverage` currently measures
element retention, not visual fidelity; decide whether to preserve that meaning
and add a separate deterministic approximation summary.

### D5 Infinite-canvas appearance

Choose whether document canvas color is content, an app theme, or both; whether
dark mode changes existing documents; and whether a new document shows a grid.
Migration must not alter authored colors without consent.

## Bounded discovery for larger capabilities

These are not implementation-ready product epics. The listed spike is the next
shovel-ready step.

### L1 Multi-page canvases, artboards, and shared layers

Draft a format extension and command model for page order, page size, shared
background/master layers, cross-page asset ownership, and export/print. Accept
the spike with canonical JSON examples, migration/unknown-field behavior, and
three command/undo walkthroughs; write no UI until the model is agreed.

### L2 Tables

Draft a semantic row/column/cell model rather than composing grouped
rectangles. Prototype resize, selection, merged cells, text overflow, keyboard
navigation, accessibility, serialization, undo, and SVG export. Choose no UI
architecture until those operations have deterministic examples.

### L3 Boolean shape operations

Prototype union, intersection, subtraction, and exclusion as derived paths that
retain editable sources. Accept when winding rules, transforms, strokes,
serialization, undo, and SVG round trips are deterministic on a compact corpus.

### L4 SVG import

Define a supported SVG subset and loss-report structure. Build a corpus that
measures faithful, approximated, and rejected inputs across paths, transforms,
text, gradients, clips, images, and filters. Accept when import is bounded,
deterministic, secure, and never claims silent fidelity.

### L5 Collaboration, comments, and sharing

Write an operation/identity/conflict model compatible with semantic commands;
prototype two clients editing the same small scene with offline replay. Accept
when ordering, deletion, asset transfer, permissions, comments, presence, share
links, undo ownership, and archive export have explicit behavior before choosing
transport.

### L6 External data links

Prototype read-only binding of CSV rows and edges to named element fields so a
small org/network diagram can refresh from a local snapshot. Define refresh,
stale/error, credential, offline, provenance, and undo rules. Accept when
refresh is deterministic, previewable, and never overwrites manual edits
without a declared conflict policy.
