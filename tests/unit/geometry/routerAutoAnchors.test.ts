import { describe, expect, it } from 'vitest';
import { edgeEndpoints } from '../../../src/shared/geometry/anchors';
import { route } from '../../../src/shared/geometry/elbow';
import { newNode } from '../../../src/shared/model/create';

describe('auto-anchor elbow routing', () => {
  it('keeps every segment orthogonal when floating endpoints are off-center', () => {
    const sourceNode = newNode({ x: 0, y: 0, width: 100, height: 60 });
    const targetNode = newNode({ x: 400, y: 220, width: 120, height: 80 });
    const endpoints = edgeEndpoints(
      sourceNode,
      { x: sourceNode.x, y: sourceNode.y },
      targetNode,
      { x: targetNode.x, y: targetNode.y },
      'auto',
      'n',
    );
    const points = route(
      endpoints.source,
      endpoints.target,
      { x: 0, y: 0, width: 100, height: 60 },
      { x: 400, y: 220, width: 120, height: 80 },
      endpoints.sourceSide,
      endpoints.targetSide,
    );

    for (let index = 1; index < points.length; index += 1) {
      const start = points[index - 1]!;
      const end = points[index]!;
      expect(start.x === end.x || start.y === end.y).toBe(true);
    }
  });
});
