/**
 * Thalyx main process entry (PLAN.md §12.1 lifecycle, §12.3 menus, §12.4 recovery).
 */
import { app, BrowserWindow, Menu, screen } from 'electron';
import { join } from 'node:path';
import { readFile } from 'node:fs/promises';
import { applyWebContentsSecurity } from './security';
import { registerIpc, sendToRenderer, grantPath } from './ipc';
import { buildMenu } from './menu';
import { docIdForPath, recoveryList, readPrefs, writePrefs } from './files';

let mainWindow: BrowserWindow | null = null;

const prefs = await readPrefs();

function createWindow(): void {
  const state = prefs.windowState;
  const win = new BrowserWindow({
    width: state?.width ?? 1280,
    height: state?.height ?? 800,
    ...(state ? { x: state.x, y: state.y } : {}),
    minWidth: 640,
    minHeight: 480,
    show: false,
    title: 'Thalyx',
    webPreferences: {
      // Security baseline (PLAN.md §14.1) — never relax these.
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      nodeIntegrationInWorker: false,
      webSecurity: true,
      preload: join(import.meta.dirname, '../preload/index.cjs'),
      spellcheck: false,
    },
  });

  // validate restored position is on-screen (§12.1)
  if (state) {
    const visible = win.isVisibleOnAllWorkspaces; // cheap check; bounds validated below
    void visible;
    try {
      const bounds = win.getBounds();
      const nearest = screen.getDisplayMatching(bounds);
      if (
        bounds.x + bounds.width < nearest.workArea.x ||
        bounds.x > nearest.workArea.x + nearest.workArea.width
      ) {
        win.center();
      }
    } catch {
      win.center();
    }
    if (state.maximized) win.maximize();
  }

  win.on('ready-to-show', () => {
    win.show();
    while (pendingOpenPaths.length > 0) {
      const p = pendingOpenPaths.shift()!;
      sendToRenderer('thalyx:open-file', p);
    }
  });
  win.on('close', () => {
    // persist window state (§12.5)
    const bounds = win.isMaximized() ? win.getNormalBounds() : win.getBounds();
    prefs.windowState = { ...bounds, maximized: win.isMaximized() };
    void writePrefs(prefs);
  });
  win.on('closed', () => {
    if (mainWindow === win) mainWindow = null;
  });

  mainWindow = win;

  if (!app.isPackaged && process.env['ELECTRON_RENDERER_URL']) {
    win.loadURL(process.env['ELECTRON_RENDERER_URL']).catch((err) => {
      console.error('[main] renderer dev-server load failed:', err);
    });
  } else {
    win.loadFile(join(import.meta.dirname, '../renderer/index.html')).catch((err) => {
      console.error('[main] renderer load failed:', err);
    });
  }
}

/** Open-file paths delivered before a window exists (held + flushed). */
const pendingOpenPaths: string[] = [];

/** Open a file path routed from argv / open-file / second-instance. */
async function openPath(path: string): Promise<void> {
  grantPath(path);
  if (mainWindow === null) {
    pendingOpenPaths.push(path); // flushed once the window finishes loading
    return;
  }
  sendToRenderer('thalyx:open-file', path);
}

app.enableSandbox();

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', (_e, argv) => {
    const fileArg = argv.find((a) => /\.(thalyx|mmd|mermaid)$/i.test(a));
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
      if (fileArg) void openPath(fileArg);
    }
  });

  app.on('open-file', (event, path) => {
    event.preventDefault();
    void openPath(path);
  });

  app.on('web-contents-created', (_event, contents) => {
    applyWebContentsSecurity(contents);
  });

  app.whenReady().then(async () => {
    registerIpc(() => mainWindow);

    const menu = buildMenu(
      () => mainWindow,
      (action, arg) => {
        // Edit items route by focus context in the renderer; everything else
        // dispatches the store action directly there.
        sendToRenderer('thalyx:menu-action', { action, arg });
      },
      prefs.recents,
    );
    Menu.setApplicationMenu(menu);

    createWindow();

    // macOS file association / launch argv
    const fileArg = process.argv.find((a) => /\.(thalyx|mmd|mermaid)$/i.test(a));
    if (fileArg) {
      grantPath(fileArg);
      sendToRenderer('thalyx:open-file', fileArg);
    }

    // Recovery restore (§12.4): silently restore the untitled scratch; for
    // path-associated entries newer than the file, offer via toast.
    const entries = await recoveryList();
    // delay the broadcast until the renderer's listeners are attached
    // (preload events registered in effects after first paint)
    await new Promise((resolve) => setTimeout(resolve, 800));
    for (const entry of entries) {
      if (entry.originalPath === null) {
        try {
          const contents = await readFile(
            join(app.getPath('userData'), 'recovery', `${entry.docId}.thalyx`),
            'utf8',
          );
          sendToRenderer('thalyx:recovery-scratch', { docId: entry.docId, contents });
        } catch {
          // ignore unreadable entries
        }
      }
    }

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });
}

// exposed for ipc (docId computation without import cycles)
export { docIdForPath };
