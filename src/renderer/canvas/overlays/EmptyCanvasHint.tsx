/**
 * Empty-canvas hint layer (PLAN.md §10.1 principle 1 / I1): open straight
 * onto a canvas — no pickers, no dialogs; just a gentle hint of how to start.
 */
export function EmptyCanvasHint({ visible, tool }: { visible: boolean; tool: string }) {
  if (!visible) return null;
  return (
    <div className="thalyx-empty-hint" aria-hidden={tool === 'select' ? undefined : true}>
      <div className="thalyx-empty-hint-row">
        <kbd>R</kbd> <kbd>O</kbd> <kbd>D</kbd> shape tools · drag on the canvas to place
      </div>
      <div className="thalyx-empty-hint-sub">
        or pick a shape from the toolbar on the left · middle/right-drag or space-drag to pan ·
        scroll to zoom
      </div>
    </div>
  );
}
