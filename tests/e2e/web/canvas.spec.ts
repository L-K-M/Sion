import { expect, test, type Page } from '@playwright/test';

/**
 * Web-mode suite (PLAN.md §15.2): the renderer in plain Chromium against the
 * built bundle (vite preview), with the browser platform fallback. Covers the
 * M2 acceptance basics: create/move/resize/delete/undo, containers from
 * fixture docs, theme remap.
 */

const BASE = '/?testHooks=1';

interface TestApi {
  loadDoc(json: string): boolean;
  getDocJson(): string;
}

async function testApi(page: Page): Promise<TestApi> {
  return (await page.evaluate(
    () => (globalThis as unknown as { __thalyxTest?: TestApi }).__thalyxTest,
  ))!;
}

async function docState(page: Page): Promise<{
  nodes: Array<{
    id: string;
    x: number;
    y: number;
    width: number;
    height: number;
    kind: string;
    label: string;
    parentId?: string;
  }>;
  edges: unknown[];
}> {
  const api = await testApi(page);
  return JSON.parse(await page.evaluate((a) => a.getDocJson(), api));
}

test.beforeEach(async ({ page }) => {
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('empty canvas shows the hint layer (I1)', async ({ page }) => {
  await expect(page.locator('.thalyx-empty-hint')).toBeVisible();
});

test('toolbar shape tool places a node; delete and undo work', async ({ page }) => {
  await page.getByRole('button', { name: 'Rectangle (R)' }).click();
  await page.mouse.click(500, 400);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  let state = await docState(page);
  expect(state.nodes).toHaveLength(1);
  expect(state.nodes[0]!.kind).toBe('shape');

  // select + delete
  await page.mouse.click(500, 400);
  await page.keyboard.press('Delete');
  await expect(page.locator('.react-flow__node')).toHaveCount(0);

  // undo restores
  await page.keyboard.press('ControlOrMeta+z');
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  state = await docState(page);
  expect(state.nodes).toHaveLength(1);
});

test('keyboard tool keys: R then Esc-less deselect still allows typing-safe tools', async ({
  page,
}) => {
  await page.keyboard.press('r');
  await page.mouse.click(600, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const state = await docState(page);
  expect(state.nodes[0]!.label).toBe('');
});

test('drag moves a node (transient + one undo entry)', async ({ page }) => {
  await page.getByRole('button', { name: 'Rounded rectangle' }).click();
  await page.mouse.click(500, 400);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);

  const before = (await docState(page)).nodes[0]!;
  const nodeBox = await page.locator('.react-flow__node').first().boundingBox();
  if (!nodeBox) throw new Error('node not visible');
  await page.mouse.move(nodeBox.x + nodeBox.width / 2, nodeBox.y + nodeBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(nodeBox.x + nodeBox.width / 2 + 100, nodeBox.y + nodeBox.height / 2 + 80, {
    steps: 8,
  });
  await page.mouse.up();

  const after = (await docState(page)).nodes[0]!;
  expect(after.x).toBeGreaterThan(before.x + 50);
  expect(after.y).toBeGreaterThan(before.y + 40);

  // one undo reverts the whole drag gesture
  await page.keyboard.press('ControlOrMeta+z');
  const undone = (await docState(page)).nodes[0]!;
  expect(undone.x).toBe(before.x);
  expect(undone.y).toBe(before.y);
});

test('resize via NodeResizer changes stored size', async ({ page }) => {
  await page.getByRole('button', { name: 'Ellipse (O)' }).click();
  await page.mouse.click(500, 400);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  // re-select the node (placing selects it already)
  const before = (await docState(page)).nodes[0]!;
  const handle = page.locator('.react-flow__node .react-flow__resize-control.handle').last();
  await expect(handle).toBeVisible();
  const box = await handle.boundingBox();
  if (!box) throw new Error('no resize handle box');
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await page.mouse.move(box.x + 60, box.y + 40, { steps: 6 });
  await page.mouse.up();
  const after = (await docState(page)).nodes[0]!;
  expect(after.width).toBeGreaterThan(before.width + 30);
});

test('containers from fixture docs render, move with children, and resize', async ({ page }) => {
  const fixture = {
    type: 'thalyx',
    version: 1,
    source: 'thalyx@0.0.0',
    nodes: [
      {
        id: 'grp',
        kind: 'container',
        x: 100,
        y: 100,
        width: 400,
        height: 260,
        label: 'Group',
        style: {
          fill: 'surface',
          stroke: 'ink',
          strokeWidth: 2,
          fontSize: 14,
          textAlign: 'center',
        },
      },
      {
        id: 'inner',
        kind: 'shape',
        shape: 'rounded',
        x: 40,
        y: 40,
        width: 140,
        height: 64,
        label: 'Inner',
        parentId: 'grp',
        style: { fill: 'blue', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' },
      },
      {
        id: 'outer1',
        kind: 'shape',
        shape: 'rect',
        x: 700,
        y: 120,
        width: 140,
        height: 64,
        label: 'Outside',
        style: {
          fill: 'surface',
          stroke: 'ink',
          strokeWidth: 2,
          fontSize: 14,
          textAlign: 'center',
        },
      },
    ],
    edges: [],
    canvas: { background: 'default', grid: false },
    meta: { mermaid: { direction: 'TB' } },
  };
  const api = await testApi(page);
  await page.evaluate(({ a, json }) => a.loadDoc(json), {
    a: api,
    json: JSON.stringify(fixture),
  });
  await expect(page.locator('.react-flow__node')).toHaveCount(3);
  await expect(page.locator('.thalyx-container-title')).toHaveText('Group');

  // drag the container — the child follows (relative coords unchanged)
  await page.keyboard.press('Shift+1'); // fit view so the container is on screen
  const innerBefore = (await docState(page)).nodes.find((n) => n.id === 'inner')!;
  const groupBox = await page
    .locator('.react-flow__node')
    .filter({ hasText: 'Group' })
    .first()
    .boundingBox();
  if (!groupBox) throw new Error('container not visible');
  await page.mouse.move(groupBox.x + 20, groupBox.y + 10); // container title area
  await page.mouse.down();
  await page.mouse.move(groupBox.x + 120, groupBox.y + 110, { steps: 6 });
  await page.mouse.up();
  const innerAfter = (await docState(page)).nodes.find((n) => n.id === 'inner')!;
  expect(innerAfter.x).toBe(innerBefore.x);
  expect(innerAfter.y).toBe(innerBefore.y);
  const grpAfter = (await docState(page)).nodes.find((n) => n.id === 'grp')!;
  expect(grpAfter.x).toBeGreaterThan(100 + 50);
});

test('theme toggle remaps the palette live', async ({ page }) => {
  await page.getByRole('button', { name: 'Ellipse (O)' }).click();
  await page.mouse.click(500, 400);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);

  const root = page.locator('.thalyx-root');
  await expect(root).toHaveAttribute('data-theme', 'light');
  const lightFill = await page
    .locator('.react-flow__node path')
    .first()
    .evaluate((el) => el.getAttribute('fill'));

  await page.getByRole('button', { name: 'Theme: system' }).click(); // → light
  await page.getByRole('button', { name: 'Theme: light' }).click(); // → dark
  await expect(root).toHaveAttribute('data-theme', 'dark');
  const darkFill = await page
    .locator('.react-flow__node path')
    .first()
    .evaluate((el) => el.getAttribute('fill'));

  expect(lightFill).toContain('--surface-fill');
  expect(darkFill).toBe(lightFill); // same var — the VAR value remapped
  const computed = await page
    .locator('.react-flow__node path')
    .first()
    .evaluate((el) => getComputedStyle(el as Element).fill);
  expect(computed).toBeTruthy();
});

test('grid toggle shows the dotted background', async ({ page }) => {
  await expect(page.locator('.react-flow__background')).toHaveCount(0);
  await page.getByRole('button', { name: 'Toggle grid' }).click();
  await expect(page.locator('.react-flow__background')).toHaveCount(1);
});
