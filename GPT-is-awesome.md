# Thalyx review

Scope: object creation, connectors, document windows, lifecycle, performance, and related UI.

## Fixed

### Object creation

- Placement now owns click and drag gestures on canvas, frames, nodes, and edges.
- Click-versus-drag uses screen distance, so zoom no longer changes intent.
- Click, drag, preview, minimum sizes, and grid snapping now agree.
- Pointer identity, Escape, pointer cancel, blur, and document changes cancel safely.
- Preview updates are animation-frame throttled.
- One-shot and locked tools now behave consistently from toolbar and keyboard.
- Text remains visible when blank. Frames are renameable and keep usable minimum sizes.
- New children clamp inside frames instead of silently becoming top-level objects.
- Dragging across frame boundaries reparents while preserving absolute position and node order.
- Nested quick-grow chooses the deepest containing frame.
- Alt-drag, duplicate, paste, resize, and Undo preserve nesting, coordinates, and routes.
- Non-QWERTY letter shortcuts now use the typed character.

### Connectors

- Handle drags store their exact north/east/south/west anchors.
- Rendered endpoints stay on those magnets after moves and reloadable model conversion.
- Self-connections are rejected in UI, actions, restore, Mermaid import, and clipboard input.
- Disabled handles remain measured but cannot steal placement gestures.
- Click-to-connect is disabled, preventing latent half-connections.
- Arrow markers now use valid SVG references; Arrow remains arrowed after Line use.
- Elbow routing leaves and enters pinned sides correctly, including reversed, same-side,
  perpendicular, ellipse, and diamond cases.
- Straight and curved routes ignore stale elbow waypoints.
- Curved labels use the same Bézier as their path.
- Edge selection, labels, arrowheads, and manual-route hit areas render consistently.
- Label and waypoint drags coalesce into one Undo entry and clean up on cancel or blur.
- Routes clear only when endpoint geometry changes; no-op drag, align, and resize preserve them.
- Copy, Cut, paste, duplicate, and Alt-drag retain internal connectors and translated routes.
- Hand mode no longer edits or blocks on connector paint.
- SVG/PNG/PDF geometry now matches canvas curves, labels, waypoints, and bounds.

### Multiple windows and documents

- Each native window has isolated document state, bootstrap data, title, dialogs, and recovery.
- New, New Window, Open, Open Recent, OS open-file, and startup arguments route correctly.
- Multiple startup paths create populated windows without an extra blank window.
- Relative second-instance paths use that instance's working directory.
- Startup bootstrap is pull-based, replayable, and safe across renderer reloads.
- Untitled windows use unique recovery identities; recovery contents resolve live on reload.
- Native files have one canonical owner. Duplicate opens focus the existing owner.
- Save As reserves its target through the write and handles symlink aliases.
- Mermaid imports remain untitled and cannot overwrite their source with Thalyx JSON.
- Document Save only emits `.thalyx`; Open supports Thalyx, JSON, Mermaid, and All Files.
- Autosave, manual save, Save As, close flush, recovery cleanup, and saved-state marking are
  serialized. Edits made during a save remain dirty.
- Save and close commit active inline drafts before serialization.
- Save failures show an actionable alert.
- Window state, menus, recents, updater readiness, print, zoom, export, and About route to the
  correct window.
- Quit waits for window flushes; a reported flush failure cancels Quit.

### Performance

- Canvas observes node, edge, grid, tool, and selection slices instead of whole state objects.
- Each edge observes only its endpoint ancestry instead of scanning every node per frame.
- Connection validation uses a memoized ID set.
- Descendant expansion, reparenting, duplication, and Alt-drag use indexed batch traversals.
- Waypoint invalidation exits early and compares absolute geometry before mutating.

## Remaining work

### Correctness and hardening

- Add a close-attempt token. A write exceeding the five-second main-process deadline can leave
  the renderer inert, then acknowledge a stale close later.
- Include asynchronous Paste and Mermaid Apply in the close barrier.
- Make updater installation recover when any window refuses or times out during close.
- Quarantine corrupt recovery entries and offer Discard instead of reopening an error forever.
- Scope file grants and recovery IDs to their owning renderer. They are currently app-global.
- Add a separate case/Unicode-folded ownership key for nonexistent Save As targets on
  case-insensitive filesystems.
- Browser-mode document replacement still needs Save/Discard/Cancel; native Open now uses a new
  window instead of replacing dirty state.
- PNG/PDF export still bypasses native Save As, may land in an unexpected directory, and leaves
  download object URLs alive.
- Browser autosave still downloads a file on every debounce after the first Save. Keep background
  writes in recovery storage unless a writable File System Access handle exists.
- Open, import, export, updater, and clipboard paths need the same actionable error reporting now
  used by Save.

### Performance and packaging

- Mermaid, Cytoscape, and export dependencies still produce multi-megabyte renderer chunks. Remove
  duplicate static imports and lazy-load specialized paths to reduce startup work.
- Missing Inter font assets make layout platform-dependent. Ship licensed assets or remove the dead
  declarations. Configure CI to reject future lint warnings.

### Interaction and missing behavior

- Implement quick-connect drag to an existing node or empty-canvas shape picker. It currently
  supports click-to-grow only.
- Add inline connector-label editing for Enter, typing, and double-click.
- Make manual-route dragging move the nearest segment, not a source-side-derived rail.
- Complete Space/right-button panning over connector labels in Select mode.
- Add valid/invalid magnet feedback while dragging, especially for rejected self-targets.
- Implement the advertised Tab shape cycle and repeated grow chaining.
- Remember the last applied node style and connector style for subsequent creation.

### Layout and polish

- Compact or scroll the tall tool strip at the supported 640×480 minimum window size.
- Reflow the inspector and Mermaid panel instead of covering most of a narrow canvas.
- Replace platform-dependent glyph icons with one accessible SVG icon set.
- Give recovery/open errors Retry, Discard, and Locate actions.
- Add keyboard-visible focus treatment and labels for every icon-only control.

## Product ideas

- Animate a short “pluck” from the chosen magnet when a connector is pinned.
- Preview reparenting with a tinted frame and a springy drop settle.
- Add a document switcher showing every open window, dirty state, and recovery state.
- Offer route suggestions as faint rails; dragging through one accepts it.
- Add recent-document thumbnails and a command palette for tools, windows, and exports.
- Add an optional minimap/outline with viewport jump navigation.
- Add a quiet zoom, save, and selection-status pill with a one-click Fit action.
- Add label/Mermaid search that dims nonmatches and jumps between results.
- Add presentation mode with chrome-free, ordered diagram walkthroughs.
- Add named node and connector style presets applied as one Undo action.
- Offer an optional first-run editable sample that teaches the core gestures.

## Verification notes

- Add malformed, oversized, traversal, and cross-window tests for every IPC boundary.
- Add restart-level Recent Files, recovery, disk-failure, and overlapping-save tests.
- Add screenshot checks for selected controls, narrow windows, both themes, long labels, and 200%
  display scaling.
- Turn logged performance cases into enforced budgets for startup, drag, layout, and export.
- Automate role, name, state, keyboard traversal, contrast, and focus-containment checks.

Current branch:

- Unit, type, lint, formatting, and build checks cover the implemented paths.
- Electron/Web Playwright regressions were added for creation, anchors, self-connections, and
  multi-window isolation.
- This environment lacks `libglib-2.0.so.0`, so Chromium/Electron could not launch here.
