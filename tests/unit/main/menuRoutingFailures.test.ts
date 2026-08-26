import { describe, expect, it, vi } from 'vitest';
import { routeMenuAction } from '../../../src/main/menuRouting';

describe('routeMenuAction failures', () => {
  it('contains recent-file failures', async () => {
    const openPath = vi.fn(async () => Promise.reject(new Error('ENOENT')));
    const send = vi.fn();
    const error = vi.spyOn(console, 'error').mockImplementation(() => undefined);

    await expect(
      routeMenuAction('openRecent', '/tmp/missing.thalyx', openPath, send),
    ).resolves.toBeUndefined();

    expect(send).not.toHaveBeenCalled();
    expect(error).toHaveBeenCalledOnce();
    error.mockRestore();
  });

  it('does not forward malformed recent-file actions', async () => {
    const openPath = vi.fn(async () => undefined);
    const send = vi.fn();

    await routeMenuAction('openRecent', undefined, openPath, send);

    expect(openPath).not.toHaveBeenCalled();
    expect(send).not.toHaveBeenCalled();
  });
});
