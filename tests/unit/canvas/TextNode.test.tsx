// @vitest-environment jsdom
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, it } from 'vitest';
import { ReactFlowProvider } from '@xyflow/react';
import { TextNode } from '../../../src/renderer/canvas/nodes/TextNode';
import type { ThalyxNodeData } from '../../../src/renderer/canvas/rfSelectors';
import { newNode } from '../../../src/shared/model/create';
import { resetStore } from '../../../src/renderer/store/store';

(globalThis as Record<string, unknown>).IS_REACT_ACT_ENVIRONMENT = true;

describe('TextNode empty state', () => {
  afterEach(() => resetStore());

  it('keeps an empty text object visible and discoverable', async () => {
    const node = newNode({ id: 'text', kind: 'text', label: '' });
    const host = document.createElement('div');
    document.body.appendChild(host);
    const root = createRoot(host);

    await act(async () => {
      root.render(
        <ReactFlowProvider>
          <TextNode
            id="text"
            type="text"
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

    expect(host.querySelector('.thalyx-text-placeholder')?.textContent).toBe('Text');

    await act(async () => root.unmount());
    host.remove();
  });
});
