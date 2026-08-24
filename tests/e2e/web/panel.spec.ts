import { expect, test, type Page } from '@playwright/test';

/**
 * M4b e2e: context panel (selection-scoped controls + palette + alignment),
 * help overlay, keymap chords (Shift+Alt+D theme, Shift+/ help).
 */

const BASE = '/?testHooks=1';

async function docState(page: Page): Promise<{
  edges: Array<{ id: string; style: { line: string } }>;
  canvas: { grid: boolean };
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
  await expect(panel.getByRole('radiogroup', { name: 'Grid' })).toBeVisible();
  // grid toggle round-trips into the doc (assert the flip, not just any value)
  const gridBefore = (await docState(page)).canvas.grid;
  await panel.getByRole('radiogroup', { name: 'Grid' }).getByRole('radio', { name: 'On' }).click();
  const state = await docState(page);
  expect(state.canvas.grid).toBe(!gridBefore);
});

test('node selection shows fill palette; applying a token updates the doc', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);

  const panel = page.locator('.thalyx-panel');
  await expect(panel.locator('.thalyx-panel-title')).toHaveText('Shape');
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
  await page.mouse.click(450, 300);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(650, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);

  // rubber-band both — the exact gesture the (passing) group test uses
  await page.mouse.move(350, 200);
  await page.mouse.down();
  await page.mouse.move(800, 400, { steps: 6 });
  await page.mouse.up();

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

  // select the edge through the dev hook (real pointer selection is covered
  // by connections.spec; this test targets the panel)
  await page.evaluate(() => {
    (
      globalThis as unknown as { __thalyxTest: { selectEdge(id: string): void } }
    ).__thalyxTest.selectEdge('e1');
  });
  const panel = page.locator('.thalyx-panel');
  await expect(panel.locator('.thalyx-panel-title')).toHaveText('Connector');
  await panel.locator('[role="radiogroup"]').first().getByRole('radio').nth(1).click();
  const state = await docState(page);
  expect(state.edges[0]!.style.line).toBe('dashed');
});

test('help overlay opens with Shift+/ and filters', async ({ page }) => {
  await page.keyboard.press('Shift+Slash');
  await expect(page.locator('.thalyx-help')).toBeVisible();
  const rowCount = await page.locator('.thalyx-help-row').count();
  expect(rowCount).toBeGreaterThanOrEqual(30);
  await page.locator('.thalyx-help-search').fill('undo');
  await expect(page.locator('.thalyx-help-row')).toHaveCount(1);
  await page.keyboard.press('Escape');
  await expect(page.locator('.thalyx-help')).toHaveCount(0);
});

test('Shift+Alt+D cycles the theme', async ({ page }) => {
  await expect(page.locator('.thalyx-root')).toHaveAttribute('data-theme', 'light');
  const pressChord = () =>
    page.evaluate(() => {
      window.dispatchEvent(
        new KeyboardEvent('keydown', {
          code: 'KeyD',
          key: 'D',
          altKey: true,
          shiftKey: true,
          bubbles: true,
        }),
      );
    });
  await pressChord(); // system -> light (attribute stays light)
  await expect(page.locator('.thalyx-root')).toHaveAttribute('data-theme', 'light');
  await pressChord(); // light -> dark
  await expect(page.locator('.thalyx-root')).toHaveAttribute('data-theme', 'dark');
  await pressChord(); // dark -> system
  await expect(page.locator('.thalyx-root')).toHaveAttribute('data-theme', 'light');
});

test('custom hex fill via the escape hatch', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  const colorInput = page.locator('.thalyx-swatch-custom input');
  await colorInput.evaluate((el, v) => {
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')!.set!;
    setter.call(el, v);
    el.dispatchEvent(new Event('input', { bubbles: true }));
  }, '#12ab34');
  const state = await docState(page);
  expect(state.nodes[0]!.style.fill.toLowerCase()).toBe('#12ab34');
});
