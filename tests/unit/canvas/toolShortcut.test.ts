import { describe, expect, it } from 'vitest';
import { ToolShortcut, toolShortcut } from '../../../src/renderer/canvas/hooks/toolShortcut';

describe('tool shortcuts', () => {
  it('uses the typed letter instead of its physical QWERTY key', () => {
    expect(toolShortcut('r', 'KeyP')).toBe(ToolShortcut.Rectangle);
    expect(toolShortcut('z', 'KeyR')).toBeNull();
  });

  it('keeps physical digit aliases stable', () => {
    expect(toolShortcut('&', 'Digit2')).toBe(ToolShortcut.Rectangle);
  });
});
