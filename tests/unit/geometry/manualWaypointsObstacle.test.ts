import { describe, expect, it } from 'vitest';
import { manualElbowWaypoints } from '../../../src/shared/geometry/manualWaypoints';
import type { Point, Rect } from '../../../src/shared/geometry/anchors';

function segmentEntersRect(start: Point, end: Point, rect: Rect): boolean {
  if (start.y === end.y) {
    const overlapsX =
      Math.max(Math.min(start.x, end.x), rect.x) <
      Math.min(Math.max(start.x, end.x), rect.x + rect.width);
    return overlapsX && start.y > rect.y && start.y < rect.y + rect.height;
  }

  const overlapsY =
    Math.max(Math.min(start.y, end.y), rect.y) <
    Math.min(Math.max(start.y, end.y), rect.y + rect.height);
  return overlapsY && start.x > rect.x && start.x < rect.x + rect.width;
}

describe('manual elbow obstacle clearance', () => {
  it('does not route through either endpoint when both magnets face east', () => {
    const sourceRect = { x: 0, y: 0, width: 100, height: 100 };
    const targetRect = { x: 300, y: 0, width: 100, height: 100 };
    const source = { x: 100, y: 50 };
    const target = { x: 400, y: 50 };
    const points = [
      source,
      ...manualElbowWaypoints(source, target, 'e', 'e', sourceRect, targetRect, { x: 200, y: 50 }),
      target,
    ];

    for (let index = 1; index < points.length; index += 1) {
      expect(segmentEntersRect(points[index - 1]!, points[index]!, sourceRect)).toBe(false);
      expect(segmentEntersRect(points[index - 1]!, points[index]!, targetRect)).toBe(false);
    }
  });
});
