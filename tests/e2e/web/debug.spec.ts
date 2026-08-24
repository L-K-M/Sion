import { expect, test } from '@playwright/test';

// TEMPORARY diagnostics (removed once the failing tests are understood).
test('diagnose dblclick + placement', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto('/?testHooks=1');
  await expect(page.locator('.react-flow')).toBeVisible();
  await page.getByTitle('Rounded rectangle').click();
  await page.mouse.click(500, 300);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);

  const info = await page.evaluate(() => {
    const node = document.querySelector('.react-flow__node') as HTMLElement | null;
    const r = node?.getBoundingClientRect();
    return {
      storeDoc: JSON.parse(
        (
          globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
        ).__thalyxTest.getDocJson(),
      ),
      viewportTransform: (document.querySelector('.react-flow__viewport') as HTMLElement | null)
        ?.style.transform,
      nodeRect: r ? { x: r.x, y: r.y, w: r.width, h: r.height } : null,
      nodeDataId: node?.getAttribute('data-id') ?? null,
      editing: (
        globalThis as unknown as { __thalyxTest: { getEditing(): string } }
      ).__thalyxTest.getEditing(),
    };
  });
  console.log('[diag] after place:', JSON.stringify(info, null, 1).slice(0, 900));

  // synthetic dblclick directly on the node element
  const synthetic = await page.evaluate(() => {
    const node = document.querySelector('.react-flow__node') as HTMLElement;
    node.dispatchEvent(new MouseEvent('dblclick', { bubbles: true, cancelable: true }));
    return (
      globalThis as unknown as { __thalyxTest: { getEditing(): string } }
    ).__thalyxTest.getEditing();
  });
  console.log('[diag] after synthetic dblclick, editing =', synthetic);

  await page.evaluate(() => {
    (
      globalThis as unknown as { __thalyxTest: { loadDoc(s: string): boolean } }
    ).__thalyxTest.loadDoc(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    );
  });
  const real = await page.mouse
    .dblclick(500, 300)
    .then(() =>
      page.evaluate(() =>
        (
          globalThis as unknown as { __thalyxTest: { getEditing(): string } }
        ).__thalyxTest.getEditing(),
      ),
    )
    .catch((e) => `mouse.dblclick failed: ${String(e)}`);
  console.log('[diag] after real dblclick, editing =', real);
  expect(true).toBe(true);
});
