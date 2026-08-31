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

## Linux

The Linux application will be a separate native UI, expected to use Qt 6. It
shares no web runtime and need not share Swift implementation code. Compatibility
comes from the normative format specification and checked-in fixtures that both
implementations must decode, rewrite, and compare semantically.
