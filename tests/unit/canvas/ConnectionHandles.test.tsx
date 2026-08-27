// @vitest-environment jsdom
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';
import { ReactFlowProvider } from '@xyflow/react';
import { ShapeNode } from '../../../src/renderer/canvas/nodes/ShapeNode';
import type { ThalyxNodeData } from '../../../src/renderer/canvas/rfSelectors';
import { newNode } from '../../../src/shared/model/create';
import { resetStore } from '../../../src/renderer/store/store';

(globalThis as Record<string, unknown>).IS_REACT_ACT_ENVIRONMENT = true;

describe('ConnectionHandles tool gating', () => {
  afterEach(() => resetStore());

  it('disables every magnet when React Flow disables node connections', async () => {
    const node = newNode({ id: 'shape' });
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root = createRoot(host);

    await act(async () => {
      root.render(
        <ReactFlowProvider>
          <ShapeNode
            id="shape"
            type="shape"
            selected={false}
            dragging={false}
            draggable
            selectable
            deletable
            zIndex={0}
            isConnectable={false}
            positionAbsoluteX={0}
            positionAbsoluteY={0}
            data={{ node } as ThalyxNodeData}
          />
        </ReactFlowProvider>,
      );
    });

    const handles = [...host.querySelectorAll('.thalyx-handle')];
    expect(handles).toHaveLength(4);
    expect(handles.every((handle) => !handle.classList.contains('connectable'))).toBe(true);
    expect(handles.every((handle) => !handle.classList.contains('connectablestart'))).toBe(true);

    await act(async () => root.unmount());
    host.remove();
  });
});
