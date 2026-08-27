import { expect, test, type Locator, type Page } from '@playwright/test';

const BASE = '/?testHooks=1';
const ENDPOINT_TOLERANCE_PX = 2;

async function createTwoNodes(page: Page): Promise<void> {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(400, 300);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(700, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
}

async function center(locator: Locator): Promise<{ x: number; y: number }> {
  const box = await locator.boundingBox();
  if (!box) throw new Error('element has no bounds');

  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

async function drag(page: Page, source: Locator, target: Locator): Promise<void> {
  const from = await center(source);
  const to = await center(target);
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(to.x, to.y, { steps: 8 });
  await page.mouse.up();
}

async function renderedEndpoints(
  path: Locator,
): Promise<{ start: { x: number; y: number }; end: { x: number; y: number } }> {
  return path.evaluate((element) => {
    const svgPath = element as SVGPathElement;
    const matrix = svgPath.getScreenCTM();
    if (!matrix) throw new Error('edge has no screen transform');
    const transform = (point: DOMPoint) => point.matrixTransform(matrix);
    const start = transform(svgPath.getPointAtLength(0));
    const end = transform(svgPath.getPointAtLength(svgPath.getTotalLength()));
    return { start: { x: start.x, y: start.y }, end: { x: end.x, y: end.y } };
  });
}

test.beforeEach(async ({ page }) => {
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('rejects a self-connection without leaving connection state armed', async ({ page }) => {
  await createTwoNodes(page);
  await page.keyboard.press('Escape');
  await page.keyboard.press('a');
  const first = page.locator('.react-flow__node').first();
  const second = page.locator('.react-flow__node').nth(1);

  await drag(
    page,
    first.locator('.react-flow__handle-right.thalyx-handle'),
    first.locator('.react-flow__handle-top.thalyx-handle'),
  );
  await expect(page.locator('.react-flow__edge')).toHaveCount(0);

  await drag(
    page,
    first.locator('.react-flow__handle-right.thalyx-handle'),
    second.locator('.react-flow__handle-left.thalyx-handle'),
  );
  await expect(page.locator('.react-flow__edge')).toHaveCount(1);
});

test('keeps rendered endpoints on their originating magnets after movement', async ({ page }) => {
  await createTwoNodes(page);
  await page.keyboard.press('Escape');
  await page.keyboard.press('a');
  const first = page.locator('.react-flow__node').first();
  const second = page.locator('.react-flow__node').nth(1);
  const sourceHandle = first.locator('.react-flow__handle-right.thalyx-handle');
  const targetHandle = second.locator('.react-flow__handle-left.thalyx-handle');
  await drag(page, sourceHandle, targetHandle);

  await page.keyboard.press('Escape');
  const secondBox = await second.boundingBox();
  if (!secondBox) throw new Error('target node has no bounds');
  await page.mouse.move(secondBox.x + secondBox.width / 2, secondBox.y + secondBox.height / 2);
  await page.mouse.down();
  await page.mouse.move(
    secondBox.x + secondBox.width / 2 + 80,
    secondBox.y + secondBox.height / 2 + 60,
    { steps: 8 },
  );
  await page.mouse.up();

  const expectedStart = await center(sourceHandle);
  const expectedEnd = await center(targetHandle);
  const endpoints = await renderedEndpoints(page.locator('.react-flow__edge-path'));
  expect(
    Math.hypot(endpoints.start.x - expectedStart.x, endpoints.start.y - expectedStart.y),
  ).toBeLessThanOrEqual(ENDPOINT_TOLERANCE_PX);
  expect(
    Math.hypot(endpoints.end.x - expectedEnd.x, endpoints.end.y - expectedEnd.y),
  ).toBeLessThanOrEqual(ENDPOINT_TOLERANCE_PX);
});
