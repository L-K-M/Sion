import { describe, expect, it } from 'vitest';
import { createPlacement, PlacementGesture } from '../../../src/renderer/canvas/creationGesture';

describe('container drag sizing', () => {
  it('keeps a short drag large enough to remain useful', () => {
    expect(
      createPlacement('container', { x: 0, y: 0 }, { x: 2, y: 2 }, PlacementGesture.Drag),
    ).toMatchObject({ width: 120, height: 80 });
  });
});
