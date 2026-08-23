/**
 * Types for the `window.thalyx` bridge exposed by the preload script
 * (PLAN.md §12.2). Grows with the IPC surface.
 */
import type { ThalyxApi } from '../../preload/index';

declare global {
  interface Window {
    thalyx?: ThalyxApi;
  }
}

export {};
