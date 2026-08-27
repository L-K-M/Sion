import {
  app,
  BrowserWindow,
  dialog,
  ipcMain,
  Menu,
  screen,
  type Event,
  type OpenDialogOptions,
} from 'electron';
import { randomUUID } from 'node:crypto';
import { isAbsolute, join, resolve } from 'node:path';
import { applyWebContentsSecurity } from './security';
import { grantPath, registerIpc, sendToRenderer } from './ipc';
import { buildMenu, type MenuAction } from './menu';
import {
  docIdForPath,
  readPrefs,
  recoveryList,
  recoveryRead,
  updatePrefs,
  type Prefs,
} from './files';
import { routeMenuAction } from './menuRouting';
import { WindowRegistry } from './windowRegistry';
import { resolveWindowBootstrap, WindowDocuments } from './windowDocuments';
import { canonicalDocumentPath } from './canonicalPath';
import type { DocumentPathReservation } from './documentSaveReservation';
import type { WindowBootstrap } from '../shared/windowBootstrap';
import { DOCUMENT_OPEN_FILTERS } from '../shared/documentOpenFilters';
import { QuitCoordinator } from './quitCoordinator';

const DOCUMENT_PATH = /\.(thalyx|json|mmd|mermaid)$/i;
const WINDOW_CASCADE_OFFSET = 24;
const CLOSE_FLUSH_TIMEOUT_MS = 5_000;
const UPDATE_CHECK_DELAY_MS = 5_000;

const windows = new WindowRegistry<BrowserWindow>((window) => window.isDestroyed());
const documents = new WindowDocuments<BrowserWindow>(randomUUID, docIdForPath, resolve);
const bootstrappedWindows = new Set<number>();
const closeAllowed = new Set<number>();
const closeTimers = new Map<number, ReturnType<typeof setTimeout>>();
const pendingDocumentPaths: string[] = [];
const quit = new QuitCoordinator();

let applicationReady = false;
let restoredWindowState: Prefs['windowState'];
let updateReady = false;
let installingUpdate = false;
let menuUpdate: Promise<void> = Promise.resolve();

function blankBootstrap(): WindowBootstrap {
  return {
    scratchId: randomUUID(),
    openPath: null,
    recovery: null,
    updateReady,
  };
}

function fileBootstrap(path: string): WindowBootstrap {
  const absolutePath = resolve(path);
  return {
    scratchId: docIdForPath(absolutePath),
    openPath: absolutePath,
    recovery: null,
    updateReady,
  };
}

function activeWindow(): BrowserWindow | null {
  return windows.target(BrowserWindow.getFocusedWindow());
}

function documentPaths(argv: string[], workingDirectory: string): string[] {
  return argv
    .filter((argument) => DOCUMENT_PATH.test(argument))
    .map((argument) =>
      isAbsolute(argument) ? resolve(argument) : resolve(workingDirectory, argument),
    );
}

async function persistWindowState(window: BrowserWindow): Promise<void> {
  const bounds = window.isMaximized() ? window.getNormalBounds() : window.getBounds();
  await updatePrefs((prefs) => ({
    ...prefs,
    windowState: { ...bounds, maximized: window.isMaximized() },
  }));
}

async function completeWindowClose(window: BrowserWindow): Promise<void> {
  const id = window.webContents.id;
  const timer = closeTimers.get(id);
  if (timer) clearTimeout(timer);
  closeTimers.delete(id);

  try {
    await persistWindowState(window);
  } catch (error) {
    console.warn('[main] window state persistence failed', { error: String(error) });
  }

  closeAllowed.add(id);
  if (!window.isDestroyed()) window.close();
}

function cancelWindowClose(window: BrowserWindow): void {
  const id = window.webContents.id;
  const timer = closeTimers.get(id);
  if (timer) clearTimeout(timer);
  closeTimers.delete(id);
  quit.cancel();

  if (window.isDestroyed()) return;
  void dialog.showMessageBox(window, {
    type: 'error',
    message: 'Thalyx could not finish saving this document.',
    detail: 'The window remains open. Check the destination and try again.',
  });
}

