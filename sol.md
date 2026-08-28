# Sion audit and execution ledger

Audited 2026-08-27 at `4194729` (`v0.2.0`). This is a source, test, and
workflow audit. Linux lacks Swift/AppKit, so macOS behavior and timing need CI
or device verification. Existing CI is green.

## Decision key

- **Ship**: bounded, verified value; implement now in its own PR.
- **Next**: sound direction, but needs a larger design or performance baseline.
- **Explore**: validate with users or prototypes before committing the model.
- **Incoming**: already covered by PR #19; verify after merge.

## What is already sound

- Clear `SionCore` / `SionKit` / app boundary.
- Deterministic commands, undo, validation, and document migration.
- Defensive ZIP parsing, canonical JSON, checksums, duplicate-key rejection,
  path validation, and recovery exports.
- Broad portable-core coverage and Linux/macOS CI.
- A compact native AppKit foundation without web-runtime overhead.

These are worth preserving. The main weaknesses are rendering fidelity,
interaction cost, feature exposure, and feedback when an operation fails.

## Incoming work

PR #19 adds persistent creation tools, direct connectors, guided anchors,
eight-way/aspect resize, rotation, corner radius, zoom controls, cursors, and
palette lifecycle fixes. Do not duplicate it. After merge, verify rotated hit
testing, obstacle geometry, Escape cancellation, and locked controls.

## Ship queue

Each row is one branch and PR. Bugs start with a failing test.

| ID | Change | Evidence and acceptance |
|---|---|---|
| S1 | Make Inspector lock-aware | Controls remain enabled for locked selections, then `try?` hides `elementLocked` (`SionPalettes.swift:163-241`). Disable mutations, show lock state and an explanation. Mixed locked selections must be safe. |
| S2 | Make grid rendering faithful and bounded | `CanvasGrid.subdivisions` is saved but ignored (`SionCanvasView.swift:671-704`). At 10% zoom, four-model-point spacing becomes 0.4 screen points. Draw distinct major/minor lines, skip imperceptible levels, and keep work proportional to viewport pixels. |
| S3 | Cache decoded display images | `NSImage(data:)` runs on every paint (`SionCanvasView.swift:834-859`). Cache by display asset identity with a memory cost and eviction. Invalidation must follow asset replacement/removal. |
| S4 | Keep future history dates from suppressing checkpoints | Negative elapsed time satisfies the five-minute throttle (`DocumentHistory.swift:46-69`). Throttle only nonnegative intervals; cover future, equal, and normal dates. |
| S5 | Reject display-image dimension lies | PNG safety validates bytes but not descriptor `pixelSize` (`SafeDisplayImage.swift:27-36`, `SionArchiveModels.swift:61-89`). Read IHDR dimensions once and require exact metadata agreement. |
| S6 | Avoid empty text mutations and editing ghost text | Opening and closing an unlabeled shape creates an empty label and undo entry (`SionCanvasView.swift:460-475,1552-1558`; `SceneCommand.swift:301-313`). The live editor also draws behind its transparent `NSTextView`. Preserve nil/empty semantics, skip unchanged commits, and suppress the backing text while editing. |
| S7 | Warn before lossy Mermaid export | Export computes `.complete`, `.partial`, or `.none`, then the UI ignores it (`MermaidExporter.swift:41-75`; `SionDrawingDocument.swift:150-157`). Show omitted counts/types and Continue/Cancel before choosing a destination. |
| S8 | Preserve alpha and whole-element opacity | Native colors replace intrinsic alpha with object opacity; text/images bypass opacity and blend; SVG labels escape element opacity (`SionCanvasView.swift:734-795,1017-1024,1659-1665`; `SVGExporter.swift:152-167,237-260`). Multiply alpha or use a transparency group, include labels/decorations/images, and test representative pixels/export structure. |
| S9 | Include painted effects in drawing bounds | Bounds omit stroke, shadows, decorations, and labels, then use fixed 32-point padding (`SceneRenderGeometry.swift:62-75,98-153`). Wide effects clip in export and Zoom to Fit. Compute conservative painted bounds. |

## Performance and architecture

### P0 — interaction work multiplies with scene size — Next

Every pointer update and text keystroke currently:

1. copies the document;
2. searches elements repeatedly;
3. executes a command;
4. validates the whole scene;
5. compares whole documents;
6. notifies observers;
7. recomputes bounds and connector routes; and
8. invalidates and repaints the full canvas.

