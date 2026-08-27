import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('edge label drag history', () => {
  it('coalesces every pointer frame into one undo entry', () => {
    const source = A.addNode({});
    const target = A.addNode({ x: 300 });
    const edge = A.connectEdge(source, target, 'arrow');
    A.updateEdge(edge, { label: 'Edge', labelT: 0.2 });
    const historyBefore = getStore().history.past.length;

    A.beginGesture();
    A.updateEdgeTransient(edge, { labelT: 0.4 });
    A.updateEdgeTransient(edge, { labelT: 0.6 });
    A.updateEdgeTransient(edge, { labelT: 0.8 });
    A.endGesture();

    expect(getStore().history.past).toHaveLength(historyBefore + 1);
    expect(getStore().doc.edges[0]?.labelT).toBe(0.8);
    A.undo();
    expect(getStore().doc.edges[0]?.labelT).toBe(0.2);
  });
});
