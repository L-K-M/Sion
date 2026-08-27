import { expect, test } from '@playwright/test';
import { _electron } from 'playwright';
import { existsSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '../../..');

test('New Window opens an independent document window', async () => {
  const mainEntry = resolve(repoRoot, 'out/main/index.js');
  if (!existsSync(mainEntry)) throw new Error(`Build output missing: ${mainEntry}`);

  const scratch = mkdtempSync(join(tmpdir(), 'thalyx-multi-window-'));
  const app = await _electron.launch({
    args: [mainEntry, '--user-data-dir=' + join(scratch, 'userData')],
    env: { ...process.env, THALYX_E2E: '1' },
  });
  try {
    const first = await app.firstWindow();
    await first.goto(`${first.url().split('?')[0]}?testHooks=1`);

    const menuFound = await app.evaluate(({ Menu }) => {
      const file = Menu.getApplicationMenu()?.items.find((item) => item.label === 'File');
      const newWindow = file?.submenu?.items.find((item) => item.label === 'New Window');
      newWindow?.click();
      return Boolean(newWindow);
    });
    expect(menuFound).toBe(true);

    await expect.poll(async () => app.windows().length).toBe(2);
    const second = app.windows().find((window) => window !== first)!;
    await second.goto(`${second.url().split('?')[0]}?testHooks=1`);

    await first.evaluate(() => {
      (
        globalThis as unknown as { __thalyxTest: { patchDoc(source: string): void } }
      ).__thalyxTest.patchDoc(
        "d.nodes.push({ id: 'first', kind: 'shape', shape: 'rect', x: 1, y: 1, width: 160, height: 64, label: 'First', style: { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' } });",
      );
    });

    const firstDoc = await first.evaluate(() =>
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    );
    const secondDoc = await second.evaluate(() =>
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    );
    expect(firstDoc).toContain('First');
    expect(secondDoc).not.toContain('First');
  } finally {
    await app.close();
    rmSync(scratch, { recursive: true, force: true });
  }
});
