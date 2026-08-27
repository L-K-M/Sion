import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('connector tool style', () => {
  it('keeps Arrow arrowheaded after using Line', () => {
    const first = A.addNode({ label: 'A' });
    const second = A.addNode({ label: 'B' });
    A.connectEdge(first, second, 'line');
    A.connectEdge(second, first, 'arrow');

    expect(getStore().doc.edges.map((edge) => edge.arrowEnd)).toEqual(['none', 'arrow']);
  });
});
