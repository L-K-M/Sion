/**
 * Theme resolution for the app shell: session.theme ('system'|'light'|'dark')
 * → the effective 'light' | 'dark', honoring prefers-color-scheme.
 *
 * The system theme is read via useSyncExternalStore — always fresh when
 * re-entering system mode, no cached value to go stale.
 */
import { useSyncExternalStore } from 'react';
import { useStore } from '../store/store';

function subscribeToSystemTheme(onChange: () => void): () => void {
  const mq = window.matchMedia('(prefers-color-scheme: dark)');
  mq.addEventListener('change', onChange);
  return () => mq.removeEventListener('change', onChange);
}

function systemThemeSnapshot(): 'light' | 'dark' {
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

function systemThemeServerSnapshot(): 'light' | 'dark' {
  return 'light';
}

export function useEffectiveTheme(): 'light' | 'dark' {
  const theme = useStore((s) => s.session.theme);
  const sys = useSyncExternalStore(
    subscribeToSystemTheme,
    systemThemeSnapshot,
    systemThemeServerSnapshot,
  );
  return theme === 'system' ? sys : theme;
}
