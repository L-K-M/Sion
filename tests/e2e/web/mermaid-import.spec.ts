import { expect, test, type Page } from '@playwright/test';

/**
 * M5 e2e: paste mermaid → editable diagram (native flowchart, island for
 * sequence), paste-as-text-instead escape hatch, one-undo import, island
 * editor.
 */

const BASE = '/?testHooks=1';

async function docState(page: Page): Promise<{
  nodes: Array<{
    id: string;
    label: string;
    kind: string;
    shape?: string;
    mermaidSource?: string;
    x: number;
    y: number;
  }>;
  edges: Array<{ source: string; target: string; label?: string }>;
}> {
  return await page.evaluate(() => {
    const api = (globalThis as unknown as { __thalyxTest?: { getDocJson(): string } }).__thalyxTest;
    if (!api) throw new Error('__thalyxTest hooks missing');
    return JSON.parse(api.getDocJson());
  });
}

test.beforeEach(async ({ page }) => {
  await page.emulateMedia({ colorScheme: 'light' });
  await page.goto(BASE);
  await expect(page.locator('.react-flow')).toBeVisible();
});

test('paste a flowchart imports a laid-out editable diagram (one undo)', async ({ page }) => {
  const mermaidText = 'flowchart TB\n  A[Alpha] --> B[Beta]\n  B --> C{Gamma?}';
  await page.evaluate((text) => {
    const dt = new DataTransfer();
    dt.setData('text/plain', text);
    window.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }),
    );
  }, mermaidText);

  await expect(page.locator('.react-flow__node')).toHaveCount(3);
  const state = await docState(page);
  expect(state.edges).toHaveLength(2);
  expect(state.nodes.map((n) => n.label).sort()).toEqual(['Alpha', 'Beta', 'Gamma?']);
  // laid out top-down: ranks separated
  const ys = state.nodes.map((n) => n.y).sort((a, b) => a - b);
  expect(ys[2]! - ys[0]!).toBeGreaterThan(50);
  // diamond shape mapped
  expect(state.nodes.find((n) => n.label === 'Gamma?')?.shape).toBe('diamond');

  // toast shows with the escape hatch
  await expect(page.locator('.thalyx-toast')).toBeVisible();

  // ONE undo removes the whole import
  await page.keyboard.press('ControlOrMeta+z');
  const undone = await docState(page);
  expect(undone.nodes).toHaveLength(0);
  expect(undone.edges).toHaveLength(0);
});

test('paste a sequence diagram creates an island', async ({ page }) => {
  const seq = 'sequenceDiagram\n  Alice->>Bob: Hi\n  Bob-->>Alice: Hello';
  await page.evaluate((text) => {
    const dt = new DataTransfer();
    dt.setData('text/plain', text);
    window.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }),
    );
  }, seq);

  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const state = await docState(page);
  expect(state.nodes[0]!.kind).toBe('mermaid');
  expect(state.nodes[0]!.mermaidSource).toContain('Alice');
  // island renders
  await expect(page.locator('.thalyx-island-svg svg')).toBeVisible({ timeout: 10_000 });
});

test('paste garbage becomes a text node (not mermaid)', async ({ page }) => {
  await page.evaluate((text) => {
    const dt = new DataTransfer();
    dt.setData('text/plain', text);
    window.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }),
    );
  }, 'just some meeting notes');

  await expect(page.locator('.react-flow__node')).toHaveCount(1);
  const state = await docState(page);
  expect(state.nodes[0]!.kind).toBe('text');
  expect(state.nodes[0]!.label).toBe('just some meeting notes');
});

test('toast escape hatch: undo + paste as text', async ({ page }) => {
  const mermaidText = 'flowchart LR\n  X[One] --> Y[Two]';
  await page.evaluate((text) => {
    const dt = new DataTransfer();
    dt.setData('text/plain', text);
    window.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }),
    );
  }, mermaidText);
  await expect(page.locator('.react-flow__node')).toHaveCount(2);

  await page.locator('.thalyx-toast').getByText('Paste as text instead').click();
  const state = await docState(page);
  expect(state.nodes).toHaveLength(1);
  expect(state.nodes[0]!.kind).toBe('text');
  expect(state.nodes[0]!.label).toBe(mermaidText);
});

test('island double-click opens the editor; Apply updates the source', async ({ page }) => {
  const seq = 'sequenceDiagram\n  Alice->>Bob: Hi';
  await page.evaluate((text) => {
    const dt = new DataTransfer();
    dt.setData('text/plain', text);
    window.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }),
    );
  }, seq);
  await expect(page.locator('.react-flow__node')).toHaveCount(1);

  // select the island, then Enter opens the editor (native dblclick on nodes
  // is intercepted by d3-drag, like labels)
  await page.evaluate(() => {
    const id = JSON.parse(
      (
        globalThis as unknown as { __thalyxTest: { getDocJson(): string } }
      ).__thalyxTest.getDocJson(),
    ).nodes[0].id;
    (
      globalThis as unknown as { __thalyxTest: { selectNode(id: string): void } }
    ).__thalyxTest.selectNode(id);
  });
  await page.keyboard.press('Enter');
  await expect(page.locator('.thalyx-island-editor')).toBeVisible();
  const textarea = page.locator('.thalyx-island-editor textarea');
  await textarea.fill('sequenceDiagram\n  Bob->>Alice: Bye');

  await page.locator('.thalyx-island-editor').getByText('Apply').click();
  const state = await docState(page);
  expect(state.nodes[0]!.mermaidSource).toContain('Bye');
});

test('50-node flowchart imports natively and stays editable', async ({ page }) => {
  const lines = ['flowchart TB'];
  for (let i = 1; i < 50; i++) {
    lines.push(`  N${i}[Node ${i}] --> N${i + 1}[Node ${i + 1}]`);
  }
  const text = lines.join('\n');
  await page.evaluate((t) => {
    const dt = new DataTransfer();
    dt.setData('text/plain', t);
    window.dispatchEvent(
      new ClipboardEvent('paste', { clipboardData: dt, bubbles: true, cancelable: true }),
    );
  }, text);

  await expect(page.locator('.react-flow__node')).toHaveCount(50);
  const state = await docState(page);
  expect(state.edges).toHaveLength(49);
  expect(state.nodes.every((n) => n.kind === 'shape')).toBe(true);
});
