/**
 * Document file lifecycle for the renderer (PLAN.md §12.4): open/save/saveAs,
 * dirty tracking, 800 ms debounced autosave (path → atomic in-place; untitled
 * → recovery dir), scratch-doc restore, menus.
 */
import { useEffect, useRef } from 'react';
import { useStore } from '../store/store';
import * as A from '../store/actions';
import { platform } from '../platform/api';
import { parseDoc, serializeDoc } from '../../shared/files/thalyxFile';
import { resetStore } from '../store/store';
import { parseMermaid } from '../mermaid/runtime';
import { isProbablyMermaid } from '../../shared/mermaid/detect';
import { newDoc } from '../../shared/model/create';

function docIdForSession(): string {
  // untitled scratch doc id, persisted across relaunches via prefs
  const KEY = 'thalyx:scratchDocId';
  let id = localStorage.getItem(KEY);
  if (!id) {
    id = Math.random().toString(36).slice(2, 10) + Math.random().toString(36).slice(2, 6);
    localStorage.setItem(KEY, id);
  }
  return id;
}

async function openPathIntoStore(path: string): Promise<void> {
  const text = await platform.file.read(path);
  if (/\.mmd$|\.mermaid$/i.test(path) || isProbablyMermaid(text)) {
    const ok = await A.importMermaidAsNew(text, parseMermaid);
    if (ok) {
      A.openFilePath(path);
      await platform.recents.add(path);
    }
    return;
  }
  const doc = parseDoc(text);
  resetStore(doc);
  A.openFilePath(path);
  await platform.recents.add(path);
}

