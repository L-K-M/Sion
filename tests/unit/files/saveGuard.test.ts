import { describe, expect, it } from 'vitest';
import { isCompletedSaveCurrent } from '../../../src/renderer/files/saveGuard';

describe('isCompletedSaveCurrent', () => {
  it('accepts the unchanged snapshot and target', () => {
    expect(isCompletedSaveCurrent('doc-a', '/a.thalyx', 'doc-a', '/a.thalyx')).toBe(true);
  });

  it('rejects a save completed after another edit', () => {
    expect(isCompletedSaveCurrent('doc-a', '/a.thalyx', 'doc-b', '/a.thalyx')).toBe(false);
  });

  it('rejects a save completed after the target changed', () => {
    expect(isCompletedSaveCurrent('doc-a', '/a.thalyx', 'doc-a', '/b.thalyx')).toBe(false);
  });
});