Relevant code: `SionCanvasView.swift:60-65,150-164,368-378,707-831`,
`SionEditorController.swift:613-636`, `SceneEditor.swift:175-189`,
`SceneCommand.swift:214-256,353-395`, and `Scene.swift:394-450`.

Target design:

```text
pointer samples -> transient overlay -> one viewport repaint
                         |
mouse-up --------> one validated command -> one undo entry
                         |
                 changed IDs + dirty bounds
```

- Build ID, parent, and connector indexes once per scene revision.
- Mutate selected IDs in one pass.
- Validate affected invariants during previews; validate the full scene at
  commit and archive boundaries.
- Send typed change sets and dirty bounds to observers.
- Keep undo as semantic inverse/delta commands with a byte budget.

Do this after adding stress fixtures and signposts. It changes the editor's
transaction contract and should not be mixed with visual features.

### P0 — routing is globally repeated — Next

- Moving one obstacle invalidates every connector
  (`SceneCommand.swift:249-256,523-532`).
- Bounds route all connectors, drawing routes them again, and each route scans
  every obstacle (`SceneRenderGeometry.swift:19-59,98-117`;
  `SionCanvasView.swift:707-718`).
- Orthogonal search can build 16,384 nodes per connector
  (`ConnectorRouting.swift:866-961`). Dense scenes then fall back to a small
  candidate set, causing a visible quality cliff.
- Rotation is omitted from obstacle and fallback-boundary geometry.

Create one immutable render context per scene geometry revision. It should own
the spatial obstacle index and route cache. Invalidate connectors attached to a
changed endpoint or whose route corridor intersects changed bounds. While
dragging, show a cheap provisional route; refine once at commit. Add exact
fixtures for rotated obstacles and cache invalidation.

### P0 — painting ignores the viewport — Next

`draw(_:)` walks every visible element, ignores `dirtyRect`, rebuilds paths,
text, gradients, and routes, and marks the whole view dirty. Add a spatial
index, viewport/dirty-rect culling, cached immutable render artifacts, and tile
or layer invalidation. Remove the redundant gradient-stop sort after validated
input (`SionCanvasView.swift:763-777`; `ModelValidation.swift:65-89`).

### P1 — saving and import block the main actor — Next

- Save synchronously resolves routes, emits recovery SVG/Mermaid, hashes
  assets, writes an uncompressed ZIP, then decodes it again
  (`SionDrawingDocument.swift:71-81`; `SionArchive.swift:68-201`).
- Large image paste reads up to 256 MiB on the main thread, then launches
  untracked jobs without progress, cancellation, or ordering
  (`SionCanvasView.swift:548-640`).
- Clipboard payloads synchronously base64-encode asset data and only then check
  size (`SionCanvasView.swift:517-525`; `SceneSelectionPayload.swift:81-89`).
- Validation repeatedly hashes and parses identical assets. SHA conversion
  copies `Data` into `[UInt8]`; PNG validation concatenates buffers.

Snapshot small value state on the main actor, then run encoding/import through
cancellable services. Validate each unique display asset once per revision.
Stream hashes and ZIP I/O; use deflate; preflight clipboard size; show progress
and precise failures. Keep a derived-save cache keyed by document revision.

### P1 — history is count-limited, not memory-limited — Next

Undo keeps up to 100 whole-document snapshots. Archives can retain 120 full
scene revisions. A few large images or scenes can create large pauses and make
save exceed archive limits. Move to command deltas or structural sharing and
enforce byte budgets for live undo and recovery history. Coalesce key-repeat
and continuous gestures.

### Performance gates — Ship with the relevant architecture PRs

Add `os_signpost` spans plus reproducible budgets for:

- drag and typing at 1,000, 10,000, and 25,000 elements;
- routing at 100 and 500 connectors;
- pan/zoom with 100 embedded images;
- save/open with 120 history entries;
- peak allocations, archive size, and frame misses.

Do not claim a performance fix from microbenchmarks alone. Verify a complete
gesture and visible frame.

## Rendering and format fidelity

### Confirmed defects — Next

- Text auto-sizing is modeled but inert. `.fitHeight` is the standalone
  default; multiline text clips instead of growing. Implement `fixed`,
  `fitHeight`, and `fitWidthAndHeight` in one measured layout abstraction.
