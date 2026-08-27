import { describe, expect, it } from 'vitest';
import { manualElbowWaypoints } from '../../../src/shared/geometry/manualWaypoints';

const pointRect = (point: { x: number; y: number }) => ({
  x: point.x,
  y: point.y,
  width: 0,
  height: 0,
});

describe('manual elbow waypoints', () => {
  it('keeps every segment axis-aligned from a horizontal source', () => {
    const source = { x: 10, y: 20 };
    const target = { x: 210, y: 120 };
    const waypoints = manualElbowWaypoints(
      source,
      target,
      'e',
      'w',
      pointRect(source),
      pointRect(target),
      { x: 90, y: 70 },
    );
    const points = [source, ...waypoints, target];

    for (let index = 1; index < points.length; index += 1) {
      const previous = points[index - 1]!;
      const current = points[index]!;
      expect(current.x === previous.x || current.y === previous.y).toBe(true);
    }
  });

  it('keeps every segment axis-aligned from a vertical source', () => {
    const source = { x: 10, y: 20 };
    const target = { x: 210, y: 120 };
    const waypoints = manualElbowWaypoints(
      source,
      target,
      's',
      'n',
      pointRect(source),
      pointRect(target),
      { x: 90, y: 70 },
    );
    const points = [source, ...waypoints, target];

    for (let index = 1; index < points.length; index += 1) {
      const previous = points[index - 1]!;
      const current = points[index]!;
      expect(current.x === previous.x || current.y === previous.y).toBe(true);
    }
  });

  it.each([
    ['n', 'n'],
    ['n', 'e'],
    ['n', 's'],
    ['n', 'w'],
    ['e', 'n'],
    ['e', 'e'],
    ['e', 's'],
    ['e', 'w'],
    ['s', 'n'],
    ['s', 'e'],
    ['s', 's'],
    ['s', 'w'],
    ['w', 'n'],
    ['w', 'e'],
    ['w', 's'],
    ['w', 'w'],
  ] as const)('leaves and approaches pinned sides for %s → %s', (sourceSide, targetSide) => {
    const source = { x: 20, y: 30 };
    const target = { x: 220, y: 130 };
    const waypoints = manualElbowWaypoints(
      source,
      target,
      sourceSide,
      targetSide,
      pointRect(source),
      pointRect(target),
      { x: 100, y: 90 },
    );
    const points = [source, ...waypoints, target];
    const first = points[1]!;
    const beforeTarget = points.at(-2)!;
    const outward = (side: 'n' | 'e' | 's' | 'w', point: { x: number; y: number }) =>
      side === 'n'
        ? point.y < 0
        : side === 's'
          ? point.y > 0
          : side === 'e'
            ? point.x > 0
            : point.x < 0;

    expect(outward(sourceSide, { x: first.x - source.x, y: first.y - source.y })).toBe(true);
    expect(
      outward(targetSide, { x: beforeTarget.x - target.x, y: beforeTarget.y - target.y }),
    ).toBe(true);
  });
});
