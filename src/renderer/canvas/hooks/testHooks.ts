/**
 * Dev/test-only hooks (M2 e2e): `window.__thalyxTest.loadDoc(json)` injects a
 * serialized .thalyx document into the store. Stripped from production builds
 * by Vite dead-code elimination (import.meta.env.DEV guard).
 */
import { parseDoc } from '../../../shared/files/thalyxFile';
import { resetStore, useStore } from '../../store/store';

export function installTestHooks(): void {
  // Dev server, or the built app explicitly opted in via ?testHooks=1
  // (used by the Playwright web suite against vite preview of the prod build).
  const optedIn = new URLSearchParams(window.location.search).has('testHooks');
  if (!import.meta.env.DEV && !optedIn) return;
  (window as unknown as Record<string, unknown>).__thalyxTest = {
    loadDoc(json: string): boolean {
      try {
        resetStore(parseDoc(json));
        return true;
      } catch (err) {
        console.error('[thalyxTest] loadDoc failed', err);
        return false;
      }
    },
    getDocJson(): string {
      return JSON.stringify(useStore.getState().doc);
    },
  };
}