- Editing insets are forced symmetric while committed rendering supports four
  independent edges. Connector labels retain only about 12 points of content
  height under defaults. Use the same layout geometry for editing and paint.
- Native linear gradients reduce start/end points to an angle, losing position
  and length. SVG retains them. Render exact normalized endpoints.
- `.overlay` maps to `.sourceOver` natively. Implement it or reject/report it;
  silent substitution corrupts appearance.
- Only the first shadow renders; `spread` and later shadows are discarded in
  Canvas and SVG. Implement the declared array semantics or narrow the format.
- Circle and diamond connector decorations are stroked on Canvas but filled in
  SVG. Define one appearance and test parity.
- SVG text wraps only at explicit newlines, hardcodes leading, and maps
  justification to start. It differs from AppKit for wrapping, line spacing,
  paragraph spacing, and alignment. Recovery output must be faithful.
- Display images may be repeatedly revalidated and copied. Share verified
  asset metadata and decoded renditions across render/export operations.

Add a renderer conformance matrix covering every enum case. Store compact SVG
fixtures in the portable tests and pixel snapshots in the macOS tests.

### Groups are data without behavior — Next

The model stores parents and `GroupClipping.clipToBounds`, but Canvas and SVG
iterate a flat list; group elements draw nothing. Clipping is ignored, parent
visibility does not hide descendants, and lock behavior is not inherited.

Define hierarchy semantics first, then implement one render traversal and clip
stack shared conceptually by Canvas and export. Add cycle, hidden-parent,
nested-clip, reorder, delete, and undo tests. Only then expose Group/Ungroup.

## Interaction and correctness

### Rotated geometry — Incoming, then verify

On `v0.2.0`, painting rotates shapes while hit testing, selection handles,
connector targets, and obstacles use unrotated rectangles. PR #19 addresses
most interaction geometry. After merge, test painted protrusions, transparent
corners, rotated connector boundaries, and routing obstacles.

### Shape-aware hit testing — Next

Every nonconnector claims its expanded rectangular frame. Transparent corners
of ellipses, diamonds, triangles, and paths steal clicks from visible content
below. Use bounds for broad phase, then fill/stroke path testing. Provide
click-cycling for deliberate overlap selection.

### Gesture cancellation — Next

Escape does not consistently cancel move, resize, rotate, radius, or creation;
lost mouse-up can leave an active gesture. Centralize gesture state and restore
its starting document on Escape, focus loss, or capture loss. One gesture must
produce at most one undo entry.

### Error handling — Next

Canvas and palettes commonly use `try?` plus `NSSound.beep()`. Rejections can
leave a control displaying a value the model refused. Add one editor feedback
channel with a compact banner, retry/details when actionable, and VoiceOver
announcements. Keep beeps optional, never exclusive.

### Mermaid import layout — Next

The parser detects TB/TD/BT/LR/RL but discards direction and places nodes in a
three-column row-major grid (`MermaidImporter.swift:9-31,252-283`). Layer the
graph by topology, honor direction, reduce crossings, and retain a deterministic
cycle fallback.

## Accessibility — Next

The canvas exposes one AX group containing only element and selection counts
(`SionCanvasView.swift:55-67,1398-1414`). VoiceOver cannot inspect or edit any
object.

Expose virtual `NSAccessibilityElement` children for viewport elements with:

- role, type, name/text/image description, frame, selected/locked state;
- connector endpoint and direction summaries;
- select, edit, move, delete, and traversal actions;
- selection, error, and document-change announcements;
- keyboard equivalents and logical focus after insertion/deletion.

