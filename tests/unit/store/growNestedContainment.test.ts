import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { absolutePosition } from '../../../src/shared/model/queries';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('nested quick-grow containment', () => {
  it('falls back to the deepest containing ancestor frame', () => {
    const outer = A.addNode({ kind: 'container', x: 0, y: 0, width: 800, height: 500 });
    const inner = A.addNode({
      kind: 'container',
      parentId: outer,
      x: 100,
      y: 80,
      width: 300,
      height: 250,
    });
    const source = A.addNode({
      parentId: inner,
      x: 150,
      y: 50,
      width: 100,
      height: 64,
    });

    const grownId = A.growConnectedNode(source, 'e');
    const grown = getStore().doc.nodes.find((node) => node.id === grownId)!;

    expect(grown.parentId).toBe(outer);
    expect(absolutePosition(getStore().doc, grown)).toEqual({ x: 398, y: 130 });
  });
});
