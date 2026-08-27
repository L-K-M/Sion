import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('no-op alignment', () => {
  it('preserves routes, history, and saved state', () => {
    const source = A.addNode({ x: 10, y: 20 });
    const target = A.addNode({ x: 10, y: 220 });
    const edge = A.connectEdge(source, target, 'arrow');
    A.setEdgeWaypoints(edge, [{ x: 220, y: 140 }]);
    A.setSelection([source, target], []);
    A.markSaved();
    const historyBefore = getStore().history.past.length;

    A.alignSelection('left');

    expect(getStore().doc.edges[0]?.waypoints).toEqual([{ x: 220, y: 140 }]);
    expect(getStore().history.past).toHaveLength(historyBefore);
    expect(getStore().session.dirtySinceSave).toBe(false);
  });
});
