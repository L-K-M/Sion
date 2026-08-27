import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { absolutePosition } from '../../../src/shared/model/queries';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('quick-grow at frame boundaries', () => {
  it('detaches a grown node that would fall outside its source frame', () => {
    const frame = A.addNode({ kind: 'container', x: 100, y: 100, width: 320, height: 220 });
    const source = A.addNode({ parentId: frame, x: 140, y: 60, width: 160, height: 64 });

    const grownId = A.growConnectedNode(source, 'e');
    const grown = getStore().doc.nodes.find((node) => node.id === grownId)!;

    expect(grown.parentId).toBeUndefined();
    expect(absolutePosition(getStore().doc, grown)).toEqual({ x: 448, y: 160 });
  });
});
