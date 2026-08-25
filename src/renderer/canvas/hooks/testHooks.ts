/**
 * Test hooks (M2 e2e): `window.__thalyxTest.loadDoc(json)` injects a
 * serialized .thalyx document into the store, `getDocJson()` reads it back.
 *
 * Availability: the dev server always installs them; BUILT apps install them
 * only when the URL carries `?testHooks=1` — this is how the Playwright web
 * suite drives the production bundle (§15.2 requires testing the built
 * renderer). The hooks only load/read the document model — untrusted data
 * that restoreDocument() already treats defensively — and never touch the
 * preload bridge, so enabling them grants no additional capability.
 */
import { parseDoc } from '../../../shared/files/thalyxFile';
import { resetStore, useStore } from '../../store/store';
import * as A from '../../store/actions';

export function installTestHooks(): void {
  // Dev server, or the built app explicitly opted in via ?testHooks=1
  // (used by the Playwright web suite against vite preview of the prod build).
  const optedIn = new URLSearchParams(window.location.search).has('testHooks');
  if (!import.meta.env.DEV && !optedIn) return;
  (window as unknown as Record<string, unknown>).__thalyxTest = {
    // patchDoc receives PATCH SOURCE (Playwright cannot serialize function
    // arguments across the boundary) — compiled here, inside the page.
    patchDoc(patchSrc: string): void {
      // Arbitrary code execution — never expose in packaged builds.
      if (!import.meta.env.DEV) throw new Error('patchDoc is dev-only');
      // eslint-disable-next-line no-new-func
      const patch = new Function('d', patchSrc) as (d: unknown) => void;
      A.applyDocPatch((d) => {
        patch(d);
      });
    },
    loadDoc(json: string): boolean {
      try {
        resetStore(parseDoc(json));
        return true;
      } catch (err) {
        console.error('[thalyxTest] loadDoc failed', err);
        return false;
      }
    },
    selectNode(id: string): void {
      A.setSelection([id], []);
    },
    addNodeToSelection(id: string, reset: boolean): void {
      const s = useStore.getState().session.selection;
      const nodes = reset ? [id] : [...new Set([...s.nodeIds, id])];
      A.setSelection(nodes, []);
    },
    selectEdge(id: string): void {
      A.setSelection([], [id]);
    },
    getEditing(): string {
      return JSON.stringify(useStore.getState().session.editingLabel);
    },
    getDocJson(): string {
      return JSON.stringify(useStore.getState().doc);
    },
  };
}