function requestWindowClose(window: BrowserWindow, event: Event): void {
  const id = window.webContents.id;
  if (closeAllowed.has(id) || !bootstrappedWindows.has(id)) return;

  event.preventDefault();
  if (closeTimers.has(id)) return;

  sendToRenderer('thalyx:before-close', {}, window);
  closeTimers.set(
    id,
    setTimeout(() => cancelWindowClose(window), CLOSE_FLUSH_TIMEOUT_MS),
  );
}

function validateRestoredPosition(window: BrowserWindow): void {
  if (!restoredWindowState) return;

  try {
    const bounds = window.getBounds();
    const nearest = screen.getDisplayMatching(bounds);
    const offX =
      bounds.x + bounds.width < nearest.workArea.x ||
      bounds.x > nearest.workArea.x + nearest.workArea.width;
    const offY =
      bounds.y + bounds.height < nearest.workArea.y ||
      bounds.y > nearest.workArea.y + nearest.workArea.height;
    if (offX || offY) window.center();
  } catch {
    window.center();
  }
}

function createWindow(bootstrap: WindowBootstrap = blankBootstrap()): BrowserWindow {
  const state = restoredWindowState;
  const cascade = windows.all().length * WINDOW_CASCADE_OFFSET;
  const window = new BrowserWindow({
    width: state?.width ?? 1280,
    height: state?.height ?? 800,
    ...(state ? { x: state.x + cascade, y: state.y + cascade } : {}),
    minWidth: 640,
    minHeight: 480,
    show: false,
    title: 'Thalyx',
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
      nodeIntegrationInWorker: false,
      webSecurity: true,
      preload: join(import.meta.dirname, '../preload/index.cjs'),
      spellcheck: false,
    },
  });
  const webContentsId = window.webContents.id;

  windows.add(window);
  documents.add(window, bootstrap);
  validateRestoredPosition(window);
  if (state?.maximized) window.maximize();

  window.on('focus', () => windows.markActive(window));
  window.once('ready-to-show', () => window.show());
  window.on('close', (event) => requestWindowClose(window, event));
  window.on('closed', () => {
    windows.remove(window);
    documents.remove(window);
    bootstrappedWindows.delete(webContentsId);
    closeAllowed.delete(webContentsId);
    const timer = closeTimers.get(webContentsId);
    if (timer) clearTimeout(timer);
    closeTimers.delete(webContentsId);
  });

  if (!app.isPackaged && process.env['ELECTRON_RENDERER_URL']) {
    void window.loadURL(process.env['ELECTRON_RENDERER_URL']).catch((error: unknown) => {
      console.error('[main] renderer dev-server load failed', { error });
    });
  } else {
    void window
      .loadFile(join(import.meta.dirname, '../renderer/index.html'))
      .catch((error: unknown) => {
        console.error('[main] renderer load failed', { error });
      });
  }

  return window;
}

function focusWindow(window: BrowserWindow): void {
  if (window.isMinimized()) window.restore();
  window.show();
  window.focus();
}

async function assertPathAvailable(window: BrowserWindow, path: string): Promise<void> {
  const canonicalPath = await canonicalDocumentPath(path);
  const owner = documents.owner(canonicalPath);
  if (!owner || owner === window) return;

  focusWindow(owner);
  throw new Error('document is already open in another window');
}

async function associateWindowPath(
  window: BrowserWindow,
  path: string | null,
): Promise<WindowBootstrap> {
  const canonicalPath = path === null ? null : await canonicalDocumentPath(path);
  const result = documents.associate(window, canonicalPath, updateReady);
  if (result.kind === 'associated') return result.bootstrap;

  focusWindow(result.owner);
  throw new Error('document is already open in another window');
}

