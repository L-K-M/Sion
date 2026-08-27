import { describe, expect, it } from 'vitest';
import type { NodeChange } from '@xyflow/react';
import { startsNodeGesture } from '../../../src/renderer/canvas/nodeChangeGesture';

describe('node change gesture detection', () => {
  it('starts before a left or top resize position delta is applied', () => {
    const changes: NodeChange[] = [
      { type: 'position', id: 'a', position: { x: 20, y: 30 } },
      {
        type: 'dimensions',
        id: 'a',
        dimensions: { width: 100, height: 50 },
        resizing: true,
      },
    ];

    expect(startsNodeGesture(changes)).toBe(true);
  });

  it('does not start for a completed position update', () => {
    const changes: NodeChange[] = [
      { type: 'position', id: 'a', position: { x: 20, y: 30 }, dragging: false },
    ];

    expect(startsNodeGesture(changes)).toBe(false);
  });
});
