// @vitest-environment jsdom
import { describe, expect, it } from 'vitest';
import { createRoot } from 'react-dom/client';
import { act } from 'react';
import { ShapeNode } from '../../../src/renderer/canvas/nodes/ShapeNode';
import { newNode } from '../../../src/shared/model/create';
import { resetStore, getStore } from '../../../src/renderer/store/store';
import * as A from '../../../src/renderer/store/actions';
import type { ThalyxNodeData } from '../../../src/renderer/canvas/rfSelectors';

describe('ShapeNode label editing (jsdom)', () => {
  it('mounts the label editor when session.editingLabel targets the node', async () => {
    resetStore();
    const node = newNode({ id: 'n1', label: 'Hello', shape: 'rounded', x: 0, y: 0 });
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root = createRoot(host);

    // Stub @xyflow/react internals the node relies on via minimal context
    const { ReactFlowProvider } = await import('@xyflow/react');
    await act(async () => {
      root.render(
        <ReactFlowProvider>
          <div data-nodeid="n1">
            <ShapeNode
              id="n1"
              type="shape"
              selected={false}
              dragging={false}
              draggable
              selectable
              deletable
              zIndex={0}
              isConnectable
              positionAbsoluteX={0}
              positionAbsoluteY={0}
              data={{ node } as ThalyxNodeData}
            />
          </div>
        </ReactFlowProvider>,
      );
    });
    expect(host.querySelector('.thalyx-node-label')?.textContent).toBe('Hello');
    expect(host.querySelector('.thalyx-label-editor')).toBeNull();

    await act(async () => {
      A.setEditingLabel({ kind: 'node', id: 'n1' });
    });
    const editor = host.querySelector('.thalyx-label-editor');
    expect(editor).not.toBeNull();
    expect(getStore().session.editingLabel).toEqual({ kind: 'node', id: 'n1' });

    await act(async () => {
      root.unmount();
    });
    host.remove();
    resetStore();
  });
});
