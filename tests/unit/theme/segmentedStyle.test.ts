import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

describe('segmented control styles', () => {
  it('styles the pressed state emitted by segmented buttons', () => {
    const css = readFileSync('src/renderer/styles.css', 'utf8');

    expect(css).toContain(".thalyx-seg[aria-pressed='true']");
  });
});
