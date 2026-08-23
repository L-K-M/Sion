/**
 * Typed wrapper over the `window.thalyx` bridge with a browser-mode fallback
 * (PLAN.md §12.2): the renderer must also run in plain Chromium for Playwright
 * web-mode tests and `vite dev`-style workflows where no preload exists.
 */
export const platform = {
  async version(): Promise<string> {
    if (typeof window !== 'undefined' && window.thalyx) {
      return window.thalyx.appx.version();
    }
    return '0.0.0-browser';
  },
};