async function reserveWindowPath(
  window: BrowserWindow,
  path: string,
): Promise<DocumentPathReservation> {
  const canonicalPath = await canonicalDocumentPath(path);
  const result = documents.reserve(window, canonicalPath, updateReady);
  if (result.kind === 'reserved') {
    return { path: canonicalPath, commit: result.commit, rollback: result.rollback };
  }

  focusWindow(result.owner);
  throw new Error('document is already open in another window');
}

async function openPath(path: string): Promise<void> {
  const canonicalPath = await canonicalDocumentPath(path);
  grantPath(canonicalPath);

  if (!applicationReady) {
    pendingDocumentPaths.push(canonicalPath);
    return;
  }

  const owner = documents.owner(canonicalPath);
  if (owner) {
    focusWindow(owner);
    return;
  }

  createWindow(fileBootstrap(canonicalPath));
}

async function chooseDocument(): Promise<void> {
  const target = activeWindow();
  const options: OpenDialogOptions = {
    properties: ['openFile'],
    filters: DOCUMENT_OPEN_FILTERS,
  };
  const result = target
    ? await dialog.showOpenDialog(target, options)
    : await dialog.showOpenDialog(options);
  const path = result.filePaths[0];
  if (path) await openPath(path);
}

async function chooseMermaidDocument(): Promise<void> {
  const target = activeWindow();
  const options: OpenDialogOptions = {
    properties: ['openFile'],
    filters: [{ name: 'Mermaid', extensions: ['mmd', 'mermaid', 'txt'] }],
  };
  const result = target
    ? await dialog.showOpenDialog(target, options)
    : await dialog.showOpenDialog(options);
  const path = result.filePaths[0];
  if (path) await openPath(path);
}

function routeApplicationMenu(action: MenuAction, arg?: unknown): void {
  if (action === 'new' || action === 'newWindow') {
    createWindow();
    return;
  }
  if (action === 'open') {
    void chooseDocument();
    return;
  }
  if (action === 'importMermaid') {
    void chooseMermaidDocument();
    return;
  }
  if (action === 'openRecent' && arg === null) {
    void updatePrefs((prefs) => ({ ...prefs, recents: [] })).then(() => rebuildMenu());
    return;
  }

  const target = activeWindow();
  if (action === 'about' && arg === undefined) {
    const options = {
      type: 'info' as const,
      title: 'About Thalyx',
      message: `Thalyx ${app.getVersion()}`,
      detail: 'A fast desktop diagramming tool.',
    };
    void (target ? dialog.showMessageBox(target, options) : dialog.showMessageBox(options));
    return;
  }

  void routeMenuAction(action, arg, openPath, (nextAction, nextArg) => {
    sendToRenderer('thalyx:menu-action', { action: nextAction, arg: nextArg }, target);
  });
}

function rebuildMenu(): Promise<void> {
  menuUpdate = menuUpdate.then(async () => {
    const prefs = await readPrefs();
    Menu.setApplicationMenu(buildMenu(activeWindow, routeApplicationMenu, prefs.recents));
  });

  return menuUpdate;
}

async function restoreInitialWindows(): Promise<void> {
  const paths = [...pendingDocumentPaths.splice(0), ...documentPaths(process.argv, process.cwd())];
  const restoredPaths = new Set<string>();
  for (const requestedPath of paths) {
    const path = await canonicalDocumentPath(requestedPath);
    if (restoredPaths.has(path)) continue;

    restoredPaths.add(path);
    grantPath(path);
    if (!documents.owner(path)) createWindow(fileBootstrap(path));
  }

  const scratchEntries = (await recoveryList()).filter((entry) => entry.originalPath === null);
  for (const entry of scratchEntries) {
    try {
      const contents = await recoveryRead(entry.docId);
      createWindow({
        scratchId: entry.docId,
        openPath: null,
        recovery: { docId: entry.docId, contents },
        updateReady,
      });
    } catch {
      // Ignore a corrupt recovery entry and continue restoring the others.
    }
  }

  if (windows.all().length === 0) createWindow();
}

