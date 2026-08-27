import { describe, expect, it } from 'vitest';
import { route } from '../../../src/shared/geometry/elbow';
import type { Point, Rect, Side } from '../../../src/shared/geometry/anchors';

const sourceRect: Rect = { x: 300, y: 300, width: 100, height: 60 };
const targetRect: Rect = { x: 0, y: 0, width: 100, height: 60 };

function anchor(rect: Rect, side: Side): Point {
  if (side === 'n') return { x: rect.x + rect.width / 2, y: rect.y };
  if (side === 's') return { x: rect.x + rect.width / 2, y: rect.y + rect.height };
  if (side === 'e') return { x: rect.x + rect.width, y: rect.y + rect.height / 2 };
  return { x: rect.x, y: rect.y + rect.height / 2 };
}

function expectDirection(before: Point, after: Point, side: Side): void {
  if (side === 'n') expect(after.y).toBeLessThan(before.y);
  if (side === 's') expect(after.y).toBeGreaterThan(before.y);
  if (side === 'e') expect(after.x).toBeGreaterThan(before.x);
  if (side === 'w') expect(after.x).toBeLessThan(before.x);
}

function crossesInterior(a: Point, b: Point, rect: Rect): boolean {
  if (a.x === b.x) {
    const overlapsY = Math.max(a.y, b.y) > rect.y && Math.min(a.y, b.y) < rect.y + rect.height;
    return a.x > rect.x && a.x < rect.x + rect.width && overlapsY;
  }

  const overlapsX = Math.max(a.x, b.x) > rect.x && Math.min(a.x, b.x) < rect.x + rect.width;
  return a.y > rect.y && a.y < rect.y + rect.height && overlapsX;
}

describe('perpendicular pinned elbow anchors', () => {
  for (const [sourceSide, targetSide] of [
    ['e', 'n'],
    ['e', 's'],
    ['w', 'n'],
    ['w', 's'],
    ['n', 'e'],
    ['n', 'w'],
    ['s', 'e'],
    ['s', 'w'],
  ] as const) {
    it(`leaves ${sourceSide} and approaches ${targetSide} outside both nodes`, () => {
      const points = route(
        anchor(sourceRect, sourceSide),
        anchor(targetRect, targetSide),
        sourceRect,
        targetRect,
        sourceSide,
        targetSide,
      );

      expectDirection(points[0]!, points[1]!, sourceSide);
      expectDirection(points.at(-1)!, points.at(-2)!, targetSide);
      for (let index = 1; index < points.length; index += 1) {
        const before = points[index - 1]!;
        const after = points[index]!;
        expect(before.x === after.x || before.y === after.y).toBe(true);
        expect(crossesInterior(before, after, sourceRect)).toBe(false);
        expect(crossesInterior(before, after, targetRect)).toBe(false);
      }
    });
  }
});
