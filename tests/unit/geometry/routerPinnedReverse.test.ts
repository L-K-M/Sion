import { describe, expect, it } from 'vitest';
import { route } from '../../../src/shared/geometry/elbow';
import type { Point, Rect } from '../../../src/shared/geometry/anchors';

function expectOrthogonal(points: Point[]): void {
  for (let index = 1; index < points.length; index++) {
    const before = points[index - 1]!;
    const after = points[index]!;
    expect(before.x === after.x || before.y === after.y).toBe(true);
  }
}

describe('reversed pinned elbow anchors', () => {
  it('leaves east and approaches west in their pinned directions', () => {
    const source: Rect = { x: 400, y: 100, width: 100, height: 60 };
    const target: Rect = { x: 0, y: 100, width: 100, height: 60 };
    const points = route({ x: 500, y: 130 }, { x: 0, y: 130 }, source, target, 'e', 'w');

    expect(points[1]!.x).toBeGreaterThan(points[0]!.x);
    expect(points.at(-2)!.x).toBeLessThan(points.at(-1)!.x);
    expectOrthogonal(points);
  });

  it('leaves south and approaches north in their pinned directions', () => {
    const source: Rect = { x: 100, y: 400, width: 100, height: 60 };
    const target: Rect = { x: 100, y: 0, width: 100, height: 60 };
    const points = route({ x: 150, y: 460 }, { x: 150, y: 0 }, source, target, 's', 'n');

    expect(points[1]!.y).toBeGreaterThan(points[0]!.y);
    expect(points.at(-2)!.y).toBeLessThan(points.at(-1)!.y);
    expectOrthogonal(points);
  });
});
