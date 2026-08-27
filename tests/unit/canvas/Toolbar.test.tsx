// @vitest-environment jsdom
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { Toolbar } from '../../../src/renderer/panels/Toolbar';
import { getStore, resetStore } from '../../../src/renderer/store/store';

(globalThis as Record<string, unknown>).IS_REACT_ACT_ENVIRONMENT = true;

const mediaQuery = {
  matches: false,
  media: '(prefers-color-scheme: dark)',
  onchange: null,
  addEventListener: () => undefined,
  removeEventListener: () => undefined,
  addListener: () => undefined,
  removeListener: () => undefined,
  dispatchEvent: () => true,
};

describe('Toolbar placement tools', () => {
  let host: HTMLDivElement;
  let root: ReturnType<typeof createRoot>;

  beforeEach(async () => {
    resetStore();
    window.matchMedia = () => mediaQuery;
    host = document.createElement('div');
    document.body.appendChild(host);
    root = createRoot(host);

    await act(async () => root.render(<Toolbar />));
  });

  afterEach(async () => {
    await act(async () => root.unmount());
    host.remove();
    resetStore();
  });

  it('shows the active text tool', async () => {
    const text = host.querySelector<HTMLButtonElement>('[title="Text (T)"]')!;

    await act(async () => text.click());

    expect(text.classList.contains('is-active')).toBe(true);
  });

  it('locks a repeated placement tool', async () => {
    const rectangle = host.querySelector<HTMLButtonElement>('[title="Rectangle (R)"]')!;

    await act(async () => rectangle.click());
    await act(async () => rectangle.click());

    expect(getStore().session.toolLocked).toBe(true);
    expect(rectangle.classList.contains('is-locked')).toBe(true);
  });

  it('locks a placement tool with Alt-click', async () => {
    const text = host.querySelector<HTMLButtonElement>('[title="Text (T)"]')!;

    await act(async () => {
      text.dispatchEvent(new MouseEvent('click', { bubbles: true, altKey: true }));
    });

    expect(getStore().session.toolLocked).toBe(true);
  });
});
