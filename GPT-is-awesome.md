# Thalyx audit

Reviewed 2026-08-26 at `1c60efb`. Unit tests, type-check, lint, and production
build were run. All 184 unit tests pass; lint emits four warnings. The build
succeeds with missing-font and ineffective-code-splitting warnings.

## Implement now

These have direct evidence and low product ambiguity. Each should use its own
PR unless two items share the same root cause.

1. **Critical — recovery writes permit path traversal.** `recovery:write`
   validates only string length, while read and clear use the restricted doc-id
   schema. A compromised renderer can send `../...` and make
   `recoveryWrite()` escape the recovery directory. Use the same schema for all
   recovery operations and test rejection before fixing.

2. **High — Recent Files fails after relaunch.** The menu is rebuilt from saved
   paths, but selecting `openRecent` never grants that path to the IPC allowlist.
   The subsequent read throws `path not granted`. Grant only the exact selected
   recent path in main before notifying the renderer; prune missing recents.

3. **High — launch-file delivery races renderer setup.** After `createWindow()`,
   startup argv is sent immediately even though the React listener is installed
   later. The existing pending-path queue is bypassed because `mainWindow` is
   already non-null. Queue until `ready-to-show`/renderer readiness and add an
   Electron regression test.

4. **High — autosave can mark newer edits saved.** A write captures document A,
   then document B can become dirty before A's asynchronous write resolves.
   A's completion calls `markSaved()` unconditionally, clearing B's dirty flag.
   Track a document revision or serialized snapshot and mark saved only when the
   completed write still matches current state. Surface write failures.

5. **High — New/Open can discard unsaved work without confirmation.** Menu New,
   Open, Recent, imports, OS open-file events, and scratch restoration replace
   the store immediately. Add a Save/Discard/Cancel guard shared by all document
   replacement paths. Autosave is not consent to overwrite the user's file.

6. **Medium — segmented controls never show their selected state.** Components
   emit `aria-pressed`, but CSS selects `aria-checked`. This affects context and
   export dialogs. Correct the selector and add an interaction/visual assertion.

7. **Medium — PNG/PDF export bypasses native saving and leaks object URLs.** In
   Electron, temporary anchor downloads do not provide the promised native file
   workflow, can save to an unexpected location, and never revoke their blob
   URLs. Add a bounded binary-save IPC abstraction and use it for PNG/PDF.

8. **Medium — recovery-write size is unbounded.** Normal file IPC caps payloads
   at 50 MB, but recovery accepts arbitrary strings. Apply the same byte limit
   before disk work to prevent renderer-triggered memory/disk pressure.

9. **Medium — container creation produces a 48 px-tall frame.** Its title and
   padding consume most of that height, so a newly created frame is barely
   useful and visually resembles a node. Start with a practical frame size or
   support drag-to-size placement.

10. **Medium — context controls obscure the canvas on small windows.** A fixed
    264 px panel begins beside the toolbar; the 360 px Mermaid panel can open on
    the opposite side. At the 640 px minimum window width they leave almost no
    usable canvas and can overlap. Add compact/collapsible responsive modes.

11. **Medium — errors vanish or become unhandled rejections.** Open, save,
    autosave, recent-file, import, export, updater, and clipboard paths often
    launch `void` promises without user-visible recovery. Add a common error
    toast with retry/details; never close Export after failure.

12. **Medium — Cut may delete without a valid copy.** Menu Cut clears plain text
    and immediately deletes selection instead of awaiting the application's
    structured copy. Copy successfully first, then delete.

13. **Medium — browser-mode saves repeatedly download during autosave.** Once an
    untitled browser document gets a filename, `platform.file.write()` downloads
    a new file after every debounce. Keep autosave in recovery/browser storage;
    download only on explicit Save/Export unless a writable File System Access
    handle exists.

14. **Medium — the renderer bundle is oversized.** The main renderer chunk is
    about 2.53 MB minified, with additional Mermaid/Cytoscape chunks over 1 MB.
    Imports intended to be dynamic are also static, so Vite reports that they
    cannot split. Remove duplicate static edges and lazy-load Mermaid and PDF
    export paths to reduce startup work and input stutter.

15. **Low — configured fonts are missing.** Build output reports missing
    `inter-regular.woff2` and `.ttf`; runtime falls back to system fonts. Remove
    dead declarations or ship licensed assets so layout is deterministic.

16. **Low — lint warnings hide signal.** `Canvas` omits `rfInstance` from a hook
    dependency list, an eslint suppression is stale, and two modules mix shared
    exports with components. Resolve them and make CI reject warnings.

## Product and visual improvements

These are worthwhile but need design validation before implementation.

17. **Command palette.** A searchable Mod+K palette would expose tools, layout,
    export, theme, and Mermaid commands without memorizing shortcuts.

18. **Minimap/outline for large diagrams.** Make it optional and collapsible;
    show containers and current viewport, with click-to-jump navigation.

19. **Zoom/status pill.** Show zoom percentage, selection count, save state, and
    a one-click Fit action in a quiet bottom bar. Today autosave is invisible.

20. **Connector preview and invalid-target feedback.** Highlight the candidate
    target and animate rejected self/island connections instead of silently
    doing nothing.

21. **Drag-to-create with live dimensions.** Click-place is fast, but dragging a
    shape or frame should size it immediately; a click can retain default size.

22. **Alignment/distribution controls.** Tidy is coarse. Add explicit left,
    center, right, top, middle, bottom, and equal-spacing actions for multi-select.

23. **Search and jump.** Mod+F should find labels and Mermaid source, dim other
    objects, and move the viewport between matches.

24. **Presentation mode.** Hide chrome, fit the diagram, and traverse containers
    or selected nodes as steps. This turns diagrams into lightweight walkthroughs.

25. **Named color/style presets.** Let users save a node and connector style as
    a small reusable token. Applying one should remain a single undo action.

26. **Delight: diagram pulse.** A restrained “trace flow” action could animate a
    pulse along outgoing connectors from the selected node, useful for demos and
    understanding unfamiliar graphs. Respect reduced-motion settings.

27. **Delight: semantic quick-grow.** After a quick-connect chevron creates a
    node, offer ephemeral choices such as Decision, Process, Note, or Database;
    keyboard digits choose without opening a persistent panel.

28. **First-run sample.** Replace the empty canvas with an optional tiny editable
    diagram that teaches select, connect, type-to-edit, and Mermaid round-trip.
    Keep “blank canvas” one click away.

## Verification gaps

- No test attacks every IPC boundary with malformed, oversized, and traversal
  inputs.
- No test covers Recent Files after a full app restart.
- No test proves startup argv/open-file delivery before renderer readiness.
- No test exercises overlapping autosave writes or disk-write failures.
- No screenshot assertions cover selected controls, narrow-window overlap,
  light/dark contrast, long labels, or 200% display scaling.
- Performance tests log several results without enforcing budgets; they can
  regress while CI stays green.
- Accessibility coverage is mostly manual: no automated role/name/state,
  keyboard traversal, contrast, or focus-containment checks.
