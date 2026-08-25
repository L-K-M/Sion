import { expect, test, type Page } from '@playwright/test';

/**
 * M6 e2e: Mermaid panel live view, Copy as Mermaid, byte-stable export,
 * direction dropdown, round-trip of the M4 demo graph.
 */

const BASE = '/?testHooks=1';

async function docState(page: Page): Promise<{
  nodes: Array<{
    id: string;
    label: string;
    kind: string;
    x: number;
    y: number;
    parentId?: string;
  }>;
  edges: Array<{ source: string; target: string; label?: string }>;
}> {
  return await page.evaluate(() => {
    const a = (globalThis as unknown as { __thalyxTest?: { getDocJson(): string } }).__thalyxTest;
    if (!a) throw new Error('hooks missing');
    return JSON.parse(a.getDocJson());
  });
}

/** The M4 login-flow demo graph, seeded surgically (gesture path is covered
 *  by grow-layout.spec). Patch source is PLAIN JS (new Function compiles it). */
const DEMO_PATCH = [
  "var style = { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' };",
  'function nd(id, label, shape, x, y, parent) {',
  "  d.nodes.push({ id: id, kind: 'shape', shape: shape, x: x, y: y, width: 160, height: 64, label: label, style: JSON.parse(JSON.stringify(style)), parentId: parent });",
  '}',
  'function ed(src, tgt, label) {',
  "  d.edges.push({ id: 'e_' + src + '_' + tgt, source: src, target: tgt, sourceAnchor: 'auto', targetAnchor: 'auto', kind: 'elbow', label: label, arrowStart: 'none', arrowEnd: 'arrow', style: { line: 'solid', stroke: 'ink', rounded: true } });",
  '}',
  "d.nodes.push({ id: 'auth', kind: 'container', x: 200, y: 150, width: 460, height: 340, label: 'Auth', style: JSON.parse(JSON.stringify(style)), meta: { mermaid: { id: 'Auth' } } });",
  "nd('start', 'Start', 'rect', 100, 80, undefined);",
  "nd('login', 'Login form', 'rounded', 300, 180, 'auth');",
  "nd('valid', 'Valid?', 'diamond', 300, 300, 'auth');",
  "nd('dash', 'Dashboard', 'rect', 600, 240, undefined);",
  "nd('err', 'Show error', 'rect', 480, 400, 'auth');",
  "nd('out', 'Log out', 'rect', 820, 240, undefined);",
  "ed('start', 'login'); ed('login', 'valid'); ed('valid', 'dash', 'yes');",
  "ed('valid', 'err', 'no'); ed('err', 'login'); ed('dash', 'out');",
].join('\n');

const ISLAND_PATCH = [
  "var style = { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' };",
  "d.nodes.push({ id: 'isl', kind: 'mermaid', x: 900, y: 80, width: 300, height: 200, label: '', mermaidSource: 'sequenceDiagram\\n  A->>B: x', style: style });",
].join('\n');

const ONLY_ISLAND_PATCH = [
  "d.nodes = [{ id: 'isl', kind: 'mermaid', x: 0, y: 0, width: 300, height: 200, label: '', mermaidSource: 'sequenceDiagram\\n  A->>B: hello', style: { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' } }];",
  'd.edges = [];',
].join('\n');

async function patchDoc(page: Page, src: string): Promise<void> {
  await page.evaluate((s) => {
    (
      globalThis as unknown as { __thalyxTest: { patchDoc(src: string): void } }
    ).__thalyxTest.patchDoc(s);
  }, src);
}

