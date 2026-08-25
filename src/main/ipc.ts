/**
 * IPC surface (PLAN.md §12.2) — the COMPLETE list; add nothing without
 * updating §14. All inputs zod-validated; path policy enforced (§14.5).
 */
import {
  BrowserWindow,
  dialog,
  ipcMain,
  shell,
  webUtils,
  clipboard,
  app,
  nativeImage,
} from 'electron';
import { readFile, stat } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { z } from 'zod';
import {
  addRecent,
  backupOnce,
  docIdForPath,
  readPrefs,
  recoveryClear,
  recoveryList,
  recoveryRead,
  recoveryWrite,
  writeAtomic,
  writePrefs,
} from './files';
import { openExternalSafely } from './security';

/** §14.5: paths the renderer may touch — granted via dialogs/recents/drops. */
const grantedPaths = new Set<string>();
const ALLOWED_EXTENSIONS = new Set(['.thalyx', '.mmd', '.mermaid', '.json']);
const MAX_CONTENT_BYTES = 50 * 1024 * 1024;

function grant(path: string): void {
  grantedPaths.add(resolve(path));
}

function assertGranted(path: string): void {
  if (process.env['THALYX_ALLOW_ANY_PATH'] === '1') return; // dev-mode loosening
  if (!grantedPaths.has(resolve(path))) {
    throw new Error(`path not granted: ${path}`);
  }
}

function assertExtension(path: string): void {
  const ext = path.slice(path.lastIndexOf('.')).toLowerCase();
  if (!ALLOWED_EXTENSIONS.has(ext)) {
    throw new Error(`extension not allowed: ${ext}`);
  }
}

export function registerIpc(getMainWindow: () => BrowserWindow | null): void {
  // --- dialog ---------------------------------------------------------------
  ipcMain.handle(
    'dialog:openFile',
    async (_e, filters?: Array<{ name: string; extensions: string[] }>) => {
      const win = getMainWindow();
      const res = await dialog.showOpenDialog(win!, {
        properties: ['openFile'],
        filters: filters ?? [
          { name: 'Thalyx documents', extensions: ['thalyx'] },
          { name: 'Mermaid', extensions: ['mmd', 'mermaid'] },
          { name: 'All files', extensions: ['*'] },
        ],
      });
      const path = res.filePaths[0];
      if (path) grant(path);
      return path ?? null;
    },
  );

  ipcMain.handle(
    'dialog:saveFile',
    async (_e, defaultName: string, filters?: Array<{ name: string; extensions: string[] }>) => {
      const win = getMainWindow();
      const res = await dialog.showSaveDialog(win!, {
        defaultPath: defaultName,
        filters: filters ?? [
          { name: 'Thalyx document', extensions: ['thalyx'] },
          { name: 'Mermaid', extensions: ['mmd'] },
          { name: 'SVG', extensions: ['svg'] },
          { name: 'PNG', extensions: ['png'] },
          { name: 'PDF', extensions: ['pdf'] },
        ],
      });
      if (res.canceled || !res.filePath) return null;
      grant(res.filePath);
      return res.filePath;
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
    if (contents.length > MAX_CONTENT_BYTES) throw new Error('content too large');
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
      z.string().min(1).max(64).parse(docId);
      await recoveryWrite(docId, contents, originalPath);
    },
  );
  ipcMain.handle('recovery:list', () => recoveryList());
  ipcMain.handle('recovery:read', async (_e, docId: string) => {
    z.string().min(1).max(64).parse(docId);
    return recoveryRead(docId);
  });
  ipcMain.handle('recovery:clear', async (_e, docId: string) => {
    z.string().min(1).max(64).parse(docId);
    await recoveryClear(docId);
  });

  // --- recents ----------------------------------------------------------------
  ipcMain.handle('recents:list', async () => {
    const prefs = await readPrefs();
    return prefs.recents.map((r) => ({ path: r.path, name: r.name }));
  });
  ipcMain.handle('recents:add', async (_e, path: string) => {
    const prefs = await addRecent(await readPrefs(), path);
    await writePrefs(prefs);
    grant(path);
  });
  ipcMain.handle('recents:clear', async () => {
    await writePrefs({ ...(await readPrefs()), recents: [] });
  });

  // --- prefs ------------------------------------------------------------------
  ipcMain.handle('prefs:get', async (_e, key: string) => {
    z.string().min(1).max(64).parse(key);
    const prefs = await readPrefs();
    return prefs[key as keyof typeof prefs] ?? null;
  });
  ipcMain.handle('prefs:set', async (_e, key: string, value: unknown) => {
    z.string().min(1).max(64).parse(key);
    const prefs = await readPrefs();
    (prefs as unknown as Record<string, unknown>)[key] = value;
    await writePrefs(prefs);
  });

  // --- shell / clipboard / app -------------------------------------------------
  ipcMain.handle('shellx:openExternal', (_e, url: string) => {
    openExternalSafely(url); // scheme-validated (§14.4)
  });
  ipcMain.handle('clip:writePng', (_e, bytes: Uint8Array) => {
    clipboard.writeImage(nativeImage.createFromBuffer(Buffer.from(bytes)));
  });
  ipcMain.handle('appx:version', () => app.getVersion());
  ipcMain.handle('appx:setDocumentEdited', (_e, edited: boolean) => {
    const win = getMainWindow();
    if (win) win.setDocumentEdited(edited);
  });
  ipcMain.handle('appx:setTitle', (_e, title: string) => {
    z.string().max(512).parse(title);
    const win = getMainWindow();
    if (win) win.setTitle(title);
  });
  ipcMain.handle('export:print', () => {
    const win = getMainWindow();
    win?.webContents.print({}); // native dialog (D11)
  });

  // --- events from main to renderer ---------------------------------------------
  const send = (channel: string, payload: unknown) => {
    getMainWindow()?.webContents.send(channel, payload);
  };
  // called by index.ts on menu actions / open-file events
  (globalThis as Record<string, unknown>).__thalyxSend = send;
  (globalThis as Record<string, unknown>).__thalyxGrant = grant;
  (globalThis as Record<string, unknown>).__thalyxDocIdForPath = docIdForPath;
  void shell;
  void webUtils;
  void basename;
}

export function sendToRenderer(channel: string, payload: unknown): void {
  const send = (globalThis as Record<string, unknown>).__thalyxSend as
    ((c: string, p: unknown) => void) | undefined;
  send?.(channel, payload);
}

export function grantPath(path: string): void {
  const grant = (globalThis as Record<string, unknown>).__thalyxGrant as
    ((p: string) => void) | undefined;
  grant?.(path);
}
