import { expect, test, type ElectronApplication, type Page } from '@playwright/test';
import { _electron } from 'playwright';
import { existsSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '../../..');
const mainEntry = resolve(repoRoot, 'out/main/index.js');

test.describe.configure({ mode: 'serial' });

async function launch(scratch: string, paths: string[] = []): Promise<ElectronApplication> {
  if (!existsSync(mainEntry)) throw new Error(`Build output missing: ${mainEntry}`);

  return _electron.launch({
    args: [mainEntry, '--user-data-dir=' + join(scratch, 'userData'), ...paths],
    env: { ...process.env, THALYX_E2E: '1' },
  });
}

async function enableHooks(page: Page): Promise<void> {
  await page.goto(`${page.url().split('?')[0]}?testHooks=1`);
  await expect(page.locator('.react-flow')).toBeVisible();
}

test('window-scoped titles, bootstrap, and recovery remain independent', async () => {
  const scratch = mkdtempSync(join(tmpdir(), 'thalyx-window-lifecycle-'));
  const app = await launch(scratch);
  try {
    const first = await app.firstWindow();
    await enableHooks(first);
    await app.evaluate(({ Menu }) => {
      const file = Menu.getApplicationMenu()?.items.find((item) => item.label === 'File');
      file?.submenu?.items.find((item) => item.label === 'New Window')?.click();
    });
    await expect.poll(async () => app.windows().length).toBe(2);
    const second = app.windows().find((window) => window !== first)!;
    await enableHooks(second);

    const stableBootstrap = await first.evaluate(async () => {
      const api = (
        globalThis as unknown as {
          thalyx: { appx: { bootstrap(): Promise<unknown> } };
        }
      ).thalyx;
      return (
        JSON.stringify(await api.appx.bootstrap()) === JSON.stringify(await api.appx.bootstrap())
      );
    });
    expect(stableBootstrap).toBe(true);

    await first.evaluate(() => {
      (
        globalThis as unknown as { __thalyxTest: { patchDoc(source: string): void } }
      ).__thalyxTest.patchDoc(
        "d.nodes.push({ id: 'one', kind: 'shape', shape: 'rect', x: 1, y: 1, width: 160, height: 64, label: 'ONE', style: { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' } });",
      );
    });
    await second.evaluate(() => {
      (
        globalThis as unknown as { __thalyxTest: { patchDoc(source: string): void } }
      ).__thalyxTest.patchDoc(
        "d.nodes.push({ id: 'two', kind: 'shape', shape: 'rect', x: 1, y: 1, width: 160, height: 64, label: 'TWO', style: { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' } });",
      );
    });
    await first.waitForTimeout(1_200);

    const recovered = await first.evaluate(async () => {
      const recovery = (
        globalThis as unknown as {
          thalyx: {
            recovery: {
              list(): Promise<Array<{ docId: string; originalPath: string | null }>>;
              read(docId: string): Promise<string>;
            };
          };
        }
      ).thalyx.recovery;
      const entries = (await recovery.list()).filter((entry) => entry.originalPath === null);
      return Promise.all(entries.map((entry) => recovery.read(entry.docId)));
    });
    expect(recovered).toHaveLength(2);
    expect(recovered.join('\n')).toContain('ONE');
    expect(recovered.join('\n')).toContain('TWO');

    await first.evaluate(() =>
      (
        globalThis as unknown as { thalyx: { appx: { setTitle(title: string): Promise<void> } } }
      ).thalyx.appx.setTitle('ONE'),
    );
    await second.evaluate(() =>
      (
        globalThis as unknown as { thalyx: { appx: { setTitle(title: string): Promise<void> } } }
      ).thalyx.appx.setTitle('TWO'),
    );
    await expect
      .poll(() =>
        app.evaluate(({ BrowserWindow }) =>
          BrowserWindow.getAllWindows()
            .map((w) => w.getTitle())
            .sort(),
        ),
      )
      .toEqual(['ONE', 'TWO']);
  } finally {
    await app.close();
    rmSync(scratch, { recursive: true, force: true });
  }
});

test('two startup documents create two populated windows', async () => {
  const scratch = mkdtempSync(join(tmpdir(), 'thalyx-startup-windows-'));
  const firstPath = join(scratch, 'one.thalyx');
  const secondPath = join(scratch, 'two.thalyx');
  writeFileSync(firstPath, documentJson('ONE'));
  writeFileSync(secondPath, documentJson('TWO'));
  const app = await launch(scratch, [firstPath, secondPath]);
  try {
    await expect.poll(async () => app.windows().length).toBe(2);
    const pages = app.windows();
    for (const page of pages) await enableHooks(page);

    const labels = await Promise.all(
      pages.map((page) =>
        page.evaluate(() =>
          JSON.parse(
            (
              globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
            ).__thalyxTest.getDocJson(),
          ).nodes.map((node: { label: string }) => node.label),
        ),
      ),
    );
    expect(labels.flat().sort()).toEqual(['ONE', 'TWO']);
  } finally {
    await app.close();
    rmSync(scratch, { recursive: true, force: true });
  }
});

function documentJson(label: string): string {
  return JSON.stringify({
    type: 'thalyx',
    version: 1,
    source: 'thalyx@0.1.0',
    nodes: [
      {
        id: label.toLowerCase(),
        kind: 'shape',
        shape: 'rect',
        x: 10,
        y: 10,
        width: 160,
        height: 64,
        label,
        style: {
          fill: 'surface',
          stroke: 'ink',
          strokeWidth: 2,
          fontSize: 14,
          textAlign: 'center',
        },
      },
    ],
    edges: [],
    canvas: { background: 'default', grid: false },
    meta: { mermaid: { direction: 'TB' } },
  });
}
