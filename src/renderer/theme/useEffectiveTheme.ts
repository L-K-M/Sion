/**
 * Theme resolution for the app shell: session.theme ('system'|'light'|'dark')
 * → the effective 'light' | 'dark', honoring prefers-color-scheme.
 */
import { useEffect, useState } from 'react';
import { useStore } from '../store/store';

function systemTheme(): 'light' | 'dark' {
  if (typeof window === 'undefined' || !window.matchMedia) return 'light';
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
}

export function useEffectiveTheme(): 'light' | 'dark' {
  const theme = useStore((s) => s.session.theme);
  const [sys, setSys] = useState<'light' | 'dark'>(systemTheme);

  useEffect(() => {
    if (theme !== 'system' || !window.matchMedia) return;
    const mq = window.matchMedia('(prefers-color-scheme: dark)');
    const onChange = (e: MediaQueryListEvent) => setSys(e.matches ? 'dark' : 'light');
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, [theme]);

  return theme === 'system' ? sys : theme;
}
