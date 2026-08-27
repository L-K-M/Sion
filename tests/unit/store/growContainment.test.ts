import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('quick-grow source rules', () => {
  it('keeps a grown child inside its source container', () => {
    const frame = A.addNode({ kind: 'container', x: 100, y: 100, width: 600, height: 300 });
    const source = A.addNode({ x: 40, y: 60, width: 160, height: 64, parentId: frame });

    const grownId = A.growConnectedNode(source, 'e');
    const grown = getStore().doc.nodes.find((node) => node.id === grownId);

    expect(grown).toMatchObject({ parentId: frame, x: 248, y: 60 });
  });

  it.each(['text', 'container'] as const)('does not grow shapes from a %s object', (kind) => {
    const source = A.addNode({ kind });

    expect(A.growConnectedNode(source, 'e')).toBeNull();
    expect(getStore().doc.nodes).toHaveLength(1);
  });
});
