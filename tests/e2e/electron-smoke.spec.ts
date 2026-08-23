import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test, type ElectronApplication, type Page } from '@playwright/test';
import { _electron } from 'playwright';

const repoRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '../..');

async function launchApp(): Promise<ElectronApplication> {
  return _electron.launch({
    args: [resolve(repoRoot, 'out/main/index.js')],
    env: { ...process.env, THALYX_E2E: '1' },
  });
}

let app: ElectronApplication | undefined;
let page: Page;

test.beforeAll(async () => {
  app = await launchApp();
  page = await app.firstWindow();
  await page.waitForLoadState('domcontentloaded');
});

// Note: the expected policy below is a deliberate golden string (PLAN.md §14.1
// specifies the exact production policy) rather than an import of
// CSP_BY_MODE — the test should fail if the shipped policy drifts from the
// plan, not merely mirror whatever the config exports.

test.afterAll(async () => {
  await app?.close();
});

test('launches and shows the Thalyx window', async () => {
  const title = await page.title();
  expect(title).toBe('Thalyx');
  await expect(page.getByRole('heading', { level: 1, name: 'Thalyx' })).toBeVisible();
});

test('renderer is sandboxed: no node globals leaked', async () => {
  const leaked = await page.evaluate(
    () =>
      typeof (globalThis as Record<string, unknown>)['require'] !== 'undefined' ||
      typeof (globalThis as Record<string, unknown>)['process'] !== 'undefined',
  );
  expect(leaked).toBe(false);
});

test('packaged renderer index.html carries the strict production CSP (§14.1)', async () => {
  const html = readFileSync(resolve(repoRoot, 'out/renderer/index.html'), 'utf8');
  const expected =
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
    "img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'";
  expect(html).toContain(`<meta http-equiv="Content-Security-Policy" content="${expected}">`);
});
