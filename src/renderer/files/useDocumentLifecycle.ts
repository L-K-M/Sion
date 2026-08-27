/** Document bootstrap, save, recovery, menu, and close coordination. */
import { useCallback, useEffect, useRef, useState } from 'react';
import { useReactFlow } from '@xyflow/react';
import { useStore, resetStore } from '../store/store';
import * as A from '../store/actions';
import { platform } from '../platform/api';
import { parseDoc, serializeDoc } from '../../shared/files/thalyxFile';
import { parseMermaid } from '../mermaid/runtime';
import { associatedPathForOpen } from './documentAssociation';
import { commitActiveInput } from './commitActiveInput';
import { clearManualSaveFailure, runManualSave, showManualSaveFailure } from './manualSave';
import { newDoc } from '../../shared/model/create';
import { isCompletedSaveCurrent } from './saveGuard';
import { SerializedTaskQueue } from './serializedTaskQueue';
import { SaveDialogPurpose } from '../../shared/saveDialog';
import type { WindowBootstrap } from '../../shared/windowBootstrap';
import {
  fitCanvas,
  fitSelection,
  resetCanvasZoom,
  zoomCanvasIn,
  zoomCanvasOut,
} from '../canvas/viewportActions';

const AUTOSAVE_DELAY_MS = 800;

enum ManualSaveMode {
  CurrentOrPrompt = 'current-or-prompt',
  SaveAs = 'save-as',
}

enum SnapshotWriteReason {
  Autosave = 'autosave',
  Close = 'close',
}

export enum DocumentLifecyclePhase {
  Loading = 'loading',
  Ready = 'ready',
  Closing = 'closing',
  Error = 'error',
}

async function openPathIntoStore(path: string): Promise<WindowBootstrap | null> {
  const text = await platform.file.read(path);
  if (associatedPathForOpen(path, text) === null) {
    const ok = await A.importMermaidAsNew(text, parseMermaid);
    if (!ok) return null;

    const bootstrap = await platform.appx.setAssociatedPath(null);
    A.setFilePath(null);
    await platform.recents.add(path);
    return bootstrap;
  }

  const parsed = parseDoc(text);
  const bootstrap = await platform.appx.setAssociatedPath(path);
  resetStore(parsed);
  A.openFilePath(path);
  await platform.recents.add(path);
  return bootstrap;
}

function showUpdateToast(): void {
  if (document.querySelector('.thalyx-toast[data-update-toast]')) return;

  const toast = document.createElement('div');
  toast.className = 'thalyx-toast';
  toast.setAttribute('data-update-toast', '1');
  toast.setAttribute('role', 'status');
  toast.innerHTML = '<span>Update ready — restart to install?</span>';

  const restart = document.createElement('button');
  restart.textContent = 'Restart';
  restart.onclick = () => {
    void (
      globalThis as unknown as { thalyx: { updater: { quitAndInstall(): Promise<void> } } }
    ).thalyx.updater.quitAndInstall();
  };

  const later = document.createElement('button');
  later.textContent = 'Later';
  later.onclick = () => toast.remove();

  toast.append(restart, later);
  document.body.append(toast);
}

function markSavedIfCurrent(savedContents: string, savedPath: string): boolean {
  const state = useStore.getState();
  const currentContents = serializeDoc(state.doc);
  if (!isCompletedSaveCurrent(savedContents, savedPath, currentContents, state.session.filePath)) {
    return false;
  }

  A.markSaved();
  return true;
}

function freezeDocumentInput(): () => void {
  commitActiveInput(document);
  const root = document.documentElement;
  const wasInert = root.inert;
  root.inert = true;
  root.dataset['closing'] = 'true';

  return () => {
    root.inert = wasInert;
    delete root.dataset['closing'];
  };
}

