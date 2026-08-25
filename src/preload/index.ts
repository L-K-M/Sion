/**
 * Thalyx preload bridge (PLAN.md §12.2) — the complete §12.2 surface.
 * §14.5: the renderer never receives raw node primitives; file paths flow
 * only through main's grant checks. `pathForDropped` wraps
 * webUtils.getPathForFile (File.path was removed in Electron 32).
 */
import { contextBridge, ipcRenderer, webUtils } from 'electron';
import type { IpcRendererEvent } from 'electron';

const thalyxApi = {
  dialog: {
    openFile: (filters?: Array<{ name: string; extensions: string[] }>): Promise<string | null> =>
      ipcRenderer.invoke('dialog:openFile', filters),
    saveFile: (
      defaultName: string,
      filters?: Array<{ name: string; extensions: string[] }>,
    ): Promise<string | null> => ipcRenderer.invoke('dialog:saveFile', defaultName, filters),
  },
  file: {
    read: (path: string): Promise<string> => ipcRenderer.invoke('file:read', path),
    writeAtomic: (path: string, contents: string): Promise<void> =>
      ipcRenderer.invoke('file:writeAtomic', path, contents),
    backup: (path: string): Promise<void> => ipcRenderer.invoke('file:backup', path),
    pathForDropped: (file: File): Promise<string> => {
      // webUtils is preload-only; main re-validates the returned path (§14.5)
      const path = webUtils.getPathForFile(file);
      return ipcRenderer.invoke('file:pathForDropped', path);
    },
  },
  recovery: {
    write: (docId: string, contents: string, originalPath: string | null): Promise<void> =>
      ipcRenderer.invoke('recovery:write', docId, contents, originalPath),
    list: (): Promise<Array<{ docId: string; originalPath: string | null; savedAt: number }>> =>
      ipcRenderer.invoke('recovery:list'),
    read: (docId: string): Promise<string> => ipcRenderer.invoke('recovery:read', docId),
    clear: (docId: string): Promise<void> => ipcRenderer.invoke('recovery:clear', docId),
  },
  recents: {
    list: (): Promise<Array<{ path: string; name: string }>> => ipcRenderer.invoke('recents:list'),
    add: (path: string): Promise<void> => ipcRenderer.invoke('recents:add', path),
    clear: (): Promise<void> => ipcRenderer.invoke('recents:clear'),
  },
  prefs: {
    get: (key: string): Promise<unknown> => ipcRenderer.invoke('prefs:get', key),
    set: (key: string, value: unknown): Promise<void> =>
      ipcRenderer.invoke('prefs:set', key, value),
  },
  shellx: {
    openExternal: (url: string): Promise<void> => ipcRenderer.invoke('shellx:openExternal', url),
  },
  clip: {
    writePng: (bytes: Uint8Array): Promise<void> => ipcRenderer.invoke('clip:writePng', bytes),
  },
  appx: {
    version: (): Promise<string> => ipcRenderer.invoke('appx:version'),
    onMenu: (cb: (action: { action: string; arg?: unknown }) => void): (() => void) => {
      const listener = (_e: IpcRendererEvent, payload: { action: string; arg?: unknown }) =>
        cb(payload);
      ipcRenderer.on('thalyx:menu-action', listener);
      return () => ipcRenderer.removeListener('thalyx:menu-action', listener);
    },
    onOpenFile: (cb: (path: string) => void): (() => void) => {
      const listener = (_e: IpcRendererEvent, path: string) => cb(path);
      ipcRenderer.on('thalyx:open-file', listener);
      return () => ipcRenderer.removeListener('thalyx:open-file', listener);
    },
    onRecoveryScratch: (
      cb: (payload: { docId: string; contents: string }) => void,
    ): (() => void) => {
      const listener = (_e: IpcRendererEvent, payload: { docId: string; contents: string }) =>
        cb(payload);
      ipcRenderer.on('thalyx:recovery-scratch', listener);
      return () => ipcRenderer.removeListener('thalyx:recovery-scratch', listener);
    },
    setDocumentEdited: (edited: boolean): Promise<void> =>
      ipcRenderer.invoke('appx:setDocumentEdited', edited),
    setTitle: (title: string): Promise<void> => ipcRenderer.invoke('appx:setTitle', title),
  },
  exportx: {
    print: (): Promise<void> => ipcRenderer.invoke('export:print'),
  },
};

contextBridge.exposeInMainWorld('thalyx', thalyxApi);

export type ThalyxApi = typeof thalyxApi;
