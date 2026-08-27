import { getBezierPath } from '@xyflow/react';
import { describe, expect, it } from 'vitest';
import {
  bezierCurve,
  bezierPointAtT,
  nearestBezierT,
} from '../../../src/renderer/canvas/edges/bezierGeometry';
import { sidePosition } from '../../../src/renderer/canvas/edges/sidePosition';

describe('curved edge label geometry', () => {
  it.each([
    ['n', 'e'],
    ['e', 'w'],
    ['s', 'n'],
    ['w', 's'],
  ] as const)('matches React Flow at the curve midpoint for %s → %s', (sourceSide, targetSide) => {
    const source = { x: 20, y: 30 };
    const target = { x: 260, y: 160 };
    const curve = bezierCurve(source, target, sourceSide, targetSide);
    const midpoint = bezierPointAtT(curve, 0.5);
    const [, labelX, labelY] = getBezierPath({
      sourceX: source.x,
      sourceY: source.y,
      sourcePosition: sidePosition(sourceSide),
      targetX: target.x,
      targetY: target.y,
      targetPosition: sidePosition(targetSide),
    });

    expect(midpoint.x).toBeCloseTo(labelX);
    expect(midpoint.y).toBeCloseTo(labelY);
  });

  it('projects label dragging onto the curve instead of its chord', () => {
    const curve = bezierCurve({ x: 20, y: 30 }, { x: 260, y: 160 }, 'e', 'n');
    const point = bezierPointAtT(curve, 0.8);

    expect(nearestBezierT(curve, point)).toBeCloseTo(0.8, 1);
  });
});
