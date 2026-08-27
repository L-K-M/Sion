/**
 * IPC surface (PLAN.md §12.2) — the COMPLETE list; add nothing without
 * updating §14. All inputs zod-validated; path policy enforced (§14.5).
 */
import {
  BrowserWindow,
  dialog,
  ipcMain,
  clipboard,
  app,
  nativeImage,
  type IpcMainInvokeEvent,
  type OpenDialogOptions,
} from 'electron';
import { readFile, stat } from 'node:fs/promises';
import { extname, resolve } from 'node:path';
import { z } from 'zod';
import {
  addRecent,
  backupOnce,
  readPrefs,
  recoveryClear,
  recoveryList,
  recoveryRead,
  recoveryWrite,
  writeAtomic,
  updatePrefs,
} from './files';
import { openExternalSafely } from './security';
import type { WindowBootstrap } from '../shared/windowBootstrap';
import { DOCUMENT_OPEN_FILTERS } from '../shared/documentOpenFilters';
import { SaveDialogPurpose } from '../shared/saveDialog';
import { saveTargetPath, type DocumentPathReservation } from './documentSaveReservation';
import {
  MAX_CONTENT_BYTES,
  validateContentSize,
  validateDocId,
  validateRecoveryWrite,
  validateSavePath,
} from './ipcValidation';

/** §14.5: paths the renderer may touch — granted via dialogs/recents/drops. */
const grantedPaths = new Set<string>();
const ALLOWED_EXTENSIONS = new Set([
  '.thalyx',
  '.mmd',
  '.mermaid',
  '.json',
  '.txt',
  '.svg',
  '.png',
  '.pdf',
]);

const DOCUMENT_SAVE_FILTERS = [{ name: 'Thalyx document', extensions: ['thalyx'] }];
const EXPORT_SAVE_FILTERS = [
  { name: 'Mermaid', extensions: ['mmd'] },
  { name: 'SVG', extensions: ['svg'] },
  { name: 'PNG', extensions: ['png'] },
  { name: 'PDF', extensions: ['pdf'] },
];

function grant(path: string): void {
  grantedPaths.add(resolve(path));
}

function assertGranted(path: string): void {
  // dev-mode loosening only for unpackaged runs
  if (!app.isPackaged && process.env['THALYX_ALLOW_ANY_PATH'] === '1') return;
  if (!grantedPaths.has(resolve(path))) {
    throw new Error(`path not granted: ${path}`);
  }
}

function assertExtension(path: string): void {
  const ext = extname(path).toLowerCase();
  if (!ALLOWED_EXTENSIONS.has(ext)) {
    throw new Error(`extension not allowed: ${ext}`);
  }
}

export interface IpcRegistration {
  getActiveWindow: () => BrowserWindow | null;
  getBootstrap: (window: BrowserWindow) => WindowBootstrap | Promise<WindowBootstrap>;
  assertPathAvailable: (window: BrowserWindow, path: string) => void | Promise<void>;
  associatePath: (
    window: BrowserWindow,
    path: string | null,
  ) => WindowBootstrap | Promise<WindowBootstrap>;
  reservePath: (
    window: BrowserWindow,
    path: string,
  ) => DocumentPathReservation | Promise<DocumentPathReservation>;
  onRecentsChanged: () => void;
  onCloseReady: (window: BrowserWindow) => void | Promise<void>;
  onCloseFailed: (window: BrowserWindow) => void;
}

let getActiveWindow: () => BrowserWindow | null = () => null;

function windowForEvent(event: IpcMainInvokeEvent): BrowserWindow | null {
  return BrowserWindow.fromWebContents(event.sender);
}

