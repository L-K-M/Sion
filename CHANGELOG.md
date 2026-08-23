# Changelog

All notable changes to Thalyx are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/). The authoritative roadmap is
[PLAN.md](PLAN.md) §17 — each milestone lands as its own PR and records any
deviations from the plan here (per PLAN.md §19.6–7).

## [Unreleased]

### M1 — Document model, store, history (PLAN.md §17 M1)

Added:

- `src/shared/model/`: `types.ts` (§7.1 authoritative types), `schema.ts`
  (zod v4 with §14.6 bounds: labels ≤ 4 kB, ≤ 20 k nodes, finite geometry,
  size ≥ 8), `create.ts` (newDoc/newNode/newEdge factories with §10.4
  defaults), `restore.ts` (normalize-on-load per §7.5: DocTooNewError for
  version > 1, coercion, dangling/island edge dropping, parent/cycle repair,
  z-order fix, clamps, final zod assertion), `queries.ts` (absolute-position
  math, bounds, containment/descendants, edge selectors,
  `positionUnderParent` for invariant §7.2.7).
- `src/shared/files/thalyxFile.ts`: serializeDoc (2-space pretty + trailing
  newline, known-fields rebuild) / parseDoc (JSON.parse → restore).
- `src/shared/snap/snap.ts`: the `GuideLine` type only (session slice needs it
  per §8.1; the computeSnap engine lands in M4).
- `src/renderer/store/`: `history.ts` (snapshot undo/redo per §8.2 — commit /
  beginGesture / endGesture / undo / redo, LIMIT 100, structural sharing via
  reference identity), `store.ts` (zustand doc+session slices exactly per
  §8.1), `actions.ts` (§8.3 catalog for M1 scope: node/edge CRUD, transient
  move/resize inside gestures, delete/duplicate/paste with re-id + intra-edge
  preservation, align, z-order (block moves with descendants),
  group/dissolve containers with absolute-position-preserving re-parenting,
  waypoints + D12 clear-on-endpoint-move, canvas/direction/grid, session
  setters). Mermaid/layout actions arrive with M4–M8 per the milestone plan.
- Tests (70): restore garbage/idempotence (`restore(restore(x)) == restore(x)`),
  invariants 1–6, schema bounds, file round-trip/fixpoint, history semantics
  incl. gesture coalescing + limit + snapshot identity, action-level invariant
  enforcement (one history entry per intent), and the mutation-through-actions
  convention test (`setStore` only in store.ts/actions.ts; shared never imports
  renderer).

Changed / deviations from PLAN.md (§19.6):

- Dependency versions moved to current stable: `immer ^11.1.18` (plan said
  ^10), `nanoid ^6.0.1` (plan said ^5; API `nanoid(12)` verified unchanged),
  `zustand ^5.0.15`, `zod ^4.4.3` (as planned). THIRD_PARTY_LICENSES.md
  regenerated (9 bundled runtime deps now).

### M0 — Scaffold & guardrails (PLAN.md §17 M0)

Added:

- Electron + React + TypeScript scaffold via electron-vite, per the PLAN.md §6
  tree: `src/main` (window + lifecycle + security baseline), `src/preload`
  (contextBridge `window.thalyx` with stub `appx.version()`), `src/renderer`
  (splash), `src/shared` (doc-schema constants).
- Security baseline per §14.1–2: context isolation + sandbox + no node
  integration; `will-navigate` block; window-open deny; render-process-gone
  reload; CSP meta injected per build mode by a Vite HTML transform (strict in
  production, HMR allowances in dev).
- License gate: `scripts/check-licenses.mjs` (production violations fail CI,
  dev violations warn) + `scripts/gen-third-party-licenses.mjs` generating
  `THIRD_PARTY_LICENSES.md`; dompurify Apache-2.0 election map (D17).
- CI: typecheck + eslint + prettier + license gate + vitest on ubuntu; Playwright
  Electron smoke + unsigned electron-builder packaging on ubuntu & macos.
- vitest with the first shared-module test; Playwright smoke suite (launch,
  sandbox check, strict-CSP assertion on the packaged index.html).
- Renovate config (weekly; grouped minor/patch; electron majors individual;
  mermaid disabled per D16); CONTRIBUTING.md (Unlicense dedication policy);
  README skeleton.

Changed / deviations from PLAN.md (per §19.6 — reality verified 2026-08-23):

- **electron-builder `^26.15.3`** instead of the plan's `^27`: 26.15.3 is the
  current stable; 27 exists only as `27.0.0-alpha.7`. Will adopt 27 when
  stable.
- **typescript `~5.9.3`** instead of "current" (7.0.2): typescript-eslint
  8.67.0 peer-supports `typescript <6.1.0`. Revisit when typescript-eslint
  supports TS 7.
- **vite `^7.3.6`** instead of 8.2.2: electron-vite 5.0.0 peers
  `vite ^5||^6||^7`. Will move with electron-vite.
- `@vitejs/plugin-react ^5.2.0` (supports vite 4–8; 6.x requires vite 8).

Verified at M0 (task 3): Electron 43.4.1 (Chromium 150, Node 24.18.1; darwin
x64+arm64; macOS ≥ 12 "Monterey"; Linux built on Ubuntu 22.04, verified
Ubuntu 18.04+/Debian 10+/Fedora 32+); zustand current major is 5 (installed at
M1); Playwright 1.62.1 `_electron` API confirmed by the smoke suite; Open
Color license is MIT (ledger entry added).
