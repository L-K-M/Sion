import { defineConfig, type Plugin } from 'vite';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

/**
 * Serves the electron-vite renderer build (out/renderer) for the Playwright
 * web-mode suite (PLAN.md §15.2). Run after `npm run build`:
 *
 *   npx vite preview --config vite.preview.config.ts --port 4173
 *
 * Also exposes the export-pipeline modules to the e2e suite via virtual
 * modules (page.evaluate cannot import TS sources from the built bundle).
 */
const e2eVirtualModules: Plugin = {
  name: 'thalyx-e2e-virtual-modules',
  apply: 'serve' as const,
  load(id: string) {
    if (id.endsWith('__thalyx-svg.ts')) {
      return readFileSync(resolve(__dirname, 'src/shared/export/svg.ts'), 'utf8');
    }
    if (id.endsWith('__thalyx-pipeline.ts')) {
      return readFileSync(resolve(__dirname, 'src/renderer/export/pipeline.ts'), 'utf8');
    }
    return null;
  },
};

export default defineConfig({
  root: resolve(__dirname, 'src/renderer'),
  plugins: [e2eVirtualModules],
  build: {
    outDir: resolve(__dirname, 'out/renderer'),
    emptyOutDir: false,
  },
});
