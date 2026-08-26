/**
 * Renderer platform layer (PLAN.md §12.2): typed wrapper over window.thalyx
 * with a browser fallback (Playwright web-mode + vite dev without Electron).
 */
import type { ThalyxApi } from '../../preload/index';

type BrowserFile = {
  path: string | null;
  handle?: FileSystemFileHandle;
};

const browserState = {
  files: new Map<string, string>(),
  recents: [] as Array<{ path: string; name: string }>,
  prefs: {} as Record<string, unknown>,
};

function browserDownload(name: string, blob: Blob): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 5000);
}

const api = (): ThalyxApi | undefined => (globalThis as unknown as { thalyx?: ThalyxApi }).thalyx;

export const platform = {
  isElectron: (): boolean => api() !== undefined,

  async version(): Promise<string> {
    return api()?.appx.version() ?? '0.0.0-browser';
  },

  dialog: {
    async openFile(
      filters?: Array<{ name: string; extensions: string[] }>,
    ): Promise<string | null> {
      if (api()) return api()!.dialog.openFile(filters);
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = (filters ?? []).flatMap((f) => f.extensions.map((e) => `.${e}`)).join(',');
      const file: BrowserFile | null = await new Promise((resolve) => {
        input.onchange = () => {
          resolve(input.files && input.files[0] ? { path: input.files[0].name } : null);
        };
        input.click();
      });
      if (!file?.path) return null;
      const text = await new Promise<string>((resolve) => {
        const r = new FileReader();
        r.onload = () => resolve(String(r.result));
        if (input.files?.[0]) r.readAsText(input.files[0]!);
      });
      browserState.files.set(file.path, text);
      browserState.recents = [
        { path: file.path, name: file.path },
        ...browserState.recents.filter((r) => r.path !== file.path),
      ].slice(0, 10);
      return file.path;
    },
    async saveFile(
      defaultName: string,
      contents: string,
      filters?: Array<{ name: string; extensions: string[] }>,
    ): Promise<string | null> {
      if (api()) {
        // main saves atomically in the same call when a path is chosen
        return api()!.dialog.saveFile(defaultName, contents, filters);
      }
      const name = window.prompt('Save as', defaultName);
      if (!name) return null;
      browserDownload(name, new Blob([contents], { type: 'text/plain' }));
      browserState.files.set(name, contents);
      return name;
    },
  },

  file: {
    async read(path: string): Promise<string> {
      if (api()) return api()!.file.read(path);
      const contents = browserState.files.get(path);
      if (contents === undefined) throw new Error(`no such file: ${path}`);
      return contents;
    },
    async write(path: string, contents: string): Promise<void> {
      if (api()) {
        await api()!.file.writeAtomic(path, contents);
        return;
      }
      browserDownload(path, new Blob([contents], { type: 'text/plain' }));
      browserState.files.set(path, contents);
    },
    async pathForDropped(file: File): Promise<string> {
      if (api()) return api()!.file.pathForDropped(file);
      // browser mode: read the file into the virtual store under its name
      const text = await file.text();
      browserState.files.set(file.name, text);
      return file.name;
    },
  },

  recents: {
    async list(): Promise<Array<{ path: string; name: string }>> {
      if (api()) return api()!.recents.list();
      return browserState.recents;
    },
    async add(path: string): Promise<void> {
      await api()?.recents.add(path);
      if (!api()) {
        browserState.recents = [
          { path, name: path },
          ...browserState.recents.filter((r) => r.path !== path),
        ].slice(0, 10);
      }
    },
    async clear(): Promise<void> {
      if (api()) await api()!.recents.clear();
      browserState.recents = [];
    },
  },

  prefs: {
    async get<T>(key: string): Promise<T | null> {
      if (api()) return (await api()!.prefs.get(key)) as T | null;
      const v = browserState.prefs[key] ?? localStorage.getItem(`thalyx:prefs:${key}`);
      return v === null ? null : (JSON.parse(v as string) as T);
    },
    async set(key: string, value: unknown): Promise<void> {
      if (api()) {
        await api()!.prefs.set(key, value);
        return;
      }
      browserState.prefs[key] = value;
      localStorage.setItem(`thalyx:prefs:${key}`, JSON.stringify(value));
    },
  },

  appx: {
    onMenu(cb: (action: { action: string; arg?: unknown }) => void): () => void {
      return api()?.appx.onMenu(cb) ?? (() => undefined);
    },
    onOpenFile(cb: (path: string) => void): () => void {
      return api()?.appx.onOpenFile(cb) ?? (() => undefined);
    },
    onRecoveryScratch(cb: (p: { docId: string; contents: string }) => void): () => void {
      return api()?.appx.onRecoveryScratch(cb) ?? (() => undefined);
    },
    async setDocumentEdited(edited: boolean): Promise<void> {
      await api()?.appx.setDocumentEdited(edited);
    },
    async setTitle(title: string): Promise<void> {
      await api()?.appx.setTitle(title);
    },
  },

  clip: {
    async writePng(bytes: Uint8Array): Promise<void> {
      await api()?.clip.writePng(bytes);
    },
  },

  shellx: {
    async openExternal(url: string): Promise<void> {
      if (api()) {
        await api()!.shellx.openExternal(url);
        return;
      }
      window.open(url, '_blank', 'noopener');
    },
  },

  exportx: {
    async print(): Promise<void> {
      if (api()) {
        await api()!.exportx.print();
        return;
      }
      window.print();
    },
  },

  recovery: {
    async write(docId: string, contents: string, originalPath: string | null): Promise<void> {
      await api()?.recovery.write(docId, contents, originalPath);
      if (!api()) localStorage.setItem(`thalyx:recovery:${docId}`, contents);
    },
    async list(): Promise<Array<{ docId: string; originalPath: string | null; savedAt: number }>> {
      if (api()) return api()!.recovery.list();
      const out: Array<{ docId: string; originalPath: string | null; savedAt: number }> = [];
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i)!;
        if (key.startsWith('thalyx:recovery:')) {
          out.push({ docId: key.slice('thalyx:recovery:'.length), originalPath: null, savedAt: 0 });
        }
      }
      return out;
    },
    async read(docId: string): Promise<string> {
      if (api()) return api()!.recovery.read(docId);
      return localStorage.getItem(`thalyx:recovery:${docId}`) ?? '';
    },
    async clear(docId: string): Promise<void> {
      await api()?.recovery.clear(docId);
      if (!api()) localStorage.removeItem(`thalyx:recovery:${docId}`);
    },
  },
};
