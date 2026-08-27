import { describe, expect, it } from 'vitest';
import { canEditEdge } from '../../../src/renderer/canvas/edges/edgeInteractionMode';

describe('edge interaction mode', () => {
  it('edits routes only with the Select tool', () => {
    expect(canEditEdge('select')).toBe(true);
    expect(canEditEdge('hand')).toBe(false);
    expect(canEditEdge('arrow')).toBe(false);
    expect(canEditEdge('line')).toBe(false);
    expect(canEditEdge('shape')).toBe(false);
  });
});