export function registerIpc(registration: IpcRegistration): void {
  getActiveWindow = registration.getActiveWindow;
  // --- dialog ---------------------------------------------------------------
  ipcMain.handle(
    'dialog:openFile',
    async (event, filters?: Array<{ name: string; extensions: string[] }>) => {
      const win = windowForEvent(event);
      const options: OpenDialogOptions = {
        properties: ['openFile'],
        filters: filters ?? DOCUMENT_OPEN_FILTERS,
      };
      const res = win
        ? await dialog.showOpenDialog(win, options)
        : await dialog.showOpenDialog(options);
      const path = res.filePaths[0];
      if (path) grant(path);
      return path ?? null;
    },
  );

  ipcMain.handle(
    'dialog:saveFile',
    async (
      event,
      defaultName: string,
      contents: string | undefined,
      filters?: Array<{ name: string; extensions: string[] }>,
      purpose: SaveDialogPurpose = SaveDialogPurpose.Export,
    ) => {
      purpose = z.nativeEnum(SaveDialogPurpose).parse(purpose);
      const win = windowForEvent(event);
      if (!win) return null;
      const saveFilters =
        purpose === SaveDialogPurpose.Document
          ? DOCUMENT_SAVE_FILTERS
          : (filters ?? EXPORT_SAVE_FILTERS);
      const res = await dialog.showSaveDialog(win, {
        defaultPath: defaultName,
        filters: saveFilters,
      });
      if (res.canceled || !res.filePath) return null;
      assertExtension(res.filePath); // validate BEFORE granting
      validateSavePath(res.filePath, purpose);
      if (purpose === SaveDialogPurpose.Document && typeof contents !== 'string') {
        throw new Error('document save contents are required');
      }
      if (typeof contents === 'string') {
        validateContentSize(contents);
      }

      const reservation =
        purpose === SaveDialogPurpose.Document
          ? await registration.reservePath(win, res.filePath)
          : null;
      const targetPath = saveTargetPath(res.filePath, reservation);
      try {
        assertExtension(targetPath);
        validateSavePath(targetPath, purpose);
        if (typeof contents === 'string') {
          await backupOnce(targetPath);
          await writeAtomic(targetPath, contents);
        }
        reservation?.commit();
      } catch (error) {
        reservation?.rollback();
        throw error;
      }

      grant(targetPath);
      return targetPath;
    },
  );

  // --- file -----------------------------------------------------------------
  ipcMain.handle('file:read', async (_e, path: string) => {
    assertGranted(path);
    assertExtension(path);
    const s = await stat(path);
    if (!s.isFile()) throw new Error('not a file');
    if (s.size > MAX_CONTENT_BYTES) throw new Error('file too large (>50 MB)');
    return readFile(path, 'utf8');
  });

  ipcMain.handle('file:writeAtomic', async (_e, path: string, contents: string) => {
    assertGranted(path);
    assertExtension(path);
    validateContentSize(contents);
    await backupOnce(path);
    await writeAtomic(path, contents);
  });

  ipcMain.handle('file:backup', async (_e, path: string) => {
    assertGranted(path);
    await backupOnce(path);
  });

  // §14.5: preload wraps webUtils.getPathForFile; main re-validates the result
  ipcMain.handle('file:pathForDropped', async (_e, path: string) => {
    assertExtension(path);
    const s = await stat(path).catch(() => null);
    if (!s || !s.isFile() || s.size > MAX_CONTENT_BYTES) {
      throw new Error('dropped file rejected');
    }
    grant(path);
    return path;
  });

  // --- recovery ---------------------------------------------------------------
  ipcMain.handle(
    'recovery:write',
    async (_e, docId: string, contents: string, originalPath: string | null) => {
      validateRecoveryWrite(docId, contents);
      await recoveryWrite(docId, contents, originalPath);
    },
  );
  ipcMain.handle('recovery:list', () => recoveryList());
  ipcMain.handle('recovery:read', async (_e, docId: string) => {
    validateDocId(docId);
    return recoveryRead(docId);
  });
  ipcMain.handle('recovery:clear', async (_e, docId: string) => {
    validateDocId(docId);
    await recoveryClear(docId);
  });

  // --- recents ----------------------------------------------------------------
  ipcMain.handle('recents:list', async () => {
    const prefs = await readPrefs();
    return prefs.recents.map((r) => ({ path: r.path, name: r.name }));
  });
  ipcMain.handle('recents:add', async (_e, path: string) => {
    z.string().min(1).max(4096).parse(path);
    assertGranted(path);
    assertExtension(path);
    await updatePrefs((prefs) => addRecent(prefs, path));
    registration.onRecentsChanged();
  });
  ipcMain.handle('recents:clear', async () => {
    await updatePrefs((prefs) => ({ ...prefs, recents: [] }));
    registration.onRecentsChanged();
  });

  // --- prefs ------------------------------------------------------------------
  ipcMain.handle('prefs:get', async (_e, key: string) => {
    z.string().min(1).max(64).parse(key);
    const prefs = await readPrefs();
    return prefs[key as keyof typeof prefs] ?? null;
  });
  ipcMain.handle('prefs:set', async (_e, key: string, value: unknown) => {
    z.string().min(1).max(64).parse(key);
    await updatePrefs((prefs) => {
      (prefs as unknown as Record<string, unknown>)[key] = value;
      return prefs;
    });
  });

  // --- shell / clipboard / app -------------------------------------------------
  ipcMain.handle('shellx:openExternal', (_e, url: string) => {
    z.string().url().max(2048).parse(url); // must parse as a URL at all
    openExternalSafely(url); // scheme-validated (§14.4)
  });
  ipcMain.handle('clip:writePng', (_e, bytes: Uint8Array) => {
    clipboard.writeImage(nativeImage.createFromBuffer(Buffer.from(bytes)));
  });
  ipcMain.handle('appx:version', () => app.getVersion());

  ipcMain.handle('appx:bootstrap', (event) => {
    const win = windowForEvent(event);
    if (!win) throw new Error('document window unavailable');

    return registration.getBootstrap(win);
  });
  ipcMain.handle('appx:setAssociatedPath', async (event, path: string | null) => {
    z.string().max(4096).nullable().parse(path);
    const win = windowForEvent(event);
    if (!win) throw new Error('document window unavailable');
    if (path !== null) {
      assertGranted(path);
      assertExtension(path);
      await registration.assertPathAvailable(win, path);
    }

    return registration.associatePath(win, path);
  });
  ipcMain.handle('appx:closeReady', async (event) => {
    const win = windowForEvent(event);
    if (win) await registration.onCloseReady(win);
  });
  ipcMain.handle('appx:closeFailed', (event) => {
    const win = windowForEvent(event);
    if (win) registration.onCloseFailed(win);
  });
  ipcMain.handle('appx:setDocumentEdited', (event, edited: boolean) => {
    windowForEvent(event)?.setDocumentEdited(edited);
  });
  ipcMain.handle('appx:setTitle', (event, title: string) => {
    z.string().max(512).parse(title);
    windowForEvent(event)?.setTitle(title);
  });
  ipcMain.handle('export:print', (event) => {
    windowForEvent(event)?.webContents.print({}); // native dialog (D11)
  });
}

export function sendToRenderer(
  channel: string,
  payload: unknown,
  target: BrowserWindow | null = getActiveWindow(),
): void {
  if (!target || target.isDestroyed()) return;

  target.webContents.send(channel, payload);
}

export function grantPath(path: string): void {
  grant(path);
}
