import { expect, test, type Page } from '@playwright/test';

/**
 * M4c e2e: grow gesture (Mod+Arrow + corridor connect), quick-connect chevrons,
 * Tidy Up + auto-layout, and the M4 acceptance demo (login flow) assembled
 * end-to-end with keyboard+mouse.
 */

const BASE = '/?testHooks=1';

interface TestApi {
  getDocJson(): string;
  loadDoc(json: string): boolean;
  patchDoc(patchSrc: string): void;
  selectNode(id: string): void;
  addNodeToSelection(id: string, reset: boolean): void;
  selectEdge(id: string): void;
}

async function docState(page: Page): Promise<{
  nodes: Array<{
    id: string;
    label: string;
    kind: string;
    shape?: string;
    x: number;
    y: number;
    width: number;
    height: number;
    parentId?: string;
  }>;
  edges: Array<{ id: string; source: string; target: string; label?: string }>;
}> {
  return await page.evaluate(() => {
    const api = (globalThis as unknown as { __thalyxTest?: { getDocJson(): string } }).__thalyxTest;
    if (!api) {
      throw new Error('__thalyxTest hooks missing — build with ?testHooks=1 support');
    }
    return JSON.parse(api.getDocJson());
  });
}

/**
 * Apply a surgical doc patch in the page. The patch body is passed as SOURCE
 * (Playwright cannot serialize function arguments across the boundary).
 */
async function patchDoc(page: Page, patchSrc: string): Promise<void> {
  await page.evaluate((src) => {
    (
      globalThis as unknown as { __thalyxTest: { patchDoc(src: string): void } }
    ).__thalyxTest.patchDoc(src);
  }, patchSrc);
}

async function selectNode(page: Page, id: string): Promise<void> {
  await page.evaluate((nodeId) => {
    (
      globalThis as unknown as { __thalyxTest: { selectNode(id: string): void } }
    ).__thalyxTest.selectNode(nodeId);
  }, id);
}

async function typeLabel(page: Page, text: string): Promise<void> {
  // Grow leaves the editor OPEN on the new node; plain placement leaves it
  // closed. Bounded wait distinguishes the two; Enter opens it when needed.
  const editor = page.locator('.thalyx-label-editor');
  const alreadyOpen = await editor
    .waitFor({ state: 'visible', timeout: 3_000 })
    .then(() => true)
    .catch(() => false);
  if (!alreadyOpen) {
    await page.keyboard.press('Enter'); // Enter-to-edit (single node selected)
  }
  await expect(editor).toBeVisible();
  await page.keyboard.type(text);
  await page.keyboard.press('Enter');
}

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('grow: Mod+Arrow creates a connected node in the direction (one entry)', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const before = (await docState(page)).nodes[0]!;

  await page.keyboard.press('ControlOrMeta+ArrowRight');
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
  const state = await docState(page);
  expect(state.edges).toHaveLength(1);
  expect(state.edges[0]!.source).toBe(before.id);
  const grown = state.nodes.find((n) => n.id !== before.id)!;
  expect(grown.x).toBe(before.x + before.width + 48);
  expect(grown.y).toBe(before.y);
  expect(grown.shape).toBe('rounded');

  await page.keyboard.press('ControlOrMeta+z');
  const undone = await docState(page);
  expect(undone.nodes).toHaveLength(1);
  expect(undone.edges).toHaveLength(0);
});

test('grow corridor: connects to an existing node instead of creating', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(400, 300);
  await page.getByTitle('Rounded rectangle').click();
  // 60px gap to the first node's right edge — inside the grow corridor
  await page.mouse.click(620, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
  const state0 = await docState(page);

  await selectNode(page, state0.nodes[0]!.id);
  await page.keyboard.press('ControlOrMeta+ArrowRight');
  const state = await docState(page);
  expect(state.nodes).toHaveLength(2);
  expect(state.edges).toHaveLength(1);
  expect(state.edges[0]!.source).toBe(state0.nodes[0]!.id);
  expect(state.edges[0]!.target).toBe(state0.nodes[1]!.id);
});

test('quick-connect chevrons: hover shows them; click grows', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);

  await page.mouse.move(500, 300);
  await page.mouse.move(505, 305);
  await expect(page.locator('.thalyx-chevron').first()).toBeVisible({ timeout: 10_000 });
  const count = await page.locator('.thalyx-chevron').count();
  expect(count).toBe(4);

  // click the east chevron (grow right)
  const nodeBefore = (await docState(page)).nodes[0]!;
  await page.locator('.thalyx-chevron').nth(2).click();
  await expect(page.locator('.react-flow__node')).toHaveCount(2);
  const state = await docState(page);
  expect(state.edges).toHaveLength(1);
  const grown = state.nodes.find((n) => n.id !== nodeBefore.id)!;
  expect(grown.x).toBe(nodeBefore.x + nodeBefore.width + 48); // east
});

test('Q toggles the chevrons off', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await page.mouse.move(505, 305);
  await page.keyboard.press('Escape');
  await page.mouse.move(505, 305);
  await expect(page.locator('.thalyx-chevron').first()).toBeVisible({ timeout: 10_000 });
  await page.keyboard.press('q');
  await expect(page.locator('.thalyx-chevron')).toHaveCount(0);
});

