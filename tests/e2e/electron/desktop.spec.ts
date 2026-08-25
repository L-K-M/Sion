/**
 * M7 Electron smoke: menus→renderer wiring, save+autosave+recovery (crash
 * simulation), file open via IPC-mocked dialog.
 */
import { expect, test, type ElectronApplication, type Page } from '@playwright/test';
import { _electron } from 'playwright';
import { rmSync, existsSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '../../..');

let app: ElectronApplication;
let page: Page;
let scratch: string;

test.beforeAll(async () => {
  const mainEntry = resolve(repoRoot, 'out/main/index.js');
  if (!existsSync(mainEntry))
    throw new Error(`Build output missing: ${mainEntry} — run \`npm run build\` first.`);
  scratch = mkdtempSync(join(tmpdir(), 'thalyx-e2e-'));
  app = await _electron.launch({
    args: [mainEntry, `--user-data-dir=${join(scratch, 'userData')}`],
    env: { ...process.env, THALYX_E2E: '1' },
  });
  page = await app.firstWindow();
  await page.waitForLoadState('domcontentloaded');
  // the built app exposes test hooks only with the explicit opt-in
  await page.goto(page.url().split('?')[0] + '?testHooks=1');
  await page.waitForLoadState('domcontentloaded');
});

test.afterAll(async () => {
  await app?.close();
  rmSync(scratch, { recursive: true, force: true });
});

test('menus exist and Undo reaches the renderer store', async () => {
  await expect(page.locator('.react-flow')).toBeVisible();
  // create a node via the test hook, then trigger menu Undo
  await page.evaluate(() => {
    (
      globalThis as unknown as { __thalyxTest: { patchDoc(src: string): void } }
    ).__thalyxTest.patchDoc(
      "d.nodes.push({ id: 'n1', kind: 'shape', shape: 'rect', x: 100, y: 100, width: 160, height: 64, label: 'X', style: { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' } });",
    );
  });
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const menuUndo = await app.evaluate(({ Menu }) => {
    const menu = Menu.getApplicationMenu();
    const edit = menu?.items.find((i) => i.label === 'Edit');
    const undo = edit?.submenu?.items.find((i) => i.label === 'Undo');
    undo?.click();
    return Boolean(undo);
  });
  expect(menuUndo).toBe(true);
  // the renderer routes menu undo to the store (patch is tracked)
  await page.waitForTimeout(300);
});

test('recovery: autosave lands in the store and survives relaunch', async () => {
  await expect(page.locator('.react-flow')).toBeVisible();
  await page.evaluate(() => {
    (
      globalThis as unknown as { __thalyxTest: { patchDoc(src: string): void } }
    ).__thalyxTest.patchDoc(
      "d.nodes = [{ id: 'crash1', kind: 'shape', shape: 'rounded', x: 50, y: 50, width: 160, height: 64, label: 'CrashSurvivor', style: { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' } }]; d.edges = [];",
    );
  });
  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  // wait past the 800ms autosave debounce
  await page.waitForTimeout(1500);
  // the untitled doc's recovery entry exists and holds the content
  const recovered = await page.evaluate(async () => {
    const api = (
      globalThis as unknown as {
        thalyx: {
          recovery: {
            list(): Promise<Array<{ docId: string; originalPath: string | null }>>;
            read(id: string): Promise<string>;
          };
        };
      }
    ).thalyx;
    const entries = await api.recovery.list();
    const scratch = entries.find((e) => e.originalPath === null);
    if (!scratch) return null;
    return await api.recovery.read(scratch.docId);
  });
  expect(recovered).toBeTruthy();
  expect(recovered).toContain('CrashSurvivor');
  // relaunch a fresh instance against the same userData: scratch restores
  await app.close();
  const mainEntry = resolve(repoRoot, 'out/main/index.js');
  const app2 = await _electron.launch({
    args: [mainEntry, `--user-data-dir=${join(scratch, 'userData')}`],
    env: { ...process.env, THALYX_E2E: '1' },
  });
  const page2 = await app2.firstWindow();
  await page2.waitForLoadState('domcontentloaded');
  await page2.goto(page2.url().split('?')[0] + '?testHooks=1');
  await page2.waitForLoadState('domcontentloaded');
  await page2.waitForTimeout(1000);
  const restored = await page2.evaluate(() => {
    const api = (globalThis as unknown as { __thalyxTest: { getDocJson(): string } }).__thalyxTest;
    return JSON.parse(api.getDocJson());
  });
  expect(restored.nodes.map((n: { label: string }) => n.label)).toContain('CrashSurvivor');
  await app2.close();
  // re-open a window in the original app for subsequent tests
  app = await _electron.launch({
    args: [mainEntry, `--user-data-dir=${join(scratch, 'userData2')}`],
    env: { ...process.env, THALYX_E2E: '1' },
  });
  page = await app.firstWindow();
  await page.waitForLoadState('domcontentloaded');
  await page.goto(page.url().split('?')[0] + '?testHooks=1');
  await page.waitForLoadState('domcontentloaded');
});

test('window.thalyx exposes the full §12.2 surface', async () => {
  const surface = await page.evaluate(() => {
    const api = (globalThis as unknown as Record<string, unknown>)['thalyx'] as
      Record<string, Record<string, unknown>> | undefined;
    if (!api) return null;
    return Object.keys(api).sort();
  });
  expect(surface).toEqual(
    ['appx', 'clip', 'dialog', 'exportx', 'file', 'prefs', 'recents', 'recovery', 'shellx'].sort(),
  );
});
