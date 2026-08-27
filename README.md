# Thalyx

A cross-platform (macOS + Linux) desktop diagramming tool in the spirit of
OmniGraffle, with a ruthless focus on **simple, fast, user-friendly UX**, and
with **Mermaid as a first-class citizen**:

**Latest release:** v<!-- version -->0.1.0<!-- /version --> · [Download](https://github.com/L-K-M/Thalyx/releases/latest)

- **Paste or open Mermaid text** and it becomes a fully editable diagram
  (flowcharts convert to native shapes and connectors; every other Mermaid
  diagram type renders as a live, text-editable "island").
- **Export the logical structure of any diagram back to clean, idiomatic
  Mermaid** — the graph (nodes, edges, labels, containers) is always a
  first-class model, so Mermaid export is pure serialization, never inference.
- **Native high-fidelity drag-and-drop editing**: real shapes, elbow
  connectors that never detach, smart alignment guides, keyboard-driven
  diagram growth, one-shot auto-layout, dark mode, SVG/PNG/PDF export.

**Status:** implementation in progress, milestone by milestone per
[PLAN.md](PLAN.md) (the authoritative plan; the research behind it lives in
[`docs/research/`](docs/research/)). See [CHANGELOG.md](CHANGELOG.md) for
progress and deviations.

## Stack

Electron · React · TypeScript (strict) · React Flow (`@xyflow/react`) ·
zustand · mermaid (pinned `11.17.0`) · `@dagrejs/dagre` · vitest · Playwright.
Single npm package; public-domain source (Unlicense).

## Platform support (verified for Electron 43, 2026-08)

- **macOS** 12 "Monterey" and up — universal builds (arm64 + x64 dmg).
- **Linux** — built on Ubuntu 22.04; verified against Ubuntu 18.04+, Debian
  10+, Fedora 32+ (AppImage, deb, rpm).
- Windows is out of scope for this plan (PLAN.md D18).

## Development

Requirements: Node.js ≥ 24, npm ≥ 11.

```bash
npm install        # install toolchain (downloads the Electron binary)
npm run dev        # launch the app with hot reload
npm run typecheck  # tsc over node + web project configs
npm run lint       # eslint
npm run format     # prettier (write); `npm run format:check` in CI
npm test           # vitest unit suite
npm run build      # production build to out/
npm run e2e        # Playwright Electron smoke suite (build first)
npm run package    # unsigned local installers via electron-builder
npm run check:licenses   # license gate (PLAN.md §4)
npm run gen:licenses     # regenerate THIRD_PARTY_LICENSES.md
```

Contributions are accepted as public-domain dedications — see
[CONTRIBUTING.md](CONTRIBUTING.md).

## License

Thalyx's own code is dedicated to the public domain under the
[Unlicense](LICENSE). Bundled dependencies keep their own permissive licenses
(see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) and PLAN.md §4 for the
dependency licensing policy).
