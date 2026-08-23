/**
 * Thalyx preload bridge (PLAN.md §12.2).
 *
 * M0 exposes only the stub `appx.version()`. The full IPC surface
 * (dialog/file/recovery/recents/prefs/shellx/clip/export/updater) lands with
 * the milestones that need it. Everything is exposed via contextBridge with
 * `contextIsolation: true`; no node primitives ever cross.
 */
import { contextBridge, ipcRenderer } from 'electron';

const thalyxApi = {
  appx: {
    version(): Promise<string> {
      return ipcRenderer.invoke('appx:version');
    },
  },
};

contextBridge.exposeInMainWorld('thalyx', thalyxApi);

export type ThalyxApi = typeof thalyxApi;
