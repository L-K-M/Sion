import { defineConfig } from 'electron-vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'node:path';

/**
 * Content-Security-Policy, injected into the renderer's index.html by a Vite
 * HTML transform, per build mode (PLAN.md §14.1).
 *
 * - production: no remote content of any kind; the updater lives in main.
 * - dev: additionally allows Vite's React-refresh preamble (inline script) and
 *   the HMR WebSocket.
 */
const CSP_PROD =
  "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; " +
  "img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'";

const CSP_DEV =
  "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; " +
  "img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self' ws://localhost:*";

export const CSP_BY_MODE = { production: CSP_PROD, development: CSP_DEV } as const;

function cspMetaTag(policy: string): string {
  return `<meta http-equiv="Content-Security-Policy" content="${policy}">`;
}

/** Vite plugin: prepends the CSP meta tag to the renderer's index.html <head>. */
function cspPlugin(isDev: boolean) {
  const policy = isDev ? CSP_DEV : CSP_PROD;
  return {
    name: 'thalyx:csp',
    transformIndexHtml(html: string): string {
      const tag = cspMetaTag(policy);
      if (/<head[^>]*>/i.test(html)) {
        return html.replace(/<head([^>]*)>/i, (m) => `${m}\n    ${tag}`);
      }
      return html.replace(/<html([^>]*)>/i, (m) => `${m}\n  <head>\n    ${tag}\n  </head>`);
    },
  };
}

export default defineConfig(({ mode }) => {
  const isDev = mode !== 'production';
  return {
    main: {
      build: {
        rollupOptions: {
          input: { index: resolve(__dirname, 'src/main/index.ts') },
          output: { format: 'es' },
        },
      },
    },
    preload: {
      build: {
        rollupOptions: {
          input: { index: resolve(__dirname, 'src/preload/index.ts') },
          // Sandboxed preloads cannot use the ESM loader — always CJS.
          output: { format: 'cjs', entryFileNames: '[name].cjs' },
        },
      },
    },
    renderer: {
      root: resolve(__dirname, 'src/renderer'),
      plugins: [react(), cspPlugin(isDev)],
    },
  };
});