test.beforeEach(async ({ page }) => {
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('panel opens with Mod+Shift+M and shows the live export', async ({ page }) => {
  await patchDoc(page, DEMO_PATCH);
  await page.keyboard.press('ControlOrMeta+Shift+m');
  const panel = page.locator('.thalyx-mermaid-panel');
  await expect(panel).toBeVisible();
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('flowchart TB');
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('subgraph Auth');
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('-->|', { timeout: 10_000 });
  await page.keyboard.press('ControlOrMeta+Shift+m');
  await expect(panel).toHaveCount(0);
});

test('byte-stable export: live view identical after id assignment (fixpoint)', async ({ page }) => {
  await patchDoc(page, DEMO_PATCH);
  await page.keyboard.press('ControlOrMeta+Shift+m');
  await expect(page.locator('.thalyx-mermaid-panel')).toBeVisible();
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('flowchart TB');
  const first = await page.locator('.thalyx-mermaid-text').innerText();
  // force a doc change → debounced re-export must be byte-identical (ids stable)
  await patchDoc(page, 'd.canvas.grid = true;');
  await page.waitForTimeout(600);
  const second = await page.locator('.thalyx-mermaid-text').innerText();
  expect(second).toBe(first);
});

test('Copy as Mermaid: Mod+Shift+C writes the export to the clipboard', async ({ page }) => {
  await patchDoc(page, DEMO_PATCH);
  await page.keyboard.press('ControlOrMeta+Shift+m');
  await expect(page.locator('.thalyx-mermaid-panel')).toBeVisible();
  const displayed = await page.locator('.thalyx-mermaid-text').innerText();
  await page.keyboard.press('ControlOrMeta+Shift+m'); // close (live text unselected)
  await page.keyboard.press('ControlOrMeta+Shift+c');
  const clip = await page.evaluate(() => navigator.clipboard.readText());
  expect(clip).toBe(displayed);
});

test('direction dropdown switches the header (action, one undo)', async ({ page }) => {
  await page.keyboard.press('ControlOrMeta+Shift+m');
  await expect(page.locator('.thalyx-mermaid-panel')).toBeVisible();
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('flowchart TB');
  await page.locator('.thalyx-mermaid-panel select').selectOption('LR');
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('flowchart LR');
  await page.keyboard.press('ControlOrMeta+z');
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('flowchart TB');
});

test('island notice counts excluded islands', async ({ page }) => {
  await patchDoc(page, ISLAND_PATCH);
  await page.keyboard.press('ControlOrMeta+Shift+m');
  await expect(page.locator('.thalyx-mermaid-notice')).toHaveText('1 mermaid island not included');
});

test('single-island doc shows the island source itself', async ({ page }) => {
  await patchDoc(page, ONLY_ISLAND_PATCH);
  await page.keyboard.press('ControlOrMeta+Shift+m');
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('sequenceDiagram');
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('hello');
});

test('M4 demo graph round-trips: export re-imports semantically identical', async ({ page }) => {
  await patchDoc(page, DEMO_PATCH);
  await page.keyboard.press('ControlOrMeta+Shift+m');
  await expect(page.locator('.thalyx-mermaid-panel')).toBeVisible();
  await expect(page.locator('.thalyx-mermaid-text')).toContainText('flowchart TB');
  const exported = await page.locator('.thalyx-mermaid-text').innerText();

  const before = await docState(page);
  expect(before.nodes).toHaveLength(7);
  expect(before.edges).toHaveLength(6);

  // re-import the exported text via the paste path
  await page.keyboard.press('ControlOrMeta+Shift+m'); // close the panel
  await page.evaluate((src) => {
    const dt = new DataTransfer();
    dt.setData('text/plain', src);
    window.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }),
    );
  }, exported);
  await page.waitForTimeout(800);
  const after = await docState(page);
  expect(after.nodes).toHaveLength(7);
  expect(after.edges).toHaveLength(6);
  const labels = after.nodes.map((n) => n.label).sort();
  expect(labels).toEqual(
    ['Auth', 'Dashboard', 'Log out', 'Login form', 'Show error', 'Start', 'Valid?'].sort(),
  );
  // containment round-trips: Login form inside Auth
  const container = after.nodes.find((n) => n.kind === 'container');
  const login = after.nodes.find((n) => n.label === 'Login form');
  expect(login?.parentId).toBe(container?.id);
});
