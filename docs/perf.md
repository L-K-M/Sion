# Performance gate (M2, PLAN.md §11.7)

## Method

- Fixture: `tests/perf/genDoc.ts` (`generateDoc(n)`) — mixed shapes, 1.5× edges,
  ~10% containers; deterministic structure, loaded into the production renderer
  build via the dev/test hook (`?testHooks=1`).
- Harness: `tests/e2e/web/perf.spec.ts` (Playwright, Chromium):
  - **Pan/zoom fps**: scripted `wheel` dispatch over 4 s (1000-node) /
    3 s (2000-node) while counting `requestAnimationFrame` ticks.
  - **Drag latency**: wall time of a 5-step node drag gesture (pointer-down →
    last move frame applied to the store).
- The spec asserts only loose anti-regression floors; the **acceptance gate**
  (1000-node ≥ 50 fps pan, drag latency < 32 ms on a dev-class machine,
  2000-node ≥ 25 fps) is measured on real hardware.

## Numbers

Measured from the built renderer (`npm run build` + `vite preview`).

| Environment | 1000-node pan fps | 1000-node drag ms | 2000-node pan fps |
|---|---|---|---|
| CI `ubuntu-latest` (headless, software GL) | TBD (fill from first green CI run) | TBD | TBD |
| CI `macos-latest` (headless Chromium) | TBD | TBD | TBD |
| Dev-class machine (manual, per §11.7) | pending | pending | pending |

> CI runners render with software GL — their numbers are a *floor /
> anti-regression baseline*, not the acceptance gate. The §11.7 gate requires
> dev-class hardware numbers for both macOS and Linux; those are recorded
> here when measured (open item — see CHANGELOG M2 deviations).

## Verdict (M2 gate)

Pending: hardware numbers above. CI baselines to be filled on first green run.
LOD fallback (§11.7) not enabled — numbers did not require it so far.
