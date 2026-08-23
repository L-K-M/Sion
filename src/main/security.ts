/**
 * Security baseline for the renderer (PLAN.md §14.1–2).
 *
 * Thalyx loads untrusted content into a full Chromium (`.thalyx` docs,
 * `.mmd` files, pasted text), so the renderer is locked down hard:
 * context isolation, sandbox, no node integration, no navigation, no
 * popups. The CSP itself is injected into index.html per build mode by the
 * Vite HTML transform in electron.vite.config.ts.
 */
import { app, shell } from 'electron';
import { BrowserWindow } from 'electron';
import type { WebContents } from 'electron';
import { pathToFileURL } from 'node:url';

export function applyWebContentsSecurity(contents: WebContents): void {
  // Block all navigation away from the app bundle. The initial load does not
  // fire will-navigate; everything after it does.
  contents.on('will-navigate', (event, url) => {
    if (!isAllowedNavigation(url)) {
      event.preventDefault();
      console.warn(`[security] blocked navigation to ${url}`);
    }
  });

  // Never allow window.open / target=_blank popups.
  contents.setWindowOpenHandler(({ url }) => {
    console.warn(`[security] blocked window.open to ${url}`);
    return { action: 'deny' };
  });

  // Crash of the renderer: log and reload (document recovery handles state),
  // but stop after repeated consecutive crashes instead of looping forever.
  contents.on('render-process-gone', (_event, details) => {
    // Normal shutdown reports here too — don't "recover" a quitting app.
    if (details.reason === 'clean-exit') return;
    console.error(`[security] render-process-gone: ${details.reason} (${details.exitCode})`);
    const crashes = (crashCounts.get(contents) ?? 0) + 1;
    crashCounts.set(contents, crashes);
    if (crashes > MAX_CONSECUTIVE_CRASHES) {
      console.error('[security] renderer crash loop — giving up on auto-reload');
      return;
    }
    const win = BrowserWindow.fromWebContents(contents);
    if (win && !win.isDestroyed()) {
      win.reload();
    }
  });

  contents.on('did-finish-load', () => {
    crashCounts.delete(contents);
  });
}

/** Only the packaged app (or the dev server, in dev builds) may navigate. */
export function isAllowedNavigation(url: string): boolean {
  try {
    const parsed = new URL(url);
    // Dev: the renderer is served by electron-vite's HTTP dev server; allow
    // same-origin navigation there (the initial loadURL never fires this).
    const devUrl = app.isPackaged ? undefined : process.env['ELECTRON_RENDERER_URL'];
    if (devUrl && parsed.origin === new URL(devUrl).origin) return true;
    if (parsed.protocol !== 'file:') return false;
    // Allow loading from within the app bundle only (encode properly — the
    // app path may contain spaces or other URL-significant characters).
    const appRoot = pathToFileURL(`${app.getAppPath()}/`);
    return parsed.href.startsWith(appRoot.href);
  } catch {
    return false;
  }
}

/** Stop reloading a renderer that keeps crashing (crash-loop guard). */
const MAX_CONSECUTIVE_CRASHES = 5;
const crashCounts = new WeakMap<WebContents, number>();

/**
 * Open external links safely: explicit user action only, and main validates
 * the scheme (PLAN.md §14.4). Allowed: https, http, mailto.
 */
export function openExternalSafely(url: string): void {
  try {
    const parsed = new URL(url);
    if (['https:', 'http:', 'mailto:'].includes(parsed.protocol)) {
      void shell.openExternal(parsed.href);
    } else {
      console.warn(`[security] refused to open link with scheme ${parsed.protocol}`);
    }
  } catch {
    console.warn(`[security] refused to open malformed link ${JSON.stringify(url)}`);
  }
}
