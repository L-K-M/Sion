import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { absolutePosition } from '../../../src/shared/model/queries';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

beforeEach(() => resetStore());
afterEach(() => resetStore());

describe('nested duplication coordinates', () => {
  it('offsets a copied frame subtree exactly once', () => {
    const frame = A.addNode({ kind: 'container', x: 100, y: 80, width: 300, height: 200 });
    A.addNode({ parentId: frame, x: 20, y: 30 });
    A.setSelection([frame]);

    A.duplicateSelection();

    const copiedIds = new Set(getStore().session.selection.nodeIds);
    const copiedFrame = getStore().doc.nodes.find(
      (node) => copiedIds.has(node.id) && node.kind === 'container',
    )!;
    const copiedChild = getStore().doc.nodes.find(
      (node) => copiedIds.has(node.id) && node.kind === 'shape',
    )!;
    expect(absolutePosition(getStore().doc, copiedFrame)).toEqual({ x: 116, y: 96 });
    expect(absolutePosition(getStore().doc, copiedChild)).toEqual({ x: 136, y: 126 });
  });

  it('detaches a copied child at its absolute position', () => {
    const frame = A.addNode({ kind: 'container', x: 100, y: 80, width: 300, height: 200 });
    const child = A.addNode({ parentId: frame, x: 20, y: 30 });
    A.setSelection([child]);

    A.duplicateSelection();

    const copy = getStore().doc.nodes.find((node) =>
      getStore().session.selection.nodeIds.includes(node.id),
    )!;
    expect(copy.parentId).toBeUndefined();
    expect({ x: copy.x, y: copy.y }).toEqual({ x: 136, y: 126 });
  });
});
