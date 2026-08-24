import { expect, test, type Page } from '@playwright/test';

/**
 * M3 e2e: the connector experience (I7–I9) — connect from a handle, edge
 * renders and re-routes on node drag, edge selection/deletion, label chip.
 */

const BASE = '/?testHooks=1';

async function docState(page: Page): Promise<{
  nodes: Array<{ id: string; x: number; y: number; label: string }>;
  edges: Array<{ id: string; source: string; target: string; label?: string }>;
}> {
  return await page.evaluate(() =>
    JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    ),
  );
}

async function nodeBoxes(
  page: Page,
): Promise<Array<{ x: number; y: number; width: number; height: number } | null>> {
  return await page.locator('.react-flow__node').evaluateAll((els) =>
    els.map((el) => {
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height };
    }),
  );
}

interface Box {
  x: number;
  y: number;
  width: number;
  height: number;
}

async function placeTwoNodes(page: Page): Promise<{ aBox: Box; bBox: Box }> {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(400, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(700, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
  const boxes = await nodeBoxes(page);
  return { aBox: boxes[0]!, bBox: boxes[1]! };
}

async function targetHandlePoint(page: Page): Promise<{ x: number; y: number }> {
  const h = await page
    .locator('.react-flow__node')
    .nth(1)
    .locator('.react-flow__handle-left.thalyx-handle')
    .boundingBox();
  if (!h) throw new Error('no target handle');
  return { x: h.x + h.width / 2, y: h.y + h.height / 2 };
}

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('connect two nodes by dragging from a handle (arrow tool)', async ({ page }) => {
  await placeTwoNodes(page);
  await page.keyboard.press('Escape'); // deselect — printable keys would start label editing (§10.2)
  await page.keyboard.press('a'); // arrow tool
  const handle = page
    .locator('.react-flow__node')
    .first()
    .locator('.react-flow__handle-right.thalyx-handle');
  await expect(handle).toBeVisible();
  const hBox = await handle.boundingBox();
  if (!hBox) throw new Error('no handle box');
  await page.mouse.move(hBox.x + hBox.width / 2, hBox.y + hBox.height / 2);
  await page.mouse.down();
  const drop = await targetHandlePoint(page);
  await page.mouse.move(drop.x, drop.y, { steps: 8 });
  await page.mouse.up();

  const state = await docState(page);
  expect(state.edges).toHaveLength(1);
  expect(state.edges[0]!.source).toBe(state.nodes[0]!.id);
  expect(state.edges[0]!.target).toBe(state.nodes[1]!.id);
  await expect(page.locator('.react-flow__edge-path')).toHaveCount(1);
  expect(
    (await page.locator('.react-flow__edge-path').first().getAttribute('d'))!.length,
  ).toBeGreaterThan(10);
});

test('line tool connects without arrowheads', async ({ page }) => {
  await placeTwoNodes(page);
  await page.keyboard.press('Escape'); // deselect
  await page.keyboard.press('l'); // line tool
  const handle = page
    .locator('.react-flow__node')
    .first()
    .locator('.react-flow__handle-right.thalyx-handle');
  const hBox = await handle.boundingBox();
  if (!hBox) throw new Error('no handle box');
  await page.mouse.move(hBox.x + hBox.width / 2, hBox.y + hBox.height / 2);
  await page.mouse.down();
  const drop = await targetHandlePoint(page);
  await page.mouse.move(drop.x, drop.y, { steps: 8 });
  await page.mouse.up();
  const state = await docState(page);
  expect(state.edges).toHaveLength(1);
  // no marker elements rendered for a headless edge
  await expect(page.locator('.react-flow__edge marker')).toHaveCount(0);
  await expect(page.locator('.react-flow__edge-path').first()).toBeVisible();
});

test('edge re-routes when a node drags (derived geometry, D12)', async ({ page }) => {
  const { aBox } = await placeTwoNodes(page);
  await page.keyboard.press('a');
  const handle = page
    .locator('.react-flow__node')
    .first()
    .locator('.react-flow__handle-right.thalyx-handle');
  const hBox = await handle.boundingBox();
  await page.mouse.move(hBox!.x + 4, hBox!.y + 4);
  await page.mouse.down();
  const drop = await targetHandlePoint(page);
  await page.mouse.move(drop.x, drop.y, { steps: 8 });
  await page.mouse.up();
  await expect(page.locator('.react-flow__edge')).toHaveCount(1);

  const before = await page.locator('.react-flow__edge-path').first().getAttribute('d');
  // drag node A — the path must change (re-route)
  await page.mouse.move(aBox!.x + aBox!.width / 2, aBox!.y + aBox!.height / 2);
  await page.mouse.down();
  await page.mouse.move(aBox!.x + aBox!.width / 2 - 120, aBox!.y + aBox!.height / 2 - 80, {
    steps: 8,
  });
  await page.mouse.up();
  const after = await page.locator('.react-flow__edge-path').first().getAttribute('d');
  expect(after).not.toBe(before);
});

test('edge selection + delete; undo restores (one entry per intent)', async ({ page }) => {
  await placeTwoNodes(page);
  await page.keyboard.press('a');
  const handle = page
    .locator('.react-flow__node')
    .first()
    .locator('.react-flow__handle-right.thalyx-handle');
  const hBox = await handle.boundingBox();
  await page.mouse.move(hBox!.x + 4, hBox!.y + 4);
  await page.mouse.down();
  const drop = await targetHandlePoint(page);
  await page.mouse.move(drop.x, drop.y, { steps: 8 });
  await page.mouse.up();
  await expect(page.locator('.react-flow__edge')).toHaveCount(1);

  // click the edge path to select, then delete
  const edgePath = page.locator('.react-flow__edge-path').first();
  await edgePath.click({ position: { x: 20, y: 5 }, force: true });
  await page.keyboard.press('Delete');
  await expect(page.locator('.react-flow__edge')).toHaveCount(0);
  const state = await docState(page);
  expect(state.edges).toHaveLength(0);

  await page.keyboard.press('ControlOrMeta+z');
  const undone = await docState(page);
  expect(undone.edges).toHaveLength(1);
});

test('label via test hook renders a chip; stays legible over the line', async ({ page }) => {
  await placeTwoNodes(page);
  await page.keyboard.press('a');
  const handle = page
    .locator('.react-flow__node')
    .first()
    .locator('.react-flow__handle-right.thalyx-handle');
  const hBox = await handle.boundingBox();
  await page.mouse.move(hBox!.x + 4, hBox!.y + 4);
  await page.mouse.down();
  const drop = await targetHandlePoint(page);
  await page.mouse.move(drop.x, drop.y, { steps: 8 });
  await page.mouse.up();
  await expect(page.locator('.react-flow__edge')).toHaveCount(1);

  const state = await docState(page);
  await page.evaluate(
    ({ id }) => {
      const api = (
        globalThis as unknown as {
          __thalyxTest: { loadDoc(json: string): boolean; getDocJson(): string };
        }
      ).__thalyxTest;
      const doc = JSON.parse(api.getDocJson());
      doc.edges.find((e: { id: string }) => e.id === id).label = 'yes!';
      api.loadDoc(JSON.stringify(doc));
    },
    { id: state.edges[0]!.id },
  );
  await expect(page.locator('.thalyx-edge-label')).toHaveText('yes!');
  // chip has an opaque canvas background so it reads over the line
  const bg = await page
    .locator('.thalyx-edge-label')
    .evaluate((el) => getComputedStyle(el).backgroundColor);
  expect(bg).not.toBe('rgba(0, 0, 0, 0)');
});
