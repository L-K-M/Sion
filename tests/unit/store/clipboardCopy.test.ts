import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import * as A from '../../../src/renderer/store/actions';
import { getStore, resetStore } from '../../../src/renderer/store/store';

let clipboardText = '';
let rejectWrites = false;

beforeEach(() => {
  resetStore();
  clipboardText = '';
  rejectWrites = false;
  vi.stubGlobal('navigator', {
    clipboard: {
      writeText: vi.fn(async (text: string) => {
        if (rejectWrites) throw new Error('clipboard unavailable');
        clipboardText = text;
      }),
    },
  });
});

afterEach(() => {
  resetStore();
  vi.unstubAllGlobals();
});

function payload(): {
  nodes: Array<{ id: string }>;
  edges: Array<{ source: string; target: string }>;
} {
  return JSON.parse(clipboardText) as ReturnType<typeof payload>;
}

describe('clipboard copy and cut', () => {
  it('copies internal edges when their endpoint nodes are selected', async () => {
    const first = A.addNode({ label: 'A' });
    const second = A.addNode({ label: 'B' });
    A.addEdge({ source: first, target: second });

    await A.copySelectionInternal([first, second], []);

    expect(payload().edges).toHaveLength(1);
  });

  it('copies a selected frame with its descendants and internal edges', async () => {
    const frame = A.addNode({ kind: 'container', width: 400, height: 300 });
    const first = A.addNode({ parentId: frame, x: 20, y: 20 });
    const second = A.addNode({ parentId: frame, x: 200, y: 20 });
    A.addEdge({ source: first, target: second });

    await A.copySelectionInternal([frame], []);

    expect(payload().nodes).toHaveLength(3);
    expect(payload().edges).toHaveLength(1);
  });

  it('keeps the selection when a cut cannot reach the clipboard', async () => {
    const node = A.addNode({ label: 'keep me' });
    rejectWrites = true;

    await A.cutSelectionInternal([node], []);

    expect(getStore().doc.nodes.map((candidate) => candidate.id)).toContain(node);
  });

  it('deletes only after a cut reaches the clipboard', async () => {
    const node = A.addNode({ label: 'cut me' });

    await A.cutSelectionInternal([node], []);

    expect(payload().nodes).toHaveLength(1);
    expect(getStore().doc.nodes).toHaveLength(0);
  });
});
