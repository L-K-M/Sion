const PRIMARY_POINTER_BUTTON = 0;

export function isPrimaryPointerButton(button: number): boolean {
  return button === PRIMARY_POINTER_BUTTON;
}

export interface PointerDragOptions {
  pointerId: number;
  onMove: (event: PointerEvent) => void;
  onFinish: () => void;
}

/** Own one pointer sequence and release every global listener together. */
export function startPointerDrag(target: Window, options: PointerDragOptions): () => void {
  let active = true;

  const onMove = (event: PointerEvent): void => {
    if (event.pointerId === options.pointerId) options.onMove(event);
  };
  const onPointerEnd = (event: PointerEvent): void => {
    if (event.pointerId === options.pointerId) finish();
  };
  const onBlur = (): void => finish();
  const finish = (): void => {
    if (!active) return;
    active = false;

    target.removeEventListener('pointermove', onMove);
    target.removeEventListener('pointerup', onPointerEnd);
    target.removeEventListener('pointercancel', onPointerEnd);
    target.removeEventListener('blur', onBlur);
    options.onFinish();
  };

  target.addEventListener('pointermove', onMove);
  target.addEventListener('pointerup', onPointerEnd);
  target.addEventListener('pointercancel', onPointerEnd);
  target.addEventListener('blur', onBlur);
  return finish;
}
