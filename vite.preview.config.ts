import { defineConfig } from 'vite';
import { resolve } from 'node:path';

/**
 * Serves the electron-vite renderer build (out/renderer) for the Playwright
 * web-mode suite (PLAN.md §15.2). Run after `npm run build`:
 *
 *   npx vite preview --config vite.preview.config.ts --port 4173
 */
export default defineConfig({
  root: resolve(__dirname, 'src/renderer'),
  build: {
    outDir: resolve(__dirname, 'out/renderer'),
    emptyOutDir: false,
  },
});
