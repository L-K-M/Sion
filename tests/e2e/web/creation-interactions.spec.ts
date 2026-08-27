import { expect, test, type Page } from '@playwright/test';

const BASE = '/?testHooks=1';

interface TestApi {
  getDocJson(): string;
}

interface DocState {
  nodes: Array<{
    id: string;
    kind: string;
    parentId?: string;
    width: number;
    height: number;
  }>;
}

async function docState(page: Page): Promise<DocState> {
  return page.evaluate(() =>
    JSON.parse((globalThis as unknown as { __thalyxTest: TestApi }).__thalyxTest.getDocJson()),
  );
}

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('dragging a placement tool draws the requested size', async ({ page }) => {
  await page.getByTitle('Rectangle (R)').click();
  await page.mouse.move(350, 260);
  await page.mouse.down();
  await page.mouse.move(570, 390, { steps: 8 });
  await page.mouse.up();

  const state = await docState(page);
  expect(state.nodes).toHaveLength(1);
  expect(state.nodes[0]).toMatchObject({ kind: 'shape', width: 220, height: 130 });
});

test('pressing a placement shortcut twice locks it', async ({ page }) => {
  await page.keyboard.press('r');
  await page.keyboard.press('r');
  await page.mouse.click(380, 300);
  await page.mouse.click(650, 300);

  await expect(page.locator('.react-flow__node')).toHaveCount(2);
});

test('placing a shape inside a frame nests it', async ({ page }) => {
  await page.getByTitle('Container / frame (F)').click();
  await page.mouse.move(300, 220);
  await page.mouse.down();
  await page.mouse.move(760, 520, { steps: 8 });
  await page.mouse.up();
  await page.keyboard.press('Escape');

  const frame = page.locator('.react-flow__node').first();
  const bounds = await frame.boundingBox();
  if (!bounds) throw new Error('frame not visible');

  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(bounds.x + bounds.width / 2, bounds.y + bounds.height / 2);

  const state = await docState(page);
  const container = state.nodes.find((node) => node.kind === 'container')!;
  const child = state.nodes.find((node) => node.kind === 'shape')!;
  expect(child.parentId).toBe(container.id);
});
