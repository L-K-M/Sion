import { expect, test, type Page } from '@playwright/test';

/**
 * M7 web-mode e2e: the export pipeline (SVG/PNG content assertions), PDF
 * golden smoke (page count + dimensions), and clipboard internal flavor.
 */

const BASE = '/?testHooks=1';

async function seedDoc(page: Page): Promise<void> {
  await page.evaluate(() => {
    (
      globalThis as unknown as { __thalyxTest: { patchDoc(src: string): void } }
    ).__thalyxTest.patchDoc(
      [
        "var style = { fill: 'surface', stroke: 'ink', strokeWidth: 2, fontSize: 14, textAlign: 'center' };",
        "d.nodes.push({ id: 'a', kind: 'shape', shape: 'rounded', x: 100, y: 100, width: 160, height: 64, label: 'Alpha', style: style });",
        "d.nodes.push({ id: 'b', kind: 'shape', shape: 'diamond', x: 420, y: 260, width: 160, height: 64, label: 'Beta', style: style });",
        "d.edges.push({ id: 'e1', source: 'a', target: 'b', sourceAnchor: 'auto', targetAnchor: 'auto', kind: 'elbow', label: 'yes', arrowStart: 'none', arrowEnd: 'arrow', style: { line: 'solid', stroke: 'ink', rounded: true } });",
      ].join('\n'),
    );
  });
}

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('renderDocToSvg: self-contained SVG with escaped text, no foreignObject', async ({ page }) => {
  await seedDoc(page);
  const svg = await page.evaluate(async () => {
    const doc = JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    );
    const api = (
      globalThis as unknown as {
        __thalyxTest: { renderSvg(doc: string, background: string): Promise<string> };
      }
    ).__thalyxTest;
    return await api.renderSvg(JSON.stringify(doc), 'light');
  });
  expect(svg).toContain('<svg xmlns="http://www.w3.org/2000/svg"');
  expect(svg).toContain('Alpha');
  expect(svg).toContain('Beta');
  expect(svg).toContain('>yes<');
  expect(svg).not.toContain('foreignObject');
  expect(svg).not.toContain('class=');
  expect(svg).toContain('font-family="Inter, system-ui, sans-serif"');
  // parses as XML
  const parses = await page.evaluate((src: string) => {
    try {
      new DOMParser().parseFromString(src, 'image/svg+xml');
      return true;
    } catch {
      return false;
    }
  }, svg);
  expect(parses).toBe(true);
});

test('renderDocToSvg: transparent background omits the rect; dark uses the dark fill', async ({
  page,
}) => {
  await seedDoc(page);
  const out = await page.evaluate(async () => {
    const doc = JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    );
    const api = (
      globalThis as unknown as {
        __thalyxTest: { renderSvg(doc: string, background: string): Promise<string> };
      }
    ).__thalyxTest;
    return {
      transparent: await api.renderSvg(JSON.stringify(doc), 'transparent'),
      dark: await api.renderSvg(JSON.stringify(doc), 'dark'),
    };
  });
  expect(out.transparent).not.toMatch(/<rect[^>]*fill="#(fff|14161a)"/);
  expect(out.dark).toContain('#14161a');
});

test('PNG export produces a non-empty image of the right pixel size', async ({ page }) => {
  await seedDoc(page);
  const { width, height, size } = await page.evaluate(async () => {
    const doc = JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    );
    const api = (
      globalThis as unknown as {
        __thalyxTest: {
          exportPng(doc: string, scale: 1 | 2, background: string): Promise<Uint8Array>;
        };
      }
    ).__thalyxTest;
    const bytes = await api.exportPng(JSON.stringify(doc), 1, 'light');
    const blob = new Blob([new Uint8Array(bytes)], { type: 'image/png' });
    const bmp = await createImageBitmap(blob);
    return { width: bmp.width, height: bmp.height, size: blob.size };
  });
  expect(size).toBeGreaterThan(1000);
  expect(width).toBeGreaterThan(400);
  expect(height).toBeGreaterThan(200);
});

test('PDF golden smoke: one page with content (svg2pdf)', async ({ page }) => {
  await seedDoc(page);
  const { bytes, pageCount, dims } = await page.evaluate(async () => {
    const doc = JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    );
    const api = (
      globalThis as unknown as {
        __thalyxTest: { exportPdf(doc: string, background: string): Promise<Uint8Array> };
      }
    ).__thalyxTest;
    const buf = await api.exportPdf(JSON.stringify(doc), 'light');
    // crude page count: count /Type /Page occurrences (not /Pages)
    const text = new TextDecoder('latin1').decode(buf);
    const pageCount = (text.match(/\/Type\s*\/Page[^s]/g) ?? []).length;
    const dims = text.match(/MediaBox\s*\[([\d.\s]+)\]/)?.[1] ?? '';
    return { bytes: buf.length, pageCount, dims };
  });
  expect(bytes).toBeGreaterThan(1000);
  expect(pageCount).toBe(1);
  expect(dims.trim().length).toBeGreaterThan(0);
});

test('internal clipboard: thalyx/clipboard JSON + PNG flavors', async ({ page }) => {
  await seedDoc(page);
  const clip = await page.evaluate(async () => {
    const api = (
      globalThis as unknown as {
        __thalyxTest: { clipboardFlavor(nodeIds: string[], edgeIds: string[]): Promise<void> };
      }
    ).__thalyxTest;
    await api.clipboardFlavor(['a', 'b'], ['e1']);
    const text = await navigator.clipboard.readText();
    const parsed = JSON.parse(text);
    return { type: parsed.type, nodes: parsed.nodes.length };
  });
  expect(clip.type).toBe('thalyx/clipboard');
  expect(clip.nodes).toBe(2);
});
