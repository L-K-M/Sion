import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('container resize compensation', () => {
  it('preserves a child route when relative motion keeps its endpoint fixed', () => {
    const frame = A.addNode({ kind: 'container', x: 100, y: 100, width: 300, height: 200 });
    const child = A.addNode({ parentId: frame, x: 20, y: 30 });
    const outside = A.addNode({ x: 500, y: 130 });
    const edge = A.addEdge({ source: child, target: outside });
    A.setEdgeWaypoints(edge, [{ x: 350, y: 160 }]);

    A.moveNodesTransient([
      { id: frame, x: 90, y: 100 },
      { id: child, x: 30, y: 30 },
    ]);

    expect(getStore().doc.edges.find((candidate) => candidate.id === edge)?.waypoints).toEqual([
      { x: 350, y: 160 },
    ]);
  });
});
