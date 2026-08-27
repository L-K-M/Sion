import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('manual waypoint preservation', () => {
  it('keeps routes and history unchanged after a zero-distance drag', () => {
    const source = A.addNode({ x: 10, y: 20 });
    const target = A.addNode({ x: 300, y: 20 });
    const edge = A.connectEdge(source, target, 'arrow');
    A.setEdgeWaypoints(edge, [{ x: 160, y: 80 }]);
    A.markSaved();
    const historyBefore = getStore().history.past.length;

    A.beginGesture();
    A.moveNodesTransient([{ id: source, x: 10, y: 20 }]);
    A.endGesture();

    expect(getStore().doc.edges[0]?.waypoints).toEqual([{ x: 160, y: 80 }]);
    expect(getStore().history.past).toHaveLength(historyBefore);
    expect(getStore().session.dirtySinceSave).toBe(false);
  });

  it('keeps child routes when only the parent frame is resized', () => {
    const frame = A.addNode({ kind: 'container', width: 400, height: 300 });
    const child = A.addNode({ parentId: frame, x: 20, y: 40 });
    const target = A.addNode({ x: 600, y: 100 });
    const edge = A.connectEdge(child, target, 'arrow');
    A.setEdgeWaypoints(edge, [{ x: 300, y: 100 }]);

    A.beginGesture();
    A.resizeNodeTransient(frame, { width: 500, height: 300 });
    A.endGesture();

    expect(getStore().doc.edges[0]?.waypoints).toEqual([{ x: 300, y: 100 }]);
  });

  it('translates absolute routes when duplicating a connected selection', () => {
    const source = A.addNode({ x: 10, y: 20 });
    const target = A.addNode({ x: 300, y: 20 });
    const edge = A.connectEdge(source, target, 'arrow');
    A.setEdgeWaypoints(edge, [{ x: 160, y: 80 }]);
    A.setSelection([source, target], [edge]);

    A.duplicateSelection();

    const copy = getStore().doc.edges.find((candidate) => candidate.id !== edge);
    expect(copy?.waypoints).toEqual([{ x: 176, y: 96 }]);
  });
});
