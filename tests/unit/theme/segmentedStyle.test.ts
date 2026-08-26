import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('segmented control styles', () => {
  it('styles the pressed state emitted by segmented buttons', () => {
    const css = readFileSync(new URL('../../../src/renderer/styles.css', import.meta.url), 'utf8');

    expect(css).toContain(".thalyx-seg[aria-pressed='true']");
    expect(css).not.toContain(".thalyx-seg[aria-checked='true']");
  });
});
