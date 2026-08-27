import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { resetStore, getStore } from '../../../src/renderer/store/store';
import * as A from '../../../src/renderer/store/actions';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('connection creation invariants', () => {
  it('rejects self-connections at the model boundary', () => {
    const node = A.addNode({ label: 'A' });

    expect(() => A.addEdge({ source: node, target: node })).toThrow('self');
    expect(getStore().doc.edges).toHaveLength(0);
  });

  it('persists the exact handles used to create a connection', () => {
    const source = A.addNode({ label: 'A' });
    const target = A.addNode({ label: 'B' });

    Reflect.apply(A.connectEdge, null, [
      source,
      target,
      'arrow',
      { sourceAnchor: 'e', targetAnchor: 'n' },
    ]);

    expect(getStore().doc.edges[0]).toMatchObject({ sourceAnchor: 'e', targetAnchor: 'n' });
  });
});
