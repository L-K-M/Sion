import { describe, expect, it } from 'vitest';
import { restoreDocument } from '../../../src/shared/model/restore';

describe('self-connection restore', () => {
  it('drops self-loops from native documents', () => {
    const doc = restoreDocument({
      nodes: [{ id: 'A', kind: 'shape' }],
      edges: [{ id: 'loop', source: 'A', target: 'A' }],
    });

    expect(doc.edges).toEqual([]);
  });
});
