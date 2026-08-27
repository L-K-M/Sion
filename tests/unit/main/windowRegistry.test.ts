import { describe, expect, it } from 'vitest';
import { WindowRegistry } from '../../../src/main/windowRegistry';

interface FakeWindow {
  id: number;
  destroyed: boolean;
}

describe('WindowRegistry', () => {
  it('routes to the focused window, then the last active live window', () => {
    const registry = new WindowRegistry<FakeWindow>((window) => window.destroyed);
    const first = { id: 1, destroyed: false };
    const second = { id: 2, destroyed: false };
    registry.add(first);
    registry.add(second);
    registry.markActive(first);

    expect(registry.target(second)).toBe(second);
    expect(registry.target(null)).toBe(first);

    first.destroyed = true;
    expect(registry.target(null)).toBe(second);
  });

  it('removes a closed window without affecting other documents', () => {
    const registry = new WindowRegistry<FakeWindow>((window) => window.destroyed);
    const first = { id: 1, destroyed: false };
    const second = { id: 2, destroyed: false };
    registry.add(first);
    registry.add(second);
    registry.remove(first);

    expect(registry.all()).toEqual([second]);
    expect(registry.target(null)).toBe(second);
  });
});
