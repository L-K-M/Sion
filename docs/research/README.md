# Research notes

These are the raw research notes (2026-08-23) that fed [`PLAN.md`](../../PLAN.md). They are kept
as **background and evidence** — sources, version numbers, license verifications, API dumps —
not as instructions.

> **Precedence rule: where a note and `PLAN.md` disagree, `PLAN.md` wins.**
> The notes were written in parallel by independent researchers and contain a few
> recommendations that were consciously overridden when the plan's binding decisions (PLAN.md §2)
> were made. Known supersessions:
>
> - `persistence.md` assumes a **Tauri** shell throughout (Rust commands, Tauri plugins,
>   WebdriverIO testing). Decision **D1** chose **Electron**; PLAN.md §12/§15 restate all of
>   that plumbing for Electron. The document-model, undo, rendering, and export *analysis* in
>   the note remains valid.
> - `canvas.md` recommends **elkjs as the primary layout engine**. Decision **D3** made
>   `@dagrejs/dagre` the only MVP engine, with elkjs deferred to M9 behind an EPL-2.0 sign-off.
> - `ux.md` proposes Tidy Up on `Ctrl+Alt+T` (Figma's binding). Decision **D15** rebinds it to
>   `Alt+Shift+T` (`Ctrl+Alt+T` opens a terminal on Ubuntu/GNOME).
> - `mermaid-api.md`'s abbreviated sequence LINETYPE table stops at 25; the **full table
>   (0–34)** in `mermaid-ground-truth.md` / PLAN.md §9.2 is the correct one.
> - `mermaid-api.md` suggests `registerExternalDiagrams([], {lazyLoad:false})` for init;
>   decision **D9** standardizes on the parse-first sequence verified in
>   `mermaid-ground-truth.md`. (Both work.)

## Files

| File | Topic |
|---|---|
| `shell.md` | Desktop shell: Tauri 2 vs Electron vs native — why Electron (WebKitGTK canvas problems, WKWebView 60fps cap, packaging/updater coverage) |
| `canvas.md` | Canvas/editor libraries (React Flow, tldraw, JointJS, Excalidraw, X6, Konva…) and layout engines (dagre, elkjs) with npm/tarball-verified licenses and versions |
| `mermaid-api.md` | Mermaid programmatic integration: parse APIs, db accessors per diagram type, serializer escaping rules, round-trip limitations |
| `mermaid-ground-truth.md` | **Hands-on verification** of the mermaid 11.17.0 API in Node 22 — real output dumps, the jsdom shim, arrow/shape/LINETYPE tables, gotcha checklist. This is the regression reference for the import/export code. |
| `mermaid-lab/` | The runnable scripts + captured outputs behind `mermaid-ground-truth.md` (`npm install` inside the dir, then `node 03-flowchart-db-jsdom.mjs` etc.). `package-lock.json` records the exact verified dependency tree. |
| `ux.md` | UX patterns of OmniGraffle, Excalidraw, Whimsical, FigJam, draw.io, Lucidchart, Miro — the 18-interaction MVP spec (adopted by PLAN.md §10) and the do-not-build list |
| `persistence.md` | Document format, undo/redo approaches, state management, rendering tradeoffs, export, autosave/recovery, testing (see supersession note above) |
