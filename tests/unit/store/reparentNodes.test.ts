import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { absolutePosition } from '../../../src/shared/model/queries';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('drag reparenting', () => {
  it('moves a child out of a frame without changing its absolute position', () => {
    const frame = A.addNode({ kind: 'container', x: 100, y: 100, width: 200, height: 160 });
    const child = A.addNode({ parentId: frame, x: 20, y: 20, width: 80, height: 40 });
    A.beginGesture();
    A.moveNodesTransient([{ id: child, x: 250, y: 20 }]);

    A.reparentNodesTransient([child]);
    A.endGesture();

    const node = getStore().doc.nodes.find((candidate) => candidate.id === child)!;
    expect(node.parentId).toBeUndefined();
    expect(absolutePosition(getStore().doc, node)).toEqual({ x: 350, y: 120 });

    A.undo();
    expect(getStore().doc.nodes.find((candidate) => candidate.id === child)?.parentId).toBe(frame);
  });

  it('moves a top-level object into the smallest containing frame', () => {
    const outer = A.addNode({ kind: 'container', x: 100, y: 100, width: 500, height: 400 });
    const inner = A.addNode({
      kind: 'container',
      parentId: outer,
      x: 50,
      y: 50,
      width: 250,
      height: 200,
    });
    const nodeId = A.addNode({ x: 180, y: 180, width: 80, height: 40 });

    A.beginGesture();
    A.reparentNodesTransient([nodeId]);
    A.endGesture();

    expect(getStore().doc.nodes.find((node) => node.id === nodeId)).toMatchObject({
      parentId: inner,
      x: 30,
      y: 30,
    });
  });
});
