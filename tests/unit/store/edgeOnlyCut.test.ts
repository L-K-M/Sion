import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('edge-only cut', () => {
  it('removes a selected edge without deleting its nodes', async () => {
    const source = A.addNode({ label: 'A' });
    const target = A.addNode({ label: 'B' });
    const edge = A.addEdge({ source, target });

    const cut = await A.cutSelectionInternal([], [edge]);

    expect(cut).toBe(true);
    expect(getStore().doc.nodes).toHaveLength(2);
    expect(getStore().doc.edges).toHaveLength(0);
  });
});
