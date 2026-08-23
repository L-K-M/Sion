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

| Environment | 1000-node pan fps | 1000-node drag gesture | 2000-node pan fps |
|---|---|---|---|
| CI `ubuntu-latest` (headless Chromium, software GL) — [run](https://github.com/L-K-M/Thalyx/actions/runs/32667795720) | **60.3** | 772 ms (whole-gesture wall time, 5 pointer steps — see note) | **60.3** |
| CI `macos-latest` (headless Chromium) — same run | **50.8** | 577 ms (same metric) | **54.7** |
| Dev-class machine (manual, per §11.7) | pending | pending | pending |

> CI runners render with software GL — their numbers are a *floor /
> anti-regression baseline*, not the acceptance gate. They already exceed the
> §11.7 thresholds (≥ 50 fps @ 1000 nodes, ≥ 25 fps @ 2000 nodes), which at
> 50+ fps implies per-frame latency under 20 ms; the harness's "drag gesture"
> number is the whole scripted-gesture wall time (Playwright round trips), not
> the per-frame input-to-store latency the plan's < 32 ms refers to. The
> §11.7 gate is formally closed by dev-class hardware numbers on both macOS
> and Linux — recorded here when measured (open item — see CHANGELOG M2
> deviations).

## Verdict (M2 gate)

CI baselines recorded above (both OSes exceed the fps thresholds even under
software GL). Hardware measurement remains the formal open item. LOD
fallback (§11.7) not enabled — numbers did not require it.
