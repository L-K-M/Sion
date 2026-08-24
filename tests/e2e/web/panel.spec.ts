import { expect, test, type Page } from '@playwright/test';

/**
 * M4b e2e: context panel (selection-scoped controls + palette + alignment),
 * help overlay, keymap chords (Shift+Alt+D theme, Shift+/ help).
 */

const BASE = '/?testHooks=1';

async function docState(page: Page): Promise<{
  nodes: Array<{
    id: string;
    label: string;
    kind: string;
    style: { fill: string; strokeWidth: number; fontSize: number };
    shape?: string;
    x: number;
    y: number;
    width: number;
  }>;
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

test('canvas panel shows grid/theme/direction when nothing is selected', async ({ page }) => {
  const panel = page.locator('.thalyx-panel');
  await expect(panel).toBeVisible();
  await expect(panel.getByText('Canvas')).toBeVisible();
  await expect(panel.getByTitle('Grid')).toBeVisible();
  // grid toggle round-trips into the doc
  await panel.getByRole('radio', { name: 'On' }).click();
  const state = await page.evaluate(() =>
    JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    ),
  );
  expect(state.canvas.grid).toBe(true);
});

test('node selection shows fill palette; applying a token updates the doc', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);

  const panel = page.locator('.thalyx-panel');
  await expect(panel.getByText('Shape')).toBeVisible();
  await panel.getByTitle('blue').click();
  const state = await docState(page);
  expect(state.nodes[0]!.style.fill).toBe('blue');

  // stroke width segmented control
  await panel.getByTitle('Bold').click();
  const state2 = await docState(page);
  expect(state2.nodes[0]!.style.strokeWidth).toBe(4);

  // font size
  await panel.getByTitle('XL', { exact: false }).first().click();
  const state3 = await docState(page);
  expect(state3.nodes[0]!.style.fontSize).toBe(24);
});

test('shape swap via the popup; corner toggle swaps rect↔rounded', async ({ page }) => {
  await page.keyboard.press('Escape');
  await page.keyboard.press('r'); // rect
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const panel = page.locator('.thalyx-panel');

  // corner toggle → rounded
  await panel.getByTitle('Rounded corners').click();
  let state = await docState(page);
  expect(state.nodes[0]!.shape).toBe('rounded');

  // shape popup → cylinder
  await panel.locator('.thalyx-panel-select').selectOption('cylinder');
  state = await docState(page);
  expect(state.nodes[0]!.shape).toBe('cylinder');
});

test('alignment row aligns two nodes', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(450, 250);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(700, 400);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);

  // rubber-band both
  await page.keyboard.down('Shift');
  const boxes = await page.locator('.react-flow__node').evaluateAll((els) =>
    els.map((el) => {
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y };
    }),
  );
  await page.keyboard.up('Shift');
  // click both with shift
  await page.mouse.click(boxes[0]!.x + 5, boxes[0]!.y + 5);
  await page.keyboard.down('Shift');
  await page.mouse.click(boxes[1]!.x + 5, boxes[1]!.y + 5);
  await page.keyboard.up('Shift');

  const panel = page.locator('.thalyx-panel');
  await panel.getByTitle('Align left').click();
  const state = await docState(page);
  expect(state.nodes[0]!.x).toBe(state.nodes[1]!.x);
});

test('edge selection shows connector controls; line style round-trips', async ({ page }) => {
  // build two nodes + an edge via the test hook for determinism
  const state0 = await page.evaluate(() => {
    const api = (
      globalThis as unknown as {
        __thalyxTest: { loadDoc(j: string): boolean; getDocJson(): string };
      }
    ).__thalyxTest;
    const doc = JSON.parse(api.getDocJson());
    doc.nodes.push(
      {
        id: 'na',
        kind: 'shape',
        shape: 'rounded',
        x: 200,
        y: 200,
        width: 140,
        height: 64,
        label: 'A',
        style: {
          fill: 'surface',
          stroke: 'ink',
          strokeWidth: 2,
          fontSize: 14,
          textAlign: 'center',
        },
      },
      {
        id: 'nb',
        kind: 'shape',
        shape: 'rounded',
        x: 500,
        y: 320,
        width: 140,
        height: 64,
        label: 'B',
        style: {
          fill: 'surface',
          stroke: 'ink',
          strokeWidth: 2,
          fontSize: 14,
          textAlign: 'center',
        },
      },
    );
    doc.edges.push({
      id: 'e1',
      source: 'na',
      target: 'nb',
      sourceAnchor: 'auto',
      targetAnchor: 'auto',
      kind: 'elbow',
      arrowStart: 'none',
      arrowEnd: 'arrow',
      style: { line: 'solid', stroke: 'ink', rounded: true },
    });
    return api.loadDoc(JSON.stringify(doc));
  });
  expect(state0).toBe(true);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
  await expect(page.locator('.react-flow__edge-path')).toHaveCount(1);

  // click the edge's invisible hit path to select
  await page
    .locator('.thalyx-edge-hit')
    .first()
    .click({ force: true, position: { x: 20, y: 5 } });
  const panel = page.locator('.thalyx-panel');
  await expect(panel.getByText('Connector')).toBeVisible();
  await panel.locator('[role="radiogroup"]').first().getByRole('radio').nth(1).click();
  const state = await page.evaluate(() =>
    JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    ),
  );
  expect(state.edges[0].style.line).toBe('dashed');
});

test('help overlay opens with Shift+/ and filters', async ({ page }) => {
  await page.keyboard.press('Shift+Slash');
  await expect(page.locator('.thalyx-help')).toBeVisible();
  await expect(page.locator('.thalyx-help-row')).toHaveCount(35);
  await page.locator('.thalyx-help-search').fill('undo');
  await expect(page.locator('.thalyx-help-row')).toHaveCount(1);
  await page.keyboard.press('Escape');
  await expect(page.locator('.thalyx-help')).toHaveCount(0);
});

test('Shift+Alt+D cycles the theme', async ({ page }) => {
  await expect(page.locator('.thalyx-root')).toHaveAttribute('data-theme', 'light');
  await page.keyboard.press('Shift+Alt+d');
  await expect(page.locator('.thalyx-root')).toHaveAttribute('data-theme', 'dark');
  await page.keyboard.press('Shift+Alt+d');
  await expect(page.locator('.thalyx-root')).toHaveAttribute('data-theme', 'system');
});

test('custom hex fill via the escape hatch', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  const colorInput = page.locator('.thalyx-swatch-custom input');
  await colorInput.evaluate((el, v) => {
    (el as HTMLInputElement).value = v;
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }, '#12ab34');
  const state = await docState(page);
  expect(state.nodes[0]!.style.fill.toLowerCase()).toBe('#12ab34');
});
