import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('reparent ordering', () => {
  it('moves a newly parented subtree after its frame', () => {
    const child = A.addNode({ x: 340, y: 240, width: 80, height: 40 });
    const frame = A.addNode({ kind: 'container', x: 300, y: 200, width: 300, height: 200 });

    A.beginGesture();
    A.reparentNodesTransient([child]);
    A.endGesture();

    const ids = getStore().doc.nodes.map((node) => node.id);
    expect(ids.indexOf(frame)).toBeLessThan(ids.indexOf(child));
    expect(getStore().doc.nodes.find((node) => node.id === child)?.parentId).toBe(frame);
  });
});
