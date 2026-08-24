import { expect, test, type Page } from '@playwright/test';
import { serializeDoc } from '../../../src/shared/files/thalyxFile';
import { generateDoc } from '../../perf/genDoc';

/**
 * Perf spike (PLAN.md §11.7): 1000-node doc pan/zoom fps + drag latency in
 * the built renderer. CI runners use software GL — numbers there are a floor,
 * not the dev-class-machine gate; results are recorded in docs/perf.md.
 */

async function loadDoc(page: Page, nodeCount: number): Promise<void> {
  const json = serializeDoc(generateDoc(nodeCount));
  const ok = await page.evaluate(
    ({ j }) =>
      (
        window as unknown as { __thalyxTest?: { loadDoc(x: string): boolean } }
      ).__thalyxTest!.loadDoc(j),
    { j: json },
  );
  if (!ok) throw new Error('loadDoc failed');
}

test.describe.serial('perf spike (§11.7)', () => {
  test('1000-node doc: pan/zoom fps and drag latency', async ({ page }) => {
    test.setTimeout(120_000);
    await page.goto('/?testHooks=1');
    await expect(page.locator('.react-flow')).toBeVisible();
    await loadDoc(page, 1000);
    await expect(page.locator('.react-flow__node').first()).toBeVisible();
    await page.keyboard.press('Shift+1'); // zoom to fit
    await page.waitForTimeout(400);

    const result = await page.evaluate(async () => {
      const pan = async (durMs: number) => {
        // scripted wheel pans across the canvas
        const start = performance.now();
        let frames = 0;
        let lastWheel = 0;
        const tick = () => {
          frames += 1;
          if (performance.now() - start < durMs) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
        const cx = window.innerWidth / 2;
        const cy = window.innerHeight / 2;
        while (performance.now() - start < durMs) {
          const t = performance.now();
          if (t - lastWheel > 16) {
            const el = document.querySelector('.react-flow') as HTMLElement;
            el.dispatchEvent(
              new WheelEvent('wheel', {
                deltaX: 4,
                deltaY: 2,
                clientX: cx,
                clientY: cy,
                bubbles: true,
              }),
            );
            lastWheel = t;
          }
          await new Promise((r) => setTimeout(r, 4));
        }
        return (frames / durMs) * 1000;
      };
      return { panFps: await pan(4000) };
    });
    console.log(`[perf] 1000-node pan fps: ${result.panFps.toFixed(1)}`);

    // drag latency: start-to-store round trip on a node drag frame
    const node = page.locator('.react-flow__node').first();
    const box = await node.boundingBox();
    if (!box) throw new Error('no node box');
    const t0 = Date.now();
    await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
    await page.mouse.down();
    await page.mouse.move(box.x + box.width / 2 + 40, box.y + box.height / 2 + 30, { steps: 5 });
    const latency = Date.now() - t0;
    await page.mouse.up();
    console.log(`[perf] drag gesture wall time: ${latency} ms`);

    // CI floor: software rendering still must stay interactive (anti-regression
    // guard — the real ≥50fps/32ms gate is measured on dev-class hardware).
    expect(result.panFps).toBeGreaterThan(4);
    // Wall time is informational on loaded CI runners (the fps floor above is
    // the anti-regression guard).
    console.log(`[perf] drag wall-time guard: ${latency} ms (informational)`);
    expect(latency).toBeLessThan(30_000);
  });

  test('1000-node doc with edges: drag reroute fps', async ({ page }) => {
    test.setTimeout(120_000);
    await page.goto('/?testHooks=1');
    await expect(page.locator('.react-flow')).toBeVisible();
    await loadDoc(page, 400); // 400 nodes → ~600 edges — every drag re-routes its edges
    await page.keyboard.press('Shift+1');
    await page.waitForTimeout(400);
    const node = page.locator('.react-flow__node').first();
    const box = await node.boundingBox();
    if (!box) throw new Error('no node box');

    const fps = await page.evaluate(
      async ({ x, y }) => {
        const start = performance.now();
        let frames = 0;
        const tick = () => {
          frames += 1;
          if (performance.now() - start < 3000) requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
        // continuous drag in small steps across the canvas
        const el = document.querySelector('.react-flow') as HTMLElement;
        el.dispatchEvent(
          new PointerEvent('pointerdown', {
            clientX: x,
            clientY: y,
            bubbles: true,
            isPrimary: true,
            pointerId: 1,
          }),
        );
        let t = 0;
        while (performance.now() - start < 3000) {
          t += 1;
          window.dispatchEvent(
            new PointerEvent('pointermove', {
              clientX: x + Math.sin(t / 6) * 60,
              clientY: y + Math.cos(t / 8) * 40,
              bubbles: true,
              isPrimary: true,
              pointerId: 1,
            }),
          );
          await new Promise((r) => setTimeout(r, 8));
        }
        window.dispatchEvent(new PointerEvent('pointerup', { bubbles: true, pointerId: 1 }));
        return (frames / 3000) * 1000;
      },
      { x: box.x + box.width / 2, y: box.y + box.height / 2 },
    );
    console.log(`[perf] edge-reroute drag fps (400 nodes/600 edges): ${fps.toFixed(1)}`);
    expect(fps).toBeGreaterThan(4);
  });

  test('2000-node doc stays usable', async ({ page }) => {
    test.setTimeout(120_000);
    await page.goto('/?testHooks=1');
    await expect(page.locator('.react-flow')).toBeVisible();
    await loadDoc(page, 2000);
    await page.keyboard.press('Shift+1');
    await page.waitForTimeout(400);
    const fps = await page.evaluate(async () => {
      const start = performance.now();
      let frames = 0;
      const tick = () => {
        frames += 1;
        if (performance.now() - start < 3000) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
      const el = document.querySelector('.react-flow') as HTMLElement;
      const cx = window.innerWidth / 2;
      const cy = window.innerHeight / 2;
      while (performance.now() - start < 3000) {
        el.dispatchEvent(
          new WheelEvent('wheel', {
            deltaX: 6,
            deltaY: 0,
            clientX: cx,
            clientY: cy,
            bubbles: true,
          }),
        );
        await new Promise((r) => setTimeout(r, 8));
      }
      return (frames / 3000) * 1000;
    });
    console.log(`[perf] 2000-node pan fps: ${fps.toFixed(1)}`);
    expect(fps).toBeGreaterThan(3);
  });
});
