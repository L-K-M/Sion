/**
 * Thalyx main process entry (PLAN.md §12.1 for lifecycle; security per §14).
 *
 * M0 scope: single window with the full security baseline, single-instance
 * lock, and a stub `appx:version` IPC handler. Files/menus/IPC surface grow
 * in later milestones.
 */
import { app, BrowserWindow, ipcMain } from 'electron';
import { join } from 'node:path';
import { applyWebContentsSecurity } from './security';

let mainWindow: BrowserWindow | null = null;

function createWindow(): void {
  const win = new BrowserWindow({
    width: 1280,
    height: 800,
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
      // CJS preload (sandboxed preloads cannot use the ESM loader);
      // bundled by electron-vite to out/preload/index.cjs.
      preload: join(__dirname, '../preload/index.cjs'),
      spellcheck: false,
    },
  });

  win.on('ready-to-show', () => win.show());
  win.on('closed', () => {
    if (mainWindow === win) mainWindow = null;
  });

  mainWindow = win;

  if (!app.isPackaged && process.env['ELECTRON_RENDERER_URL']) {
    win.loadURL(process.env['ELECTRON_RENDERER_URL']).catch((err) => {
      console.error('[main] renderer dev-server load failed:', err);
    });
  } else {
    // electron-vite emits the renderer bundle to out/renderer/index.html.
    win.loadFile(join(__dirname, '../renderer/index.html')).catch((err) => {
      console.error('[main] renderer load failed:', err);
    });
  }
}

app.enableSandbox();

// Single instance (PLAN.md §12.1): a second launch focuses the existing
// window; its argv would route to openPath() once file handling exists.
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });

  app.on('web-contents-created', (_event, contents) => {
    applyWebContentsSecurity(contents);
  });

  app.whenReady().then(() => {
    // Stub of the §12.2 `appx.version` surface.
    ipcMain.handle('appx:version', () => app.getVersion());

    createWindow();

    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow();
    });
  });

  app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
  });
}