export function useDocumentLifecycle(): void {
  const doc = useStore((s) => s.doc);
  const dirty = useStore((s) => s.session.dirtySinceSave);
  const filePath = useStore((s) => s.session.filePath);
  const timer = useRef<number | null>(null);
  const docRef = useRef(doc);
  const pathRef = useRef(filePath);
  const dirtyRef = useRef(dirty);
  useEffect(() => {
    docRef.current = doc;
    pathRef.current = filePath;
    dirtyRef.current = dirty;
  });

  // --- autosave (800 ms debounce, §12.4) ---------------------------------
  useEffect(() => {
    if (!dirty) return;
    if (timer.current !== null) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      const contents = serializeDoc(docRef.current);
      if (pathRef.current) {
        void platform.file.write(pathRef.current, contents).then(() => A.markSaved());
      } else {
        void platform.recovery.write(docIdForSession(), contents, null);
      }
    }, 800);
    return () => {
      if (timer.current !== null) window.clearTimeout(timer.current);
    };
  }, [doc, dirty]);

  // --- dirty/title/edited indicators -------------------------------------
  useEffect(() => {
    void platform.appx.setDocumentEdited(dirty);
    const name = filePath ? filePath.split(/[\\/]/).pop() : 'Untitled';
    void platform.appx.setTitle(`${dirty ? '• ' : ''}${name} — Thalyx`);
  }, [dirty, filePath]);

  // --- clear recovery for saved docs (§12.4) --------------------------------
  useEffect(() => {
    if (!dirty && filePath) {
      void platform.recovery.clear(docIdForSession());
    }
  }, [dirty, filePath]);

  // --- menu wiring ----------------------------------------------------------
  useEffect(() => {
    return platform.appx.onMenu(({ action, arg }) => {
      switch (action) {
        case 'undo':
          A.undo();
          break;
        case 'redo':
          A.redo();
          break;
        case 'delete':
          A.deleteSelection();
          break;
        case 'selectAll':
          A.selectAll();
          break;
        case 'cut':
          void navigator.clipboard?.writeText('');
          A.deleteSelection();
          break;
        case 'copy':
          {
            const s = useStore.getState().session.selection;
            void A.copySelectionInternal(s.nodeIds, s.edgeIds);
          }
          break;
        case 'paste':
          void A.pasteFromClipboard();
          break;
        case 'new':
          resetStore(newDoc());
          A.setFilePath(null);
          A.markSaved();
          break;
        case 'open':
          void (async () => {
            const path = await platform.dialog.openFile();
            if (path) await openPathIntoStore(path);
          })();
          break;
        case 'openRecent':
          if (typeof arg === 'string' && arg) void openPathIntoStore(arg);
          break;
        case 'save':
          void (async () => {
            const path = pathRef.current;
            const contents = serializeDoc(docRef.current);
            if (path) {
              await platform.file.write(path, contents);
              A.markSaved();
            } else {
              const target = await platform.dialog.saveFile('Untitled.thalyx', contents);
              if (target) {
                A.setFilePath(target);
                A.markSaved();
                await platform.recents.add(target);
              }
            }
          })();
          break;
        case 'saveAs':
          void (async () => {
            const contents = serializeDoc(docRef.current);
            const target = await platform.dialog.saveFile(
              (pathRef.current ?? 'Untitled.thalyx').split(/[\\/]/).pop() ?? 'Untitled.thalyx',
              contents,
            );
            if (target) {
              A.setFilePath(target);
              A.markSaved();
              await platform.recents.add(target);
            }
          })();
          break;
        case 'importMermaid':
          void (async () => {
            const path = await platform.dialog.openFile([
              { name: 'Mermaid', extensions: ['mmd', 'mermaid', 'txt'] },
            ]);
            if (!path) return;
            const text = await platform.file.read(path);
            const ok = await A.importMermaidAsNew(text, parseMermaid);
            if (ok) {
              A.setFilePath(null);
              A.setDirtySinceSave();
            }
          })();
          break;
        case 'print':
          void platform.exportx.print();
          break;
        case 'toggleGrid':
          A.toggleGrid();
          break;
        case 'toggleMermaidPanel': {
          const s = useStore.getState().session.mermaidPanelOpen;
          A.setMermaidPanelOpen(!s);
          break;
        }
        case 'help':
          A.setHelpOpen(true);
          break;
        case 'about':
          if (arg === 'github') {
            void platform.shellx.openExternal('https://github.com/L-K-M/Thalyx');
          }
          break;
        default:
          break;
      }
    });
  }, []);

  // --- open-file events (argv / open-file / second-instance / drag-drop) ----
  useEffect(() => {
    return platform.appx.onOpenFile((path) => {
      void openPathIntoStore(path);
    });
  }, []);

  // --- updater toast (§12.6): 'Restart to update' — never force ----------------------
  useEffect(() => {
    const api = (
      globalThis as unknown as {
        thalyx?: { updater?: { onUpdateReady(cb: () => void): () => void } };
      }
    ).thalyx;
    return (
      api?.updater?.onUpdateReady(() => {
        // simple confirm-style toast; quitAndInstall only on explicit click
        const el = document.createElement('div');
        el.className = 'thalyx-toast';
        el.innerHTML = '<span>Update ready — restart to install?</span>';
        const btn = document.createElement('button');
        btn.textContent = 'Restart';
        btn.onclick = () => {
          void (
            globalThis as unknown as { thalyx: { updater: { quitAndInstall(): Promise<void> } } }
          ).thalyx.updater.quitAndInstall();
        };
        const no = document.createElement('button');
        no.textContent = 'Later';
        no.onclick = () => el.remove();
        el.append(btn, no);
        document.body.append(el);
      }) ?? (() => undefined)
    );
  }, []);

  // --- scratch-doc restore on launch (§12.4) --------------------------------
  useEffect(() => {
    const off = platform.appx.onRecoveryScratch(async ({ contents }) => {
      try {
        const doc = parseDoc(contents);
        if (doc.nodes.length > 0) {
          resetStore(doc);
          A.setFilePath(null);
          A.markSaved();
        }
      } catch {
        // unreadable scratch — start fresh
      }
    });
    // browser-mode fallback: check localStorage recovery directly
    if (!platform.isElectron()) {
      void (async () => {
        const list = await platform.recovery.list();
        const scratch = list.find((e) => e.originalPath === null);
        if (scratch) {
          const contents = await platform.recovery.read(scratch.docId);
          try {
            const doc = parseDoc(contents);
            if (doc.nodes.length > 0) {
              resetStore(doc);
              A.openFilePath(null);
            }
          } catch {
            // ignore
          }
        }
      })();
    }
    return off;
  }, []);
}
