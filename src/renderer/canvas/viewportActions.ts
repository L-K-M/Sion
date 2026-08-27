import type { ReactFlowInstance } from '@xyflow/react';

const VIEWPORT_ANIMATION_MS = 200;
const FIT_PADDING = 0.2;
const FIT_MAX_ZOOM = 1.25;

type CanvasViewport = Pick<
  ReactFlowInstance,
  'fitView' | 'getViewport' | 'setViewport' | 'zoomIn' | 'zoomOut'
>;

export function zoomCanvasIn(flow: CanvasViewport): void {
  void flow.zoomIn({ duration: VIEWPORT_ANIMATION_MS });
}

export function zoomCanvasOut(flow: CanvasViewport): void {
  void flow.zoomOut({ duration: VIEWPORT_ANIMATION_MS });
}

export function resetCanvasZoom(flow: CanvasViewport): void {
  const { x, y } = flow.getViewport();
  void flow.setViewport({ x, y, zoom: 1 }, { duration: VIEWPORT_ANIMATION_MS });
}

export function fitCanvas(flow: CanvasViewport): void {
  void flow.fitView({
    padding: FIT_PADDING,
    maxZoom: FIT_MAX_ZOOM,
    duration: VIEWPORT_ANIMATION_MS,
  });
}

export function fitSelection(flow: CanvasViewport, nodeIds: string[]): void {
  const options = { padding: FIT_PADDING, duration: VIEWPORT_ANIMATION_MS };
  if (nodeIds.length === 0) {
    void flow.fitView(options);
    return;
  }

  void flow.fitView({ ...options, nodes: nodeIds.map((id) => ({ id })) });
}
