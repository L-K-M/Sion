// @vitest-environment jsdom
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';
import { ReactFlowProvider } from '@xyflow/react';
import { ContainerNode } from '../../../src/renderer/canvas/nodes/ContainerNode';
import type { ThalyxNodeData } from '../../../src/renderer/canvas/rfSelectors';
import { newNode } from '../../../src/shared/model/create';
import * as A from '../../../src/renderer/store/actions';
import { resetStore } from '../../../src/renderer/store/store';

(globalThis as Record<string, unknown>).IS_REACT_ACT_ENVIRONMENT = true;

describe('ContainerNode label editing', () => {
  afterEach(() => resetStore());

  it('mounts the label editor when editing targets the container', async () => {
    const node = newNode({ id: 'frame', kind: 'container', label: 'Frame', x: 0, y: 0 });
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root = createRoot(host);

    await act(async () => {
      root.render(
        <ReactFlowProvider>
          <ContainerNode
            id="frame"
            type="container"
            selected
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
        </ReactFlowProvider>,
      );
    });

    await act(async () => A.setEditingLabel({ kind: 'node', id: 'frame' }));

    expect(host.querySelector('.thalyx-label-editor')).not.toBeNull();

    await act(async () => root.unmount());
    host.remove();
  });
});
