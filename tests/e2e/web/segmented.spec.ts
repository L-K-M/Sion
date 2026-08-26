import { expect, test } from '@playwright/test';

test('segmented controls visibly distinguish the selected option', async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto('/?testHooks=1');

  const grid = page.getByRole('group', { name: 'Grid' });
  const selected = grid.getByRole('button', { pressed: true });
  const unselected = grid.getByRole('button', { pressed: false });

  const selectedBackground = await selected.evaluate(
    (element) => getComputedStyle(element).backgroundColor,
  );
  const unselectedBackground = await unselected.evaluate(
    (element) => getComputedStyle(element).backgroundColor,
  );

  expect(selectedBackground).not.toBe(unselectedBackground);
});