async function setupUpdater(): Promise<void> {
  if (process.env['THALYX_E2E'] === '1') return;

  try {
    const electronUpdater = (await import('electron-updater')) as typeof import('electron-updater');
    const autoUpdater = electronUpdater.autoUpdater;
    autoUpdater.autoDownload = true;
    autoUpdater.autoInstallOnAppQuit = true;
    autoUpdater.on('error', (error) => {
      console.warn('[updater] error', { error: String(error) });
    });
    autoUpdater.on('update-downloaded', () => {
      updateReady = true;
      for (const window of windows.all()) {
        sendToRenderer('thalyx:update-ready', {}, window);
      }
    });
    ipcMain.handle('updater:check', async () => {
      const info = await autoUpdater.checkForUpdates();
      return {
        version: info?.updateInfo?.version ?? null,
        files: info?.updateInfo?.files?.length ?? 0,
      };
    });
    ipcMain.handle('updater:quitAndInstall', async () => {
      installingUpdate = true;
      const openWindows = windows.all();
      await Promise.all(
        openWindows.map(
          (window) =>
            new Promise<void>((resolveClosed) => {
              window.once('closed', resolveClosed);
              window.close();
            }),
        ),
      );
      autoUpdater.quitAndInstall();
    });
    setTimeout(() => {
      void autoUpdater.checkForUpdates().catch((error: unknown) => {
        console.warn('[updater] check failed', { error: String(error) });
      });
    }, UPDATE_CHECK_DELAY_MS);
  } catch (error) {
    console.warn('[updater] unavailable', { error: String(error) });
  }
}

async function initializeApplication(): Promise<void> {
  restoredWindowState = (await readPrefs()).windowState;
  registerIpc({
    getActiveWindow: activeWindow,
    async getBootstrap(window) {
      const bootstrap = documents.bootstrap(window);
      if (!bootstrap) throw new Error('window bootstrap unavailable');

      bootstrappedWindows.add(window.webContents.id);
      return resolveWindowBootstrap({ ...bootstrap, updateReady }, recoveryRead);
    },
    assertPathAvailable,
    associatePath: associateWindowPath,
    reservePath: reserveWindowPath,
    onRecentsChanged() {
      void rebuildMenu();
    },
    onCloseReady: completeWindowClose,
    onCloseFailed: cancelWindowClose,
  });
  await rebuildMenu();
  applicationReady = true;
  await restoreInitialWindows();
  await setupUpdater();
}

export function startApplication(): void {
  app.enableSandbox();
  if (!app.requestSingleInstanceLock()) {
    app.quit();
    return;
  }

  app.on('second-instance', (_event, argv, workingDirectory) => {
    const paths = documentPaths(argv, workingDirectory);
    if (paths.length === 0) {
      const target = activeWindow();
      if (target) focusWindow(target);
      return;
    }

    for (const path of paths) void openPath(path);
  });

  app.on('open-file', (event, path) => {
    event.preventDefault();
    void openPath(path);
  });

  app.on('web-contents-created', (_event, contents) => {
    applyWebContentsSecurity(contents);
  });

  app.on('before-quit', (event) => {
    const openWindows = windows.all();
    if (quit.isResuming() || openWindows.length === 0) return;

    event.preventDefault();
    quit.request();
    for (const window of openWindows) window.close();
  });

  if (process.platform === 'linux' && !process.env['ELECTRON_OZONE_PLATFORM_HINT']) {
    process.env['ELECTRON_OZONE_PLATFORM_HINT'] = 'auto';
  }

  void app
    .whenReady()
    .then(initializeApplication)
    .catch((error: unknown) => console.error('[main] initialization failed', { error }));

  app.on('activate', () => {
    if (applicationReady && windows.all().length === 0) createWindow();
  });

  app.on('window-all-closed', () => {
    if (quit.beginResumeWhenEmpty(windows.all().length)) {
      app.quit();
      return;
    }

    if (!installingUpdate && process.platform !== 'darwin') app.quit();
  });
}
