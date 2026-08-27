import { describe, expect, it } from 'vitest';
import { route } from '../../../src/shared/geometry/elbow';
import type { Point, Rect, Side } from '../../../src/shared/geometry/anchors';

function segmentEntersRect(start: Point, end: Point, rect: Rect): boolean {
  if (start.y === end.y) {
    return (
      Math.max(Math.min(start.x, end.x), rect.x) <
        Math.min(Math.max(start.x, end.x), rect.x + rect.width) &&
      start.y > rect.y &&
      start.y < rect.y + rect.height
    );
  }

  return (
    Math.max(Math.min(start.y, end.y), rect.y) <
      Math.min(Math.max(start.y, end.y), rect.y + rect.height) &&
    start.x > rect.x &&
    start.x < rect.x + rect.width
  );
}

function expectClear(
  sourceRect: Rect,
  targetRect: Rect,
  source: Point,
  target: Point,
  sourceSide: Side,
  targetSide: Side,
): void {
  const points = route(source, target, sourceRect, targetRect, sourceSide, targetSide);
  for (let index = 1; index < points.length; index += 1) {
    expect(segmentEntersRect(points[index - 1]!, points[index]!, sourceRect)).toBe(false);
    expect(segmentEntersRect(points[index - 1]!, points[index]!, targetRect)).toBe(false);
  }
}

describe('elbow endpoint clearance', () => {
  it('routes same-facing magnets around both nodes', () => {
    expectClear(
      { x: 0, y: 0, width: 100, height: 100 },
      { x: 300, y: 0, width: 100, height: 100 },
      { x: 100, y: 50 },
      { x: 400, y: 50 },
      'e',
      'e',
    );
  });

  it('routes perpendicular magnets around overlapping corridors', () => {
    expectClear(
      { x: 0, y: 200, width: 100, height: 60 },
      { x: 100, y: 0, width: 100, height: 60 },
      { x: 100, y: 230 },
      { x: 150, y: 0 },
      'e',
      'n',
    );
  });
});
