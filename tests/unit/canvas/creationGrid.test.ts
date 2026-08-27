import { describe, expect, it } from 'vitest';
import {
  createPlacement,
  PlacementGesture,
  snapPlacementToGrid,
} from '../../../src/renderer/canvas/creationGesture';

describe('grid-aware creation', () => {
  it('snaps a click-created object by its center', () => {
    const placement = createPlacement(
      'shape',
      { x: 503, y: 303 },
      { x: 503, y: 303 },
      PlacementGesture.Click,
    );

    expect(snapPlacementToGrid(placement, PlacementGesture.Click, 8)).toEqual({
      x: 424,
      y: 272,
      width: 160,
      height: 64,
    });
  });

  it('snaps every drag-created boundary', () => {
    const placement = createPlacement(
      'shape',
      { x: 3, y: 5 },
      { x: 101, y: 70 },
      PlacementGesture.Drag,
    );
    const snapped = snapPlacementToGrid(placement, PlacementGesture.Drag, 8);

    expect([snapped.x, snapped.y, snapped.x + snapped.width, snapped.y + snapped.height]).toEqual([
      0, 8, 104, 72,
    ]);
  });
});
