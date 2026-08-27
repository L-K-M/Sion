import { describe, expect, it } from 'vitest';
import {
  DEFAULT_CONTAINER_HEIGHT,
  createPlacement,
  PlacementGesture,
} from '../../../src/renderer/canvas/creationGesture';

describe('createPlacement', () => {
  it('centers a default-sized shape on a click', () => {
    expect(
      createPlacement('shape', { x: 500, y: 300 }, { x: 500, y: 300 }, PlacementGesture.Click),
    ).toEqual({
      x: 420,
      y: 268,
      width: 160,
      height: 64,
    });
  });

  it('normalizes drag direction and preserves the drawn size', () => {
    expect(
      createPlacement('shape', { x: 500, y: 300 }, { x: 300, y: 180 }, PlacementGesture.Drag),
    ).toEqual({
      x: 300,
      y: 180,
      width: 200,
      height: 120,
    });
  });

  it('gives click-created containers useful height', () => {
    const placement = createPlacement(
      'container',
      { x: 500, y: 300 },
      { x: 500, y: 300 },
      PlacementGesture.Click,
    );

    expect(placement.height).toBe(DEFAULT_CONTAINER_HEIGHT);
    expect(placement.height).toBeGreaterThanOrEqual(180);
  });
});