Respect Reduce Motion for any animation and Increase Contrast/Reduce
Transparency for guides and overlays. Follow Apple's
[AppKit accessibility](https://developer.apple.com/documentation/AppKit/accessibility-for-appkit),
[custom element](https://developer.apple.com/documentation/appkit/nsaccessibilityelement-swift.class),
and [accessibility HIG](https://developer.apple.com/design/human-interface-guidelines/accessibility)
guidance.

## Product and interface backlog

These close the largest gap between the capable file model and the sparse UI.

### Essential editing — Next

- Marquee/lasso selection; spacebar hand/pan; drag autoscroll.
- Grid snapping, smart guides, equal-spacing guides, and visible snap toggles.
- Align/distribute, nudge, reorder, group/ungroup, lock/hide, and duplicate.
- A searchable Layers/Outline sidebar with hierarchy, visibility, lock, rename,
  drag reorder, selection sync, and a minimap viewport.
- Scrollable, sectioned Inspector with mixed-value multi-editing. Prioritize
  Geometry, Text, Connector, Appearance, Image, and Canvas.
- Direct connector endpoint and bend editing, detach/reattach, label position,
  route type, and arrowheads.
- Selection dimensions/coordinates and a small zoom/saved/selection status row.
- Context menus, command palette, search/jump, and shortcut discoverability.

The model already supports most of this, but the UI currently exposes only
fill, stroke width, route, and magnets. Keep controllers at semantic command
level; do not let palettes mutate the scene directly.

### Library and reusable design — Next

The Library is four fixed text buttons despite eight built-in shapes. Replace
it with a searchable, keyboard-accessible icon grid containing every built-in
shape, recent/favorite styles, drag-to-place, and reusable user stencils. Add
named style tokens for nodes/connectors and contrast-aware text suggestions.

### History — Next

History buttons restore immediately without preview, diff, current marker, or
confirmation. Use a selectable revision list with thumbnail, timestamp,
changed-element summary, explicit Restore, and Open as Copy.

### Native completeness — Next

- Standard Settings, Services, Open Recent, Revert, Help, Find/Spelling,
  Page Setup, Print, and responder-chain menus.
- PNG, PDF, and JPEG export; extension/type enforcement in save panels.
- Window minimum size and aligned Inspector columns (`NSGridView`).
- Simplified small app-icon variants; the detailed castle is unreadable at
  16 px.
- Localization hooks, first-run sample, templates, and sample gallery.
- Developer ID signing, hardened runtime, notarization, update path, and an
  explicit sandbox/file-access decision.
- Launch smoke, visual regression, accessibility, fuzz/property, and
  performance CI. Swift 6.3.3 is pinned, but the package still uses Swift 5
  language mode; migrate under strict-concurrency diagnostics.

### Larger capabilities — Explore

- Multi-page canvases and shared/artboard layers.
- Automatic graph layout and data-driven org/network diagrams.
- Tables, Boolean shape operations, SVG import, and freehand paths.
- Comments, presence, conflict-aware collaboration, and share links.
- Presentation mode with named traversal steps.
- External data links and refreshable diagrams.

These are established expectations in
[OmniGraffle](https://www.omnigroup.com/omnigraffle/features/),
[Visio](https://support.microsoft.com/en-US/Visio/compare-visio-versions-and-features),
and [draw.io](https://www.drawio.com/docs/features/). Sequence them only after
core editing is fast, faithful, and accessible.

## Product experiments

Validate these with a small prototype or usability session.

- **Quick-grow nodes:** drag a connector into empty space, then choose Process,
  Decision, Note, or Database from a four-item radial strip. Digits select.
- **Diagram Doctor:** flag crossings, overlaps, clipped labels, dangling
  connectors, weak contrast, and inconsistent spacing; offer reversible fixes.
- **Keyboard graph authoring:** Return adds a child, Tab a sibling, arrows move
  through neighbors, typing edits immediately.
- **Trace Flow:** a restrained pulse follows outgoing edges from the selection.
  Disable it under Reduce Motion.
- **Magnetic spark:** one subtle guide flare and optional trackpad haptic when a
  snap locks. No sound by default.
- **Presentation path:** turn selected nodes/groups into a navigable story
  without duplicating the diagram.
- **Editable onboarding diagram:** teach select, connect, text edit, quick-grow,
  and Mermaid paste inside a disposable sample.

## Verification gaps

Before calling the product robust, add coverage for:

- Canvas paint semantics and Canvas/SVG parity;
- rotated hit testing, selection, connection, and routing;
- auto-size and edit/commit layout parity;
- nested clipping and inherited visibility;
- accessibility tree, actions, focus, and announcements;
- async paste ordering, cancellation, size limits, and errors;
- end-to-end save/reopen, malformed archives, and property/fuzz inputs;
- large-scene interaction, rendering, routing, undo, save, and memory budgets.

## Deferred semantics

Do not change these without a product decision:

- Whether deleting a locked endpoint may delete its attached locked connector.
- Whether parent lock is inherited or only blocks direct group operations.
- Whether Zoom to Fit means page, drawing, or selection. Prefer three explicit
  commands: Fit Page, Fit Drawing, and Fit Selection.
- Whether unsupported format features should be rejected, normalized, or
  rendered approximately. Silent approximation is the only unacceptable case.
