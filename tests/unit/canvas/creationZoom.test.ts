import { describe, expect, it } from 'vitest';
import { createPlacement, placementGesture } from '../../../src/renderer/canvas/creationGesture';

describe('zoom-independent creation intent', () => {
  it('treats sub-threshold screen jitter as a click at minimum zoom', () => {
    const gesture = placementGesture({ x: 100, y: 100 }, { x: 101, y: 100 });
    const placement = createPlacement('shape', { x: 0, y: 0 }, { x: 10, y: 0 }, gesture);

    expect(placement).toMatchObject({ x: -80, y: -32, width: 160, height: 64 });
  });

  it('treats a visible screen drag as a drag at maximum zoom', () => {
    const gesture = placementGesture({ x: 100, y: 100 }, { x: 108, y: 100 });
    const placement = createPlacement('shape', { x: 0, y: 0 }, { x: 2, y: 0 }, gesture);

    expect(placement).toMatchObject({ x: 0, y: 0, width: 16, height: 16 });
  });
});
