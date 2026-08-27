import { describe, expect, it } from 'vitest';
import { edgePathPoints } from '../../../src/renderer/canvas/edges/edgePathPoints';

describe('edge path points', () => {
  it('ignores elbow waypoints after switching to straight or curved', () => {
    const source = { x: 10, y: 20 };
    const target = { x: 300, y: 200 };
    const waypoint = { x: 80, y: 90 };

    expect(edgePathPoints('straight', source, target, [waypoint], () => [])).toEqual([
      source,
      target,
    ]);
    expect(edgePathPoints('curved', source, target, [waypoint], () => [])).toEqual([
      source,
      target,
    ]);
  });

  it('keeps manual points for elbow connectors', () => {
    const source = { x: 10, y: 20 };
    const target = { x: 300, y: 200 };
    const waypoint = { x: 80, y: 90 };

    expect(edgePathPoints('elbow', source, target, [waypoint], () => [])).toEqual([
      source,
      waypoint,
      target,
    ]);
  });
});
