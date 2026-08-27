import { describe, expect, it } from 'vitest';
import { newDoc, newNode } from '../../../src/shared/model/create';
import { descendantIdsOf } from '../../../src/shared/model/queries';

describe('descendantIdsOf', () => {
  it('walks several subtrees once and deduplicates overlapping roots', () => {
    const doc = newDoc();
    doc.nodes = [
      newNode({ id: 'outer', kind: 'container' }),
      newNode({ id: 'inner', kind: 'container', parentId: 'outer' }),
      newNode({ id: 'leaf', parentId: 'inner' }),
      newNode({ id: 'other', kind: 'container' }),
      newNode({ id: 'other-leaf', parentId: 'other' }),
    ];

    expect(descendantIdsOf(doc, ['outer', 'inner', 'other'])).toEqual(
      new Set(['inner', 'leaf', 'other-leaf']),
    );
  });
});
