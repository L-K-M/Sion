# Thalyx research — Desktop shell / app framework (Tauri 2.x vs Electron vs native)

Research date: 2026-08-23. Target: canvas-heavy, OmniGraffle-like diagram editor for macOS + Linux with deep Mermaid import/export. Project license: public domain / Unlicense → all deps must be permissive (MIT/Apache/BSD/ISC). GPL/AGPL/source-available excluded.

---

## 1. Current versions and licensing (verified Aug 2026)

| Framework | Latest (Aug 2026) | License | Notes |
|---|---|---|---|
| Tauri core | v2.11.5 (tauri crate); ecosystem "Tauri v2.10.1" umbrella release Mar 2026 | **MIT OR Apache-2.0** (dual, per `tauri/LICENSE.spdx`) | https://github.com/tauri-apps/tauri/releases , https://tauri.app/release/core/ |
| Electron | **43.4.1** (2026-08-19); Electron 43 = Chromium M150 + Node 24, released 2026-06-30. Support window = latest 3 majors (43/42/41), new major every 8 weeks | **MIT** (Chromium itself BSD-3) | https://endoflife.date/electron , https://releases.electronjs.org/ |
| electron-builder | v27.x line | MIT | https://www.electron.build/docs/ |
| Qt 6 | 6.x | LGPL-3.0 / GPL / commercial per module; QtWebEngine = LGPL + Chromium | License friction for a public-domain app; see §10 |
| GTK4 | 4.x | LGPL-2.1+ | Linux-first; macOS port is second-class |
| Flutter | 3.x stable desktop | BSD-3-Clause | No DOM → Mermaid needs an embedded webview anyway; see §10 |

Licensing verdict: **both Tauri and Electron are fully compatible** with an Unlicense app. Tauri: MIT/Apache-2.0 dual. Electron: MIT. WebKitGTK (LGPL/BSD) is a *system* library with Tauri — dynamically linked, never bundled — so no license contamination either way.

---

## 2. Webview engines — the decisive issue

