# Architecture

Sion is a native macOS document application. No browser runtime sits in the
editing path.

```text
Sion executable
    │
    ▼
SionKit / AppKit
  document · window · canvas · palettes · accessibility
    │
    ▼
SionCore use cases
  commands · routing · import · export · archive · history
    │
    ▼
SionCore model and geometry
    │
    ▼
ZIP and digest drivers
```

Each layer calls only its immediate neighbor. Views issue semantic commands to
an editor controller; they do not mutate archives or raw scene arrays. The
document controller invokes the archive service; it does not parse ZIP records.

## Targets

- `SionCore`: Foundation-only values and services. It builds and tests on macOS
  and Linux. No AppKit, Core Graphics, or UI coordinates enter this target.
- `SionKit`: programmatic AppKit document UI, custom canvas, native text editing,
  paste, undo, and tear-off palettes.
- `Sion`: thin application entry point and main menu.

Canonical coordinates are top-left/y-down throughout. The canvas is flipped;
conversion occurs only at AppKit boundaries.

## Editing

One user intent is one command transaction and one undo step. Pointer drags keep
a preview snapshot, render live, and commit once on mouse-up. Text uses native
text views and AppKit measurement. Paste precedence is original image files,
PDF/SVG, bitmap, Mermaid, then plain text. Image import keeps the source bytes
and generates a bounded PNG rendition; canvas rendering reads only the
rendition.

The canvas's contextual menu sends the same selectors the main menu does, with
no target, so the responder chain resolves them and one `validateMenuItem(_:)`
decides what either menu offers.

Connectors reference elements and stable magnets. The router receives immutable
geometry plus obstacles and returns a resolved path. Rendering never owns graph
semantics.

## Palettes

Inspector, library, and history use a typed content factory for two containers:
a transient `NSPopover` and a borderless floating `NSPanel`. The instances
share their current document target. Each palette is an app-global singleton
that retargets to the front document and selection. The panel states the
palette's declared size itself: it is borderless, so it has no title bar to
size it, and the palette bodies scroll rather than report a height of their own.
A resizable panel grows its own edges too: a borderless window has no frame view
to drag, so an overlay claims a band down the sides and along the bottom and
lets every other point through. The top is left to the header, which moves it.

## Libraries

A library entry is a named `SceneSelectionPayload`, stored encoded so an entry
written by a later build survives a round trip through this one. Two stores
share that model and differ only in how far an entry travels. The document's own
library is a scene extension under `ch.lkmc.sion.library`, written by the same
command mechanism as any other edit, so it is undoable and travels in the
archive. The global one is a JSON file in Application Support, written straight
through: it belongs to the person rather than any document, so there is no undo
stack it could join. A file that this build cannot read is never overwritten.

## Linux

The Linux application will be a separate native UI, expected to use Qt 6. It
shares no web runtime and need not share Swift implementation code. Compatibility
comes from the normative format specification and checked-in fixtures that both
implementations must decode, rewrite, and compare semantically.
