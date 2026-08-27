import { Position } from '@xyflow/react';
import { describe, expect, it } from 'vitest';
import { sidePosition } from '../../../src/renderer/canvas/edges/sidePosition';

describe('Bezier endpoint directions', () => {
  it('maps model sides to matching React Flow tangents', () => {
    expect(sidePosition('n')).toBe(Position.Top);
    expect(sidePosition('s')).toBe(Position.Bottom);
    expect(sidePosition('e')).toBe(Position.Right);
    expect(sidePosition('w')).toBe(Position.Left);
  });
});
