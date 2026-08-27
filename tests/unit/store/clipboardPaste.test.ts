import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { newEdge, newNode } from '../../../src/shared/model/create';
import { absolutePosition } from '../../../src/shared/model/queries';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

let clipboardText = '';

beforeEach(() => {
  resetStore();
  clipboardText = '';
  vi.stubGlobal('navigator', {
    clipboard: {
      readText: vi.fn(async () => clipboardText),
      writeText: vi.fn(async (text: string) => {
        clipboardText = text;
      }),
    },
  });
});

afterEach(() => {
  resetStore();
  vi.unstubAllGlobals();
});

describe('internal clipboard normalization', () => {
  it('drops pasted self-links and Mermaid endpoints', async () => {
    const a = newNode({ id: 'a', label: 'A' });
    const b = newNode({ id: 'b', label: 'B' });
    const island = newNode({ id: 'm', kind: 'mermaid', mermaidSource: 'pie' });
    clipboardText = JSON.stringify({
      type: 'thalyx/clipboard',
      version: 1,
      nodes: [a, b, island],
      edges: [
        newEdge({ source: 'a', target: 'a' }),
        newEdge({ source: 'a', target: 'm' }),
        newEdge({ source: 'a', target: 'b' }),
      ],
    });

    await A.pasteFromClipboard();

    expect(getStore().doc.edges).toHaveLength(1);
    expect(getStore().doc.edges[0]!.source).not.toBe(getStore().doc.edges[0]!.target);
    const nodes = new Map(getStore().doc.nodes.map((node) => [node.id, node]));
    expect(nodes.get(getStore().doc.edges[0]!.source)?.kind).not.toBe('mermaid');
    expect(nodes.get(getStore().doc.edges[0]!.target)?.kind).not.toBe('mermaid');
  });

  it('preserves one relative offset for a nested pasted subtree', async () => {
    const parent = newNode({
      id: 'parent',
      kind: 'container',
      x: 100,
      y: 80,
      width: 300,
      height: 200,
    });
    const child = newNode({ id: 'child', parentId: 'parent', x: 20, y: 30 });
    clipboardText = JSON.stringify({
      type: 'thalyx/clipboard',
      version: 1,
      nodes: [child, parent],
      edges: [],
    });

    await A.pasteFromClipboard();

    const pastedParent = getStore().doc.nodes.find((node) => node.kind === 'container')!;
    const pastedChild = getStore().doc.nodes.find((node) => node.kind === 'shape')!;
    expect(getStore().doc.nodes.indexOf(pastedParent)).toBeLessThan(
      getStore().doc.nodes.indexOf(pastedChild),
    );
    expect(pastedChild.parentId).toBe(pastedParent.id);
    expect(absolutePosition(getStore().doc, pastedChild)).toEqual({ x: 136, y: 126 });
  });

  it('copies a child without its frame at its absolute position', async () => {
    const frame = A.addNode({ kind: 'container', x: 100, y: 80, width: 300, height: 200 });
    const child = A.addNode({ parentId: frame, x: 20, y: 30 });

    await A.copySelectionInternal([child], []);
    resetStore();
    await A.pasteFromClipboard();

    const pasted = getStore().doc.nodes[0]!;
    expect(pasted.parentId).toBeUndefined();
    expect({ x: pasted.x, y: pasted.y }).toEqual({ x: 136, y: 126 });
  });
});