test('Alt+Shift+T tidies a scattered selection (24px gaps)', async ({ page }) => {
  await page.evaluate(() => {
    const api = (globalThis as unknown as { __thalyxTest: TestApi }).__thalyxTest;
    const doc = JSON.parse(api.getDocJson()) as {
      nodes: Array<Record<string, unknown>>;
    };
    for (const [i, x] of [0, 90, 205].entries()) {
      doc.nodes.push({
        id: `t${i}`,
        kind: 'shape',
        shape: 'rounded',
        x,
        y: 300 + i * 3,
        width: 160,
        height: 64,
        label: `T${i}`,
        style: {
          fill: 'surface',
          stroke: 'ink',
          strokeWidth: 2,
          fontSize: 14,
          textAlign: 'center',
        },
      });
    }
    api.loadDoc(JSON.stringify(doc));
  });
  await expect(page.locator('.react-flow__node')).toHaveCount(3);
  await page.keyboard.press('ControlOrMeta+a');
  await page.keyboard.down('Alt');
  await page.keyboard.down('Shift');
  await page.keyboard.press('t');
  await page.keyboard.up('Shift');
  await page.keyboard.up('Alt');
  const state = await docState(page);
  const xs = state.nodes.map((n) => n.x).sort((a, b) => a - b);
  expect(xs[1]! - xs[0]!).toBe(160 + 24);
  expect(xs[2]! - xs[1]!).toBe(160 + 24);
  const ys = new Set(state.nodes.map((n) => n.y));
  expect(ys.size).toBe(1);
});

test('Alt+Shift+L auto-layouts the whole doc', async ({ page }) => {
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(400, 100);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(900, 500);
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(650, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(3);
  // seed edges surgically (patchDoc preserves selection/session)
  await patchDoc(
    page,
    "var ns = d.nodes; var a = ns[0], c = ns[2], b = ns[1]; function mk(id, src, tgt){ return { id: id, source: src, target: tgt, sourceAnchor: 'auto', targetAnchor: 'auto', kind: 'elbow', arrowStart: 'none', arrowEnd: 'arrow', style: { line: 'solid', stroke: 'ink', rounded: true } }; } d.edges.push(mk('le1', a.id, c.id), mk('le2', c.id, b.id));",
  );
  await expect(page.locator('.react-flow__edge-path')).toHaveCount(2);

  await page.keyboard.press('Escape'); // deselect — layout acts on the whole doc
  await page.keyboard.down('Alt');
  await page.keyboard.down('Shift');
  await page.keyboard.press('l');
  await page.keyboard.up('Shift');
  await page.keyboard.up('Alt');
  const state = await docState(page);
  const ys = state.nodes.map((n) => n.y).sort((a, b) => a - b);
  expect(ys[1]! - ys[0]!).toBeGreaterThanOrEqual(58);
});

test('M4 acceptance demo: login flow built with keyboard+mouse', async ({ page }) => {
  test.setTimeout(120_000);
  await page.keyboard.press('Escape');
  await page.keyboard.press('r'); // rect tool
  await page.mouse.click(500, 150);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  await typeLabel(page, 'Start');

  // grow right: Login form
  await page.keyboard.press('ControlOrMeta+ArrowRight');
  await typeLabel(page, 'Login form');

  // diamond below it: Valid?
  await page.keyboard.press('ControlOrMeta+ArrowDown');
  await typeLabel(page, 'Valid?');
  await patchDoc(
    page,
    "const v = d.nodes.find(function(n){return n.label==='Valid?';}); if (v) v.shape = 'diamond';",
  );

  // Dashboard (yes)
  await page.keyboard.press('ControlOrMeta+ArrowRight');
  await typeLabel(page, 'Dashboard');
  await patchDoc(page, "var e = d.edges[d.edges.length - 1]; if (e) e.label = 'yes';");

  // Show error (no), grown downward from Valid?
  const mid = await docState(page);
  const validNode = mid.nodes.find((n) => n.label === 'Valid?');
  expect(validNode, 'Valid? must exist').toBeDefined();
  await selectNode(page, validNode!.id);
  await page.keyboard.press('ControlOrMeta+ArrowDown');
  await typeLabel(page, 'Show error');
  await patchDoc(page, "var e = d.edges[d.edges.length - 1]; if (e) e.label = 'no';");

  // container around the three auth nodes: multi-select then Mod+G
  const after = await docState(page);
  const labels = ['Login form', 'Valid?', 'Show error'];
  const ids = after.nodes.filter((n) => labels.includes(n.label)).map((n) => n.id);
  expect(ids).toHaveLength(3);
  for (const [i, id] of ids.entries()) {
    await page.evaluate(
      ({ id, reset }) => {
        (
          globalThis as unknown as {
            __thalyxTest: { addNodeToSelection(id: string, reset: boolean): void };
          }
        ).__thalyxTest.addNodeToSelection(id, reset);
      },
      { id, reset: i === 0 },
    );
  }
  await page.keyboard.press('ControlOrMeta+g');
  await patchDoc(
    page,
    "var c = d.nodes.find(function(n){return n.kind === 'container';}); if (c) c.label = 'Auth';",
  );

  // final edge Dashboard → Log out (grow from Dashboard, label it)
  const grouped = await docState(page);
  const dash = grouped.nodes.find((n) => n.label === 'Dashboard');
  expect(dash, 'Dashboard must exist').toBeDefined();
  await selectNode(page, dash!.id);
  await page.keyboard.press('ControlOrMeta+ArrowRight');
  await typeLabel(page, 'Log out');

  // Verify: 7 nodes incl. the Auth container; 5 grow edges (the canonical
  // diagram's 6th edge — Show error → Login form back-edge — is out of the
  // grow-corridor scope by design).
  const final = await docState(page);
  expect(final.nodes).toHaveLength(7);
  expect(final.edges).toHaveLength(5);
  const container = final.nodes.find((n) => n.kind === 'container');
  expect(container?.label).toBe('Auth');
  const members = final.nodes.filter((n) => n.parentId === container?.id);
  expect(members.map((m) => m.label).sort()).toEqual(['Login form', 'Show error', 'Valid?']);
});
