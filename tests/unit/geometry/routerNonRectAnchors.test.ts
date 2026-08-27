import { describe, expect, it } from 'vitest';
import { edgeEndpoints } from '../../../src/shared/geometry/anchors';
import { route } from '../../../src/shared/geometry/elbow';
import { newNode } from '../../../src/shared/model/create';
import type { ShapeKind } from '../../../src/shared/model/types';

describe.each<ShapeKind>(['ellipse', 'diamond'])('%s auto-anchor routing', (shape) => {
  it('keeps floating endpoint routes orthogonal', () => {
    const source = newNode({ shape, x: 0, y: 0, width: 160, height: 64 });
    const target = newNode({ shape, x: 200, y: 150, width: 160, height: 64 });
    const endpoints = edgeEndpoints(
      source,
      { x: source.x, y: source.y },
      target,
      { x: target.x, y: target.y },
      'auto',
      'auto',
    );
    const points = route(
      endpoints.source,
      endpoints.target,
      { x: source.x, y: source.y, width: source.width, height: source.height },
      { x: target.x, y: target.y, width: target.width, height: target.height },
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
