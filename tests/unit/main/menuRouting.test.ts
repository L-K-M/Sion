import { describe, expect, it, vi } from 'vitest';
import { routeMenuAction } from '../../../src/main/menuRouting';

describe('routeMenuAction', () => {
  it('opens recent files through the trusted main-process path', async () => {
    const openPath = vi.fn(async () => undefined);
    const send = vi.fn();

    await routeMenuAction('openRecent', '/tmp/recent.thalyx', openPath, send);

    expect(openPath).toHaveBeenCalledWith('/tmp/recent.thalyx');
    expect(send).not.toHaveBeenCalled();
  });

  it('forwards other menu actions to the renderer', async () => {
    const openPath = vi.fn(async () => undefined);
    const send = vi.fn();

    await routeMenuAction('undo', undefined, openPath, send);

    expect(send).toHaveBeenCalledWith('undo', undefined);
    expect(openPath).not.toHaveBeenCalled();
  });
});
