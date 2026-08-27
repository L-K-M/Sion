import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('manual waypoint invalidation', () => {
  it('clears a child edge on the first parent drag frame', () => {
    const frame = A.addNode({ kind: 'container' });
    const child = A.addNode({ parentId: frame, x: 20, y: 20 });
    const outside = A.addNode({ x: 500, y: 100 });
    const edge = A.connectEdge(child, outside, 'arrow');
    A.setEdgeWaypoints(edge, [{ x: 250, y: 50 }]);

    A.beginGesture();
    A.moveNodesTransient([{ id: frame, x: 100, y: 100 }]);

    expect(getStore().doc.edges[0]?.waypoints).toBeUndefined();
    A.endGesture();
  });

  it('clears endpoint waypoints when nudging', () => {
    const source = A.addNode({});
    const target = A.addNode({ x: 300 });
    const edge = A.connectEdge(source, target, 'arrow');
    A.setEdgeWaypoints(edge, [{ x: 150, y: 50 }]);
    A.setSelection([source]);

    A.nudgeSelection(1, 0);

    expect(getStore().doc.edges[0]?.waypoints).toBeUndefined();
  });
});
