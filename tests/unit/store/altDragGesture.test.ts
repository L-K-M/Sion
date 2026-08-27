import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('Alt-drag duplication gesture', () => {
  it('preserves originals and routes in one undo entry', () => {
    const source = A.addNode({ x: 10, y: 20 });
    const target = A.addNode({ x: 300, y: 20 });
    const edge = A.connectEdge(source, target, 'arrow');
    A.setEdgeWaypoints(edge, [{ x: 160, y: 80 }]);
    A.setSelection([source, target], [edge]);
    const documentBefore = JSON.stringify(getStore().doc);
    const historyBefore = getStore().history.past.length;

    A.beginGesture();
    A.moveNodesTransient([
      { id: source, x: 210, y: 120 },
      { id: target, x: 500, y: 120 },
    ]);
    A.finishAltDragDuplicate([source, target]);

    expect(getStore().history.past).toHaveLength(historyBefore + 1);
    expect(getStore().doc.nodes.find((node) => node.id === source)).toMatchObject({
      x: 10,
      y: 20,
    });
    expect(getStore().doc.edges.find((candidate) => candidate.id === edge)?.waypoints).toEqual([
      { x: 160, y: 80 },
    ]);

    const copy = getStore().doc.edges.find((candidate) => candidate.id !== edge);
    expect(copy?.waypoints).toEqual([{ x: 360, y: 180 }]);

    A.undo();
    expect(JSON.stringify(getStore().doc)).toBe(documentBefore);
  });

  it('reparents only the dropped copy into a frame', () => {
    const source = A.addNode({ x: 0, y: 0, width: 80, height: 40 });
    const frame = A.addNode({ kind: 'container', x: 300, y: 200, width: 300, height: 200 });

    A.beginGesture();
    A.moveNodesTransient([{ id: source, x: 340, y: 240 }]);
    const [copyId] = A.finishAltDragDuplicate([source]);

    expect(getStore().doc.nodes.find((node) => node.id === source)?.parentId).toBeUndefined();
    expect(getStore().doc.nodes.find((node) => node.id === copyId)).toMatchObject({
      parentId: frame,
      x: 40,
      y: 40,
    });
  });
});
