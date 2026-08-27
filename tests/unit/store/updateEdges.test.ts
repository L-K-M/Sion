import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('batch edge updates', () => {
  it('changes several edges in one undo entry', () => {
    const first = A.addNode({});
    const second = A.addNode({ x: 200 });
    const third = A.addNode({ x: 400 });
    const firstEdge = A.connectEdge(first, second, 'arrow');
    const secondEdge = A.connectEdge(second, third, 'arrow');
    const historyBefore = getStore().history.past.length;

    A.updateEdges([firstEdge, secondEdge], (edge) => ({
      style: { ...edge.style, line: 'dashed' },
    }));

    expect(getStore().history.past).toHaveLength(historyBefore + 1);
    expect(getStore().doc.edges.every((edge) => edge.style.line === 'dashed')).toBe(true);

    A.undo();
    expect(getStore().doc.edges.every((edge) => edge.style.line === 'solid')).toBe(true);
  });
});