### 2.1 Tauri's engines
- macOS: **WKWebView** (system Safari/WebKit; version tied to the user's macOS version).
- Linux: **WebKitGTK** via `webkit2gtk-4.1` (libsoup3 API); the version is whatever the user's distro ships — **the app does not control it**.
- Windows (future): WebView2 (Chromium) — the only Chromium-consistent Tauri platform.
- Reference: https://v2.tauri.app/reference/webview-versions/

### 2.2 WebKitGTK on Linux — documented problems (highly relevant to a canvas editor)

Concrete, sourced facts:

1. **Tauri's own docs have a dedicated "Linux Graphics Issues" page** (https://v2.tauri.app/develop/debug/linux-graphics/): blank/white windows, flicker on resize, crashes on resize, framebuffer errors — mostly "the WebKitGTK DMABUF renderer requesting buffer formats the NVIDIA driver does not provide." Documented workaround env vars (in order of preference):
   - `__NV_DISABLE_EXPLICIT_SYNC=1` (Wayland/NVIDIA crashes, minimal perf cost)
   - `WEBKIT_DISABLE_DMABUF_RENDERER=1` (fixes framebuffer errors, costs rendering perf)
   - `WEBKIT_DISABLE_COMPOSITING_MODE=1` (last resort — **disables HW acceleration entirely**)
   - Docs recommend setting these from Rust *before* webview init. Critical warning quoted from that page: WebGL/canvas can **"silently land on a slow path"** on Linux **with no detectable error** — Tauri itself tells you to build fallback rendering paths.
2. **Canvas FPS**: report in tauri-apps discussion #8524 (July 2026): a Tauri app reaches **~40 fps on Ubuntu WebKitGTK despite GPU acceleration vs 240 fps in a Chromium-based shell**. A Tauri maintainer in that thread: "webkitgtk is unusable", "worse/more unstable each release". (https://github.com/tauri-apps/tauri/discussions/8524)
3. **Known-bad releases**: WebKit2GTK 2.40 caused Tauri apps to render slowly (tauri issue #7021, https://github.com/tauri-apps/tauri/issues/7021); general Linux perf complaints in tauri #3988 and wry #890 (lag/freezes with many DOM elements, slow drag-selection).
4. **Version drift**: because WebKitGTK is a system lib, users on Debian stable / older Ubuntu run *years-old* engines with different bugs than users on Fedora. You cannot ship a fix; the AppImage bundler explicitly does NOT bundle webkitgtk. Only Flatpak partially fixes this by pinning the GNOME runtime (see §7).
5. **It is improving — slowly**: WebKitGTK 2.50 (Nov 2025) switched threaded rendering to **Skia**; 2.52 (Mar 2026) added accelerated 2D canvas with batched-replay recording, faster text rendering, damage propagation in non-composited mode (https://webkitgtk.org/2026/03/18/webkitgtk-2.52-highlights.html , https://webkitgtk.org/2025/11/26/webkitgtk-2.50.html). But these versions won't reach LTS-distro users for 1–3 years.
6. **Real-world migration away**: Paseo (desktop AI agent app) migrated Tauri → Electron (~May 2026), citing outdated WebKitGTK bindings, Wayland problems, and "real layout differences" (not just font aliasing) across distros/GPU setups; concluded Electron overhead was application-level, not framework-level (https://paseo.sh/blog/i-was-wrong-about-electron). The OpenCode desktop app also chose Electron over Tauri.
7. **Tauri team's own exit plans** confirm the problem: active work on **CEF integration** (maintainer, Nov 2025: "working on it", dogfooding on customer projects; `cef-rs` "pretty advanced" as of Oct 2025) and the experimental **Verso/Servo runtime** `tauri-runtime-verso` (announced Mar 2025, explicitly experimental; Servo "can't compete with the normal browsers feature-wise anytime soon" per maintainer) (https://v2.tauri.app/blog/tauri-verso-integration/ , https://github.com/versotile-org/tauri-runtime-verso). Neither is production-ready as of Aug 2026. No Firefox option ("there's no firefox based webview library").

**Verdict on the special-attention question**: WebKitGTK is a *known, documented, maintainer-acknowledged* source of canvas-performance and rendering bugs, and for a professional canvas editor in 2026 it is **not good enough as the only Linux engine**. It runs fine for form-like UIs; it is the worst possible substrate for the exact workload Thalyx has (large SVG/canvas scene, 60fps drag interactions, text-heavy labels).

### 2.3 WKWebView on macOS — good but not perfect
- Generally solid Safari-class rendering; canvas/SVG quality is professional-grade.
- **60 fps cap**: WebKit's internal `PreferPageRenderingUpdatesNear60FPSEnabled` preference (default true) caps WKWebView rendering ~60fps; can be flipped via private `_features` API on `WKPreferences` (community plugin `tauri-plugin-macos-fps`), but **on macOS 26+ WKWebView ignores the toggle** (https://crates.io/crates/tauri-plugin-macos-fps). ProMotion 120 Hz canvas interaction is effectively unavailable.
- Reported **micro-lag while scrolling in Tauri/WKWebView that does not occur in Safari or Chrome** on the same page (tauri discussion #8436).
- Embedded-browser detection: Google OAuth refuses to complete inside WKWebView (relevant only if cloud sync is ever added). One team (Atrium) embedded CEF inside their Tauri app to escape WKWebView, at a cost of **~+170 MB bundle** and substantial native complexity (https://getatrium.dev/blog/embedding-real-browser-tauri).

### 2.4 Electron's bundled Chromium
- Identical Blink/Skia rendering on macOS and Linux; the engine version is pinned by the app, updated on the app's schedule. Canvas 2D, WebGL, OffscreenCanvas, `foreignObject`, font shaping all behave like desktop Chrome (the environment Mermaid and every canvas lib is primarily tested against).
- Residual Linux variance is only fontconfig-level (which fonts exist), not engine-level.
- Cost: 8-week Chromium major cadence; staying on a supported major (latest 3) is the security treadmill.

### 2.5 Mermaid-specific engine risk (load-bearing for Thalyx)
- Since Mermaid v9.2 default flowchart labels render as **HTML inside SVG `<foreignObject>`** (`htmlLabels: true`). WebKit (both WKWebView and WebKitGTK) has a long history of `foreignObject` bugs: wrong clipping, misplaced layers (WebKit bug 23113), silent render failures, stricter HTML validation. Non-Chromium embedders (e.g. JCEF/IntelliJ, mermaid issue #7565) show blank labels.
- Workaround: `mermaid.initialize({ flowchart: { htmlLabels: false }, htmlLabels: false })` forces plain SVG `<text>` labels — safer everywhere, slightly different word-wrap metrics.
- On Electron/Chromium this whole class of bugs disappears; Chrome is Mermaid's reference target.

---

## 3. Bundle size and memory (concrete numbers)

From the Hopp benchmark (same app implemented in both, macOS, N=1 — treat as indicative: https://www.gethopp.app/blog/tauri-vs-electron):
- Bundle: **Tauri 8.6 MiB vs Electron 244 MiB** (their unoptimized build; typical compressed Electron installers are ~85–120 MB).
- Memory, 6 windows open: **Tauri ~172 MB vs Electron ~409 MB**.
- Startup time: "negligible" difference.
- Build time (cold): Tauri 80.9 s (Rust compile) vs Electron 15.8 s.
- Hoppscotch migration data point: 165 MB → 8 MB installer, ~70% memory reduction after moving to Tauri.
- Typical idle RSS: Electron ~200–300 MB; Tauri ~30–40 MB (raftlabs/openreplay comparisons).

Reality check: a diagram editor holding a large scene graph will have its memory dominated by app data + canvas buffers in either shell; the ~150–250 MB Electron overhead is real but constant, not proportional.

---

## 4. File system access and native file dialogs

### Tauri 2
- Dialogs: plugin `tauri-plugin-dialog` / npm `@tauri-apps/plugin-dialog`. JS: `open({ multiple, directory, filters: [{name, extensions}], defaultPath })`, `save(...)`, `message()`, `ask()`, `confirm()`. Rust: `DialogExt` → `app.dialog().file().pick_file()/blocking_pick_file()/blocking_save_file()`, `.message().buttons().kind()`. Native dialogs on macOS (NSOpenPanel/NSSavePanel) and Linux (GTK file chooser; xdg-desktop-portal under Flatpak). MSRV 1.77.2. (https://v2.tauri.app/plugin/dialog/)
- FS: `tauri-plugin-fs` (`readTextFile`, `writeTextFile`, `readFile`, `writeFile`, `watch`) gated by the **capabilities/permissions JSON** system (`src-tauri/capabilities/*.json`); path scopes like `$HOME/**`, `$APPDATA/**`. Arbitrary paths returned by the dialog plugin are automatically allowed. More ceremony than Electron, but a real security model.
- Big-file caveat: prefer doing IO in Rust commands; shuttling MB-scale file bytes over IPC is slow (see §6).

### Electron
- `dialog.showOpenDialog({ properties: ['openFile','multiSelections'], filters })`, `dialog.showSaveDialog()` in main process — native NSOpenPanel / GTK chooser. Full Node `fs` in the main process; expose narrow, validated operations to the renderer via `contextBridge` + `ipcRenderer.invoke`. No built-in scoping — discipline is on the app (contextIsolation: true, sandbox: true, no nodeIntegration in renderer).
- Both frameworks: file associations (`.thalyx`, `.mmd`) supported — Electron via electron-builder `fileAssociations`; Tauri via `tauri.conf.json > bundle > fileAssociations` + deep-link/`onOpenUrl`/`RunEvent::Opened` handling on macOS.

---

## 5. Native menu bar and keyboard shortcuts

### Tauri 2
- Menus built on the `muda` crate (MIT/Apache-2.0). Rust: `tauri::menu::{Menu, Submenu, MenuItem, CheckMenuItem, IconMenuItem, PredefinedMenuItem}`; JS: `@tauri-apps/api/menu` (`Menu.new`, `Submenu.new`, `items`, `setAsAppMenu`, `popup()` for context menus). Docs: https://v2.tauri.app/learn/window-menu/ , https://docs.rs/tauri/latest/tauri/menu/index.html
- Accelerators: `accelerator: "CmdOrCtrl+S"` — resolves to ⌘ on macOS, Ctrl on Linux. `PredefinedMenuItem` gives native Cut/Copy/Paste/Undo/About/Quit.
- macOS quirk (documented): top-level items are ignored — everything must live in submenus; the first submenu becomes the app menu. Known accelerator edge-case bugs exist (e.g. `Cmd++` broken, tauri issue #12945).
- Linux: menu renders as a GTK in-window menubar (no global menubar on GNOME Wayland — same is true for Electron).
- Global (system-wide) shortcuts: `tauri-plugin-global-shortcut`. In-window shortcuts: handle in JS (keydown) or via menu accelerators.

### Electron
- `Menu.buildFromTemplate([...])` + `Menu.setApplicationMenu(menu)`; `role:` items (`'undo'`, `'redo'`, `'cut'`, `'copy'`, `'paste'`, `'appMenu'`, `'fileMenu'`, `'editMenu'`, `'windowMenu'`) give fully native, localized macOS behavior for free; `accelerator: 'CmdOrCtrl+Z'`. This is the most battle-tested cross-platform menu implementation in existence (VS Code, Slack, Figma desktop, Obsidian).
- Edit-menu roles matter for a Mac editor: text fields get native Undo/Cut/Copy/Paste only when the roles exist — Electron template makes this a one-liner.
- Verdict: parity in features; Electron's `role` system is less code and fewer platform bugs; Tauri's is fine but younger (menu API landed with 2.0 in Oct 2024).

---

## 6. IPC ergonomics

### Tauri 2
- Commands: Rust `#[tauri::command] fn save_doc(state: State<...>, payload: Doc) -> Result<...>`; registered via `tauri::generate_handler![...]`; JS `import { invoke } from '@tauri-apps/api/core'; await invoke('save_doc', { payload })`. Serde JSON serialization both ways.
- Events: `emit`/`listen` both directions; streaming via `tauri::ipc::Channel<T>` (JS `Channel` in `@tauri-apps/api/core`).
- Raw binary: `invoke(cmd, new Uint8Array(...))` sends a raw body (`tauri::ipc::Request`); Rust can return `tauri::ipc::Response`/`InvokeResponseBody::Raw` to skip JSON.
- **Perf caveat (documented in tauri discussions #5690/#11915)**: JSON IPC is slow for large payloads (reports of ~200 ms for a 3 MB payload; third-party binary-IPC benchmark: 64 KiB roundtrip 6.7 ms via invoke vs 0.6 ms via custom protocol). Mitigation: custom URI-scheme protocols (`register_uri_scheme_protocol`) fetched from JS — effectively a local HTTP path for big blobs. For Thalyx (documents are small text/JSON) this is a non-issue *unless* image export pipelines cross IPC.
- Everything crossing IPC must be declared in capabilities JSON (`core:default`, plugin permissions) — safer, more boilerplate, and a common source of "why is invoke rejected" confusion for LLM-generated code.

### Electron
- `ipcMain.handle('save-doc', handler)` ↔ `await ipcRenderer.invoke('save-doc', payload)` through a `contextBridge.exposeInMainWorld` preload. Structured-clone serialization (handles TypedArrays/Buffers efficiently — no JSON stringify for binary). `MessagePort`s and `utilityProcess` for heavier patterns.
- Same-language both sides (TS everywhere) — simpler for a single-language codebase and for a weaker LLM implementer: one build system (electron-vite), one language, enormous training-data coverage.

---

## 7. Packaging, distribution, auto-update

### Tauri 2
- Built-in bundler targets: `app`, `dmg` (macOS), `deb`, `rpm`, `appimage` (Linux), `nsis`/`msi` (Windows). Config `tauri.conf.json > bundle.targets`. (https://v2.tauri.app/reference/config/)
- **No native Flatpak target**; official guide (https://v2.tauri.app/distribute/flatpak/) builds a `.deb`, extracts it, and repackages into a Flathub manifest on `org.gnome.Platform` runtime (example uses runtime-version 47). Upside: the GNOME runtime **pins WebKitGTK**, giving the only distribution channel where you control the Linux engine version.
- AppImage caveat: webkitgtk is *not* bundled inside the AppImage — system dependency remains.
- Auto-update: `tauri-plugin-updater`. Formats: macOS `.app.tar.gz`; **Linux: AppImage ONLY** (no deb/rpm auto-update); Windows NSIS/MSI. Mandatory signature verification (keypair via `tauri signer generate`, pubkey in `tauri.conf.json`); static JSON manifest (`version`, `platforms.{target}.url`, `.signature`, `notes`, `pub_date`) or dynamic endpoint (200 = update JSON, 204 = none). JS `check()` / `downloadAndInstall()`; Rust `check()` / `download_and_install()`. (https://v2.tauri.app/plugin/updater/)
- CI: `tauri-action` GitHub Action builds+signs all targets; macOS notarization supported via env vars (APPLE_ID etc.).

### Electron
- electron-builder (MIT) targets: macOS `dmg`/`zip`/`mas`; Linux **AppImage, deb, rpm, flatpak, snap, pacman**, tarballs (https://www.electron.build/docs/linux/). Flathub also has an established Electron baseapp (`org.electronjs.Electron2.BaseApp`) — Electron-on-Flathub is a very well-trodden path (hundreds of apps).
- Auto-update: `electron-updater` supports **macOS (zip, code-signing required), Windows NSIS, and Linux AppImage + deb + rpm + pacman** — broader Linux coverage than Tauri's updater (https://www.electron.build/docs/features/auto-update/). Generic HTTPS/GitHub Releases providers; `latest-mac.yml`/`latest-linux.yml` metadata (v27 uses `files[]` format).
- macOS notarization integrated (`@electron/notarize` via electron-builder).

Both: macOS signing+notarization is required for Gatekeeper regardless of framework. Flatpak auto-updates through Flathub itself in both cases (in-app updater should be disabled in Flatpak builds).

---

## 8. Tauri 2 maturity in 2025–2026
- 2.0 stable Oct 2024; steady patch cadence through 2026 (core 2.11.x mid-2026; ecosystem release 2.10.1 Mar 2026; regular CLI/plugin releases — e.g. AppImage symlink fix in CLI 2.11.4). Actively maintained, well funded (Crab Nebula), Rust-audited codebase.
- API surface (menus, multiwebview, mobile) is young relative to Electron's 13 years; issues like accelerator bugs (#12945), notification-plugin gaps (Paseo), and the whole Linux-graphics-workaround page indicate you become a platform-bug triager.
- The maintainers' own bet on CEF/Verso as future engines is the clearest signal that they consider system WebKitGTK a liability. Neither alternative shipped as of Aug 2026.

---

## 9. Real-world signal summary
- Migrated Tauri → Electron: Paseo (May 2026; WebKitGTK layout breakage, Wayland, plugin gaps). OpenCode chose Electron.
- Happy on Tauri: Hoppscotch (API client — form UI, not canvas-heavy).
- Escaped the system webview *within* Tauri: Atrium embedded CEF (+170 MB, heavy native complexity) — i.e., they kept Tauri's shell but abandoned its webviews.
- Canvas-heavy professional editors shipping today (Figma desktop, Excalidraw+/Obsidian(canvas), draw.io desktop) are Electron across the board; no significant OmniGraffle-class editor ships on WebKitGTK.

---

## 10. Native alternatives (brief)
- **Qt 6 (QGraphicsScene/QML)**: technically the best pure-native canvas toolkit (QGraphicsView built for exactly this). But: LGPL-3/GPL/commercial licensing friction for a public-domain project (dynamic-linking obligations, some modules GPL-only); Mermaid still requires a JS engine + DOM → you'd embed QtWebEngine (Chromium, LGPL) anyway; C++/PySide toolchain is far harder for an LLM-driven build. Rejected.
- **GTK4**: LGPL-2.1+, cairo/GSK canvas is capable, but macOS support is second-tier (rendering glitches, non-native feel), and again no Mermaid without a webview. Rejected.
- **Flutter**: BSD-3 (license fine), Impeller canvas is fast, desktop stable. But no DOM: Mermaid import would need mermaid running in a hidden webview (`webview_flutter` has no official Linux desktop support; community `desktop_webview_window` uses… WebKitGTK) or a re-implementation of mermaid's layout (dagre/ELK ports don't exist in Dart at fidelity). Diagramming-widget ecosystem is thin. Rejected.
- Common blocker: Mermaid (and dagre/ELK layout + measured text) is a JS/DOM ecosystem; any non-web shell pays a webview tax anyway, so a web-tech shell is the pragmatic choice.

---

## 11. Recommendation

**Primary: Electron (v43+, MIT) with electron-vite + TypeScript, electron-builder for dmg/AppImage/deb/rpm/Flatpak, electron-updater for auto-update.**

Reasons, ranked:
1. The product *is* the canvas. WebKitGTK is a maintainer-acknowledged source of canvas performance problems (40 vs 240 fps report, DMABUF/NVIDIA breakage, "silently land on a slow path" per Tauri's own docs) and its version is outside the app's control on Linux. Chromium removes the entire class of risk on both OSes.
2. Mermaid's default `foreignObject` HTML labels are a known WebKit failure mode; on Chromium they just work. One engine to test = feasible QA matrix for a small OSS project.
3. WKWebView's ~60 fps cap and micro-lag reports make even macOS second-best under Tauri for high-refresh canvas interaction.
4. Weakest-link implementer: an all-TypeScript, single-runtime stack with massive training-data coverage is far more likely to be executed correctly by a weaker LLM than Rust + capabilities JSON + platform-specific WebKit workarounds.
5. Electron's updater covers deb/rpm/AppImage; Tauri's covers AppImage only.
Accepted costs: ~100–250 MB installs, ~200–400 MB RAM, 8-week Chromium upgrade treadmill (mitigate: Renovate/dependabot pin to latest supported major; keep `contextIsolation: true`, `sandbox: true`, no `nodeIntegration`).

**Fallback: Tauri 2.x** — if bundle size/memory becomes a hard requirement or Electron is vetoed. Mandatory mitigations if chosen:
- Force `htmlLabels: false` in all mermaid rendering.
- Ship the documented WebKitGTK env-var fallbacks (`__NV_DISABLE_EXPLICIT_SYNC`, `WEBKIT_DISABLE_DMABUF_RENDERER`, `WEBKIT_DISABLE_COMPOSITING_MODE`) set from Rust before webview creation, plus an in-app "software rendering" toggle.
- Prefer Flatpak distribution on Linux (pins WebKitGTK via GNOME runtime) over AppImage/deb.
- Keep the renderer abstracted (Canvas2D with dirty-rect discipline; avoid giant DOM/SVG scenes) and benchmark on Ubuntu LTS + NVIDIA early.
- Re-evaluate when Tauri's CEF runtime ships (in progress as of Nov 2025, no ETA) — Tauri+CEF would combine Tauri's shell with Chromium consistency and could flip this recommendation.

## Sources
- https://v2.tauri.app/develop/debug/linux-graphics/
- https://github.com/tauri-apps/tauri/discussions/8524
- https://github.com/tauri-apps/tauri/issues/7021 , https://github.com/tauri-apps/tauri/issues/3988 , https://github.com/tauri-apps/wry/issues/890
- https://webkitgtk.org/2026/03/18/webkitgtk-2.52-highlights.html , https://webkitgtk.org/2025/11/26/webkitgtk-2.50.html
- https://www.gethopp.app/blog/tauri-vs-electron
- https://paseo.sh/blog/i-was-wrong-about-electron
- https://getatrium.dev/blog/embedding-real-browser-tauri
- https://crates.io/crates/tauri-plugin-macos-fps , https://github.com/tauri-apps/tauri/discussions/8436
- https://endoflife.date/electron , https://releases.electronjs.org/
- https://v2.tauri.app/plugin/dialog/ , https://v2.tauri.app/plugin/updater/ , https://v2.tauri.app/learn/window-window-menu/ (menu: https://v2.tauri.app/learn/window-menu/), https://v2.tauri.app/reference/config/ , https://v2.tauri.app/distribute/flatpak/
- https://www.electron.build/docs/linux/ , https://www.electron.build/docs/features/auto-update/
- https://github.com/mermaid-js/mermaid/issues/7565 , https://bugs.webkit.org/show_bug.cgi?id=23113
- https://v2.tauri.app/blog/tauri-verso-integration/ , https://github.com/versotile-org/tauri-runtime-verso
- https://github.com/tauri-apps/tauri/blob/dev/LICENSE.spdx
