import { expect, test, type Page } from '@playwright/test';

/**
 * M4a e2e: inline label editing (incl. type-to-edit precedence), duplicate,
 * smart-guide snapping, group/ungroup containers.
 */

const BASE = '/?testHooks=1';

async function docState(page: Page): Promise<{
  nodes: Array<{
    id: string;
    x: number;
    y: number;
    width: number;
    height: number;
    label: string;
    kind: string;
    parentId?: string;
  }>;
  edges: Array<{ id: string }>;
}> {
  return await page.evaluate(() =>
    JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    ),
  );
}

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('double-click opens the label editor; Enter commits (one undo entry)', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const before = await docState(page);

  await page.mouse.dblclick(500, 300);
  await expect(page.locator('.thalyx-label-editor')).toBeVisible();
  await page.keyboard.type('Login form');
  await page.keyboard.press('Enter');
  await expect(page.locator('.thalyx-label-editor')).toHaveCount(0);
  const after = await docState(page);
  expect(after.nodes[0]!.label).toBe('Login form');

  await page.keyboard.press('ControlOrMeta+z');
  const undone = await docState(page);
  expect(undone.nodes[0]!.label).toBe(before.nodes[0]!.label);
});

test('type-to-edit precedence: a printable char on a selected node starts editing', async ({
  page,
}) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  // node is selected after placement — typing must NOT switch tools
  await page.keyboard.press('x');
  await expect(page.locator('.thalyx-label-editor')).toBeVisible();
  await page.keyboard.press('Enter');
  const state = await docState(page);
  expect(state.nodes[0]!.label).toBe('x');
});

test('tool keys still work with an empty or edge selection (Esc clears)', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  // Esc deselects, then tool keys must fire again
  await page.keyboard.press('Escape');
  await page.keyboard.press('r'); // rect shape tool
  await page.mouse.click(700, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
});

test('Mod+D duplicates the selection with re-ids', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const before = (await docState(page)).nodes[0]!;

  await page.keyboard.press('ControlOrMeta+d');
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
  const nodes = (await docState(page)).nodes;
  const copy = nodes.find((n) => n.id !== before.id)!;
  expect(copy.x).toBe(before.x + 16);
  expect(copy.y).toBe(before.y + 16);
  expect(copy.id).not.toBe(before.id);
});

test('smart guides snap the dragged node to an aligned edge', async ({ page }) => {
  // two nodes at the same y; drag the second until its left edge nears the
  // first's right edge — it must snap to exactly 16px apart… actually to the
  // aligned edge candidate within 6px.
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(400, 300);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(700, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);

  const boxes = await page.locator('.react-flow__node').evaluateAll((els) =>
    els.map((el) => {
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height };
    }),
  );
  const firstRight = boxes[0]!.x + boxes[0]!.w;
  // drag the second node so its left edge lands ~2px past first's right edge
  const targetLeft = firstRight + 2;
  const second = boxes[1]!;
  const dx = targetLeft - second.x;
  await page.mouse.move(second.x + second.w / 2, second.y + second.h / 2);
  await page.mouse.down();
  await page.mouse.move(second.x + second.w / 2 + dx, second.y + second.h / 2, { steps: 10 });
  await page.mouse.up();

  const state = await docState(page);
  const a = state.nodes[0]!;
  const b = state.nodes[1]!;
  // snapped: b's left edge within 0.5px of a's right edge
  expect(Math.abs(b.x - (a.x + a.width))).toBeLessThan(0.5);
});

test('group selection into a container; dissolve restores', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(450, 300);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(650, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);

  // rubber-band select both (drag on empty canvas)
  await page.mouse.move(350, 200);
  await page.mouse.down();
  await page.mouse.move(800, 400, { steps: 6 });
  await page.mouse.up();
  // both selected? group via keyboard
  await page.keyboard.press('ControlOrMeta+g');
  const grouped = await docState(page);
  expect(grouped.nodes).toHaveLength(3);
  const container = grouped.nodes.find((n) => n.kind === 'container')!;
  expect(container).toBeTruthy();
  expect(
    grouped.nodes.filter((n) => n.kind === 'shape').every((n) => n.parentId === container.id),
  ).toBe(true);

  // dissolve
  await page.keyboard.press('ControlOrMeta+Shift+g');
  const dissolved = await docState(page);
  expect(dissolved.nodes).toHaveLength(2);
  expect(dissolved.nodes.every((n) => n.parentId === undefined)).toBe(true);
});

test('F tool places a container by click', async ({ page }) => {
  await page.keyboard.press('f');
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const state = await docState(page);
  expect(state.nodes[0]!.kind).toBe('container');
});
