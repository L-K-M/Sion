import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('no-op reparenting', () => {
  it('does not dirty an unchanged document', () => {
    const nodeId = A.addNode({ x: 40, y: 40 });
    A.markSaved();
    const before = getStore().doc;

    A.reparentNodesTransient([nodeId]);

    expect(getStore().doc).toBe(before);
    expect(getStore().session.dirtySinceSave).toBe(false);
  });
});
