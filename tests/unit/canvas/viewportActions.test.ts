import { describe, expect, it, vi } from 'vitest';
import {
  fitCanvas,
  fitSelection,
  resetCanvasZoom,
  zoomCanvasIn,
  zoomCanvasOut,
} from '../../../src/renderer/canvas/viewportActions';

function viewport() {
  return {
    fitView: vi.fn().mockResolvedValue(true),
    getViewport: vi.fn(() => ({ x: 12, y: 34, zoom: 2 })),
    setViewport: vi.fn().mockResolvedValue(true),
    zoomIn: vi.fn().mockResolvedValue(true),
    zoomOut: vi.fn().mockResolvedValue(true),
  };
}

describe('canvas viewport actions', () => {
  it('routes zoom controls through React Flow', () => {
    const flow = viewport();

    zoomCanvasIn(flow);
    zoomCanvasOut(flow);
    resetCanvasZoom(flow);

    expect(flow.zoomIn).toHaveBeenCalledOnce();
    expect(flow.zoomOut).toHaveBeenCalledOnce();
    expect(flow.setViewport).toHaveBeenCalledWith(
      { x: 12, y: 34, zoom: 1 },
      expect.objectContaining({ duration: expect.any(Number) }),
    );
  });

  it('fits selected nodes or the whole canvas', () => {
    const flow = viewport();

    fitSelection(flow, ['a', 'b']);
    fitSelection(flow, []);
    fitCanvas(flow);

    expect(flow.fitView).toHaveBeenNthCalledWith(
      1,
      expect.objectContaining({ nodes: [{ id: 'a' }, { id: 'b' }] }),
    );
    expect(flow.fitView).toHaveBeenNthCalledWith(2, expect.not.objectContaining({ nodes: [] }));
    expect(flow.fitView).toHaveBeenNthCalledWith(3, expect.objectContaining({ maxZoom: 1.25 }));
  });
});
