// @vitest-environment jsdom
import { describe, expect, it, vi } from 'vitest';
import {
  isPrimaryPointerButton,
  startPointerDrag,
} from '../../../src/renderer/canvas/edges/pointerDrag';

function pointerEvent(type: string, pointerId: number): PointerEvent {
  const event = new Event(type) as PointerEvent;
  Object.defineProperty(event, 'pointerId', { value: pointerId });
  return event;
}

describe('edge pointer drag lifecycle', () => {
  it('reserves middle and right drag for canvas panning', () => {
    expect(isPrimaryPointerButton(0)).toBe(true);
    expect(isPrimaryPointerButton(1)).toBe(false);
    expect(isPrimaryPointerButton(2)).toBe(false);
  });

  it('filters other pointers and stops after pointer cancellation', () => {
    const onMove = vi.fn();
    const onFinish = vi.fn();
    startPointerDrag(window, { pointerId: 7, onMove, onFinish });

    window.dispatchEvent(pointerEvent('pointermove', 8));
    window.dispatchEvent(pointerEvent('pointermove', 7));
    window.dispatchEvent(pointerEvent('pointercancel', 7));
    window.dispatchEvent(pointerEvent('pointermove', 7));

    expect(onMove).toHaveBeenCalledTimes(1);
    expect(onFinish).toHaveBeenCalledTimes(1);
  });

  it('finishes and removes listeners when the window blurs', () => {
    const onMove = vi.fn();
    const onFinish = vi.fn();
    startPointerDrag(window, { pointerId: 3, onMove, onFinish });

    window.dispatchEvent(new Event('blur'));
    window.dispatchEvent(pointerEvent('pointermove', 3));

    expect(onMove).not.toHaveBeenCalled();
    expect(onFinish).toHaveBeenCalledTimes(1);
  });
});
