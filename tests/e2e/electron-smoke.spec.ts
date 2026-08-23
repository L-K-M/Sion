import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { expect, test, type ElectronApplication, type Page } from '@playwright/test';
import { _electron } from 'playwright';

const repoRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '../..');
const mainEntry = resolve(repoRoot, 'out/main/index.js');

async function launchApp(): Promise<ElectronApplication> {
  if (!existsSync(mainEntry)) {
    throw new Error(`Build output missing: ${mainEntry} — run \`npm run build\` first.`);
  }
  return _electron.launch({
    args: [mainEntry],
    env: { ...process.env, THALYX_E2E: '1' },
  });
}

test.describe.configure({ mode: 'serial' });

let app: ElectronApplication | undefined;
let page: Page | undefined;

test.beforeAll(async () => {
  app = await launchApp();
  page = await app.firstWindow();
  await page.waitForLoadState('domcontentloaded');
});

test.afterAll(async () => {
  await app?.close();
});

test('launches and shows the Thalyx window', async () => {
  const p = page;
  if (!p) throw new Error('app did not launch');
  const title = await p.title();
  expect(title).toBe('Thalyx');
  await expect(p.getByRole('heading', { level: 1, name: 'Thalyx' })).toBeVisible();
});

test('renderer is sandboxed: no node globals leaked', async () => {
  const p = page;
  if (!p) throw new Error('app did not launch');
  const leaked = await p.evaluate(
    () =>
      typeof (globalThis as Record<string, unknown>)['require'] !== 'undefined' ||
      typeof (globalThis as Record<string, unknown>)['process'] !== 'undefined',
  );
  expect(leaked).toBe(false);
});

test('packaged renderer index.html carries the strict production CSP (§14.1)', () => {
  const html = readFileSync(resolve(repoRoot, 'out/renderer/index.html'), 'utf8');
  // Attribute-order-independent: find the CSP meta tag, then its content value.
  const tag = html.match(/<meta\b[^>]*Content-Security-Policy[^>]*>/i)?.[0];
  expect(tag, 'CSP meta tag present').toBeDefined();
  const content = tag?.match(/\bcontent\s*=\s*"([^"]*)"/i)?.[1];
  // Note: the expected policy is a deliberate golden string (PLAN.md §14.1
  // specifies the exact production policy) rather than an import of
  // CSP_BY_MODE — the test should fail if the shipped policy drifts from the
  // plan, not merely mirror whatever the config exports.
  const expected =
    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
    "img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'";
  expect(content).toBe(expected);
});