export function useDocumentLifecycle(): DocumentLifecyclePhase {
  const reactFlow = useReactFlow();
  const doc = useStore((state) => state.doc);
  const dirty = useStore((state) => state.session.dirtySinceSave);
  const filePath = useStore((state) => state.session.filePath);
  const timer = useRef<number | null>(null);
  const scratchIdRef = useRef<string | null>(null);
  const writeQueue = useRef(new SerializedTaskQueue());
  const [phase, setPhase] = useState(DocumentLifecyclePhase.Loading);

  const clearScratchRecovery = useCallback(async () => {
    const scratchId = scratchIdRef.current;
    if (!scratchId) return;

    await platform.recovery.clear(scratchId);
  }, []);

  const writeCurrentSnapshot = useCallback(
    async (reason: SnapshotWriteReason): Promise<void> => {
      const state = useStore.getState();
      const targetPath = state.session.filePath;
      if (!state.session.dirtySinceSave) {
        if (targetPath) await clearScratchRecovery();
        return;
      }

      const contents = serializeDoc(state.doc);
      if (!targetPath) {
        const scratchId = scratchIdRef.current;
        if (!scratchId) throw new Error('document recovery identity unavailable');

        await platform.recovery.write(scratchId, contents, null);
        return;
      }

      await platform.file.write(targetPath, contents);
      if (reason === SnapshotWriteReason.Close) {
        await clearScratchRecovery();
        return;
      }

      if (markSavedIfCurrent(contents, targetPath)) await clearScratchRecovery();
    },
    [clearScratchRecovery],
  );

  const saveDocument = useCallback(
    async (mode: ManualSaveMode): Promise<void> => {
      clearManualSaveFailure(document);
      await runManualSave(document, async () => {
        await writeQueue.current.run(async () => {
          const state = useStore.getState();
          const contents = serializeDoc(state.doc);
          let targetPath = mode === ManualSaveMode.SaveAs ? null : state.session.filePath;

          if (targetPath) {
            await platform.file.write(targetPath, contents);
          } else {
            const defaultName =
              (state.session.filePath ?? 'Untitled.thalyx').split(/[\\/]/).pop() ??
              'Untitled.thalyx';
            targetPath = await platform.dialog.saveFile(
              defaultName,
              contents,
              undefined,
              SaveDialogPurpose.Document,
            );
            if (!targetPath) return;

            const bootstrap = await platform.appx.setAssociatedPath(targetPath);
            scratchIdRef.current = bootstrap.scratchId;
            A.setFilePath(targetPath);
            await platform.recents.add(targetPath);
          }

          if (markSavedIfCurrent(contents, targetPath)) await clearScratchRecovery();
        });
      });
    },
    [clearScratchRecovery],
  );

  // Bootstrap is sender-scoped and replayable after a renderer reload.
  useEffect(() => {
    let cancelled = false;

    void (async () => {
      try {
        const bootstrap = await platform.appx.bootstrap();
        if (cancelled) return;

        scratchIdRef.current = bootstrap.scratchId;
        if (bootstrap.updateReady) showUpdateToast();
        if (bootstrap.openPath) {
          const association = await openPathIntoStore(bootstrap.openPath);
          if (!association) throw new Error('document import failed');

          scratchIdRef.current = association.scratchId;
          if (!cancelled) setPhase(DocumentLifecyclePhase.Ready);
          return;
        }

        let recovery = bootstrap.recovery;
        if (!platform.isElectron() && !recovery) {
          const entry = (await platform.recovery.list()).find((item) => item.originalPath === null);
          if (entry) {
            recovery = { docId: entry.docId, contents: await platform.recovery.read(entry.docId) };
            scratchIdRef.current = entry.docId;
          }
        }
        if (recovery) {
          resetStore(parseDoc(recovery.contents));
          A.openFilePath(null);
        }

        if (!cancelled) setPhase(DocumentLifecyclePhase.Ready);
      } catch (error) {
        console.error('[bootstrap] document restore failed', { error });
        if (!cancelled) setPhase(DocumentLifecyclePhase.Error);
      }
    })();

    return () => {
      cancelled = true;
    };
  }, []);

  // Autosave snapshots when its queued task starts, after prior target changes.
  useEffect(() => {
    if (!dirty || phase !== DocumentLifecyclePhase.Ready || !scratchIdRef.current) return;
    if (timer.current !== null) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      timer.current = null;
      void writeQueue.current
        .run(() => writeCurrentSnapshot(SnapshotWriteReason.Autosave))
        .catch((error: unknown) => {
          console.error('[autosave] write failed', { error });
        });
    }, AUTOSAVE_DELAY_MS);

    return () => {
      if (timer.current !== null) window.clearTimeout(timer.current);
    };
  }, [dirty, doc, filePath, phase, writeCurrentSnapshot]);

  // Freeze the editor, then flush the latest state after earlier saves settle.
  useEffect(() => {
    return platform.appx.onBeforeClose(async () => {
      if (timer.current !== null) {
        window.clearTimeout(timer.current);
        timer.current = null;
      }

      const releaseInput = freezeDocumentInput();
      setPhase(DocumentLifecyclePhase.Closing);
      try {
        await writeQueue.current.run(() => writeCurrentSnapshot(SnapshotWriteReason.Close));
      } catch (error) {
        releaseInput();
        setPhase(DocumentLifecyclePhase.Ready);
        throw error;
      }
    });
  }, [writeCurrentSnapshot]);

  useEffect(() => {
    void platform.appx.setDocumentEdited(dirty);
    const name = filePath ? filePath.split(/[\\/]/).pop() : 'Untitled';
    void platform.appx.setTitle(`${dirty ? '• ' : ''}${name} — Thalyx`);
  }, [dirty, filePath]);

  useEffect(() => {
    if (phase !== DocumentLifecyclePhase.Ready) return;

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
        case 'cut': {
          const selection = useStore.getState().session.selection;
          void A.cutSelectionInternal(selection.nodeIds, selection.edgeIds);
          break;
        }
        case 'copy': {
          const selection = useStore.getState().session.selection;
          void A.copySelectionInternal(selection.nodeIds, selection.edgeIds);
          break;
        }
        case 'paste':
          void A.pasteFromClipboard();
          break;
        case 'new':
          resetStore(newDoc());
          void platform.appx.setAssociatedPath(null).then((bootstrap) => {
            scratchIdRef.current = bootstrap.scratchId;
          });
          A.setFilePath(null);
          A.markSaved();
          break;
        case 'open':
          void (async () => {
            const path = await platform.dialog.openFile();
            if (!path) return;

            const bootstrap = await openPathIntoStore(path);
            if (bootstrap) scratchIdRef.current = bootstrap.scratchId;
          })();
          break;
        case 'openRecent':
          if (typeof arg === 'string' && arg) {
            void openPathIntoStore(arg).then((bootstrap) => {
              if (bootstrap) scratchIdRef.current = bootstrap.scratchId;
            });
          }
          break;
        case 'save':
          void saveDocument(ManualSaveMode.CurrentOrPrompt).catch((error: unknown) => {
            console.error('[save] failed', { error });
            showManualSaveFailure(document, error);
          });
          break;
        case 'saveAs':
          void saveDocument(ManualSaveMode.SaveAs).catch((error: unknown) => {
            console.error('[save-as] failed', { error });
            showManualSaveFailure(document, error);
          });
          break;
        case 'importMermaid':
          void (async () => {
            const path = await platform.dialog.openFile([
              { name: 'Mermaid', extensions: ['mmd', 'mermaid', 'txt'] },
            ]);
            if (!path) return;

            const text = await platform.file.read(path);
            const ok = await A.importMermaidAsNew(text, parseMermaid);
            if (!ok) return;

            const bootstrap = await platform.appx.setAssociatedPath(null);
            scratchIdRef.current = bootstrap.scratchId;
            A.setFilePath(null);
            A.setDirtySinceSave();
          })();
          break;
        case 'export':
          A.setExportDialogOpen(true);
          break;
        case 'print':
          void platform.exportx.print();
          break;
        case 'zoomIn':
          zoomCanvasIn(reactFlow);
          break;
        case 'zoomOut':
          zoomCanvasOut(reactFlow);
          break;
        case 'zoomReset':
          resetCanvasZoom(reactFlow);
          break;
        case 'zoomFit':
          fitCanvas(reactFlow);
          break;
        case 'zoomSelection':
          fitSelection(reactFlow, useStore.getState().session.selection.nodeIds);
          break;
        case 'toggleGrid':
          A.toggleGrid();
          break;
        case 'toggleMermaidPanel': {
          const open = useStore.getState().session.mermaidPanelOpen;
          A.setMermaidPanelOpen(!open);
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
  }, [phase, reactFlow, saveDocument]);

  useEffect(() => {
    if (phase !== DocumentLifecyclePhase.Ready) return;

    return platform.appx.onOpenFile((path) => {
      void openPathIntoStore(path).then((bootstrap) => {
        if (bootstrap) scratchIdRef.current = bootstrap.scratchId;
      });
    });
  }, [phase]);

  useEffect(() => {
    const api = (
      globalThis as unknown as {
        thalyx?: { updater?: { onUpdateReady(cb: () => void): () => void } };
      }
    ).thalyx;
    return api?.updater?.onUpdateReady(showUpdateToast) ?? (() => undefined);
  }, []);

  return phase;
}
