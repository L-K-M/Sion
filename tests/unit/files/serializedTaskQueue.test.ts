import { describe, expect, it, vi } from 'vitest';
import { SerializedTaskQueue } from '../../../src/renderer/files/serializedTaskQueue';

describe('SerializedTaskQueue', () => {
  it('starts the next task only after the previous task settles', async () => {
    let finishFirst: () => void = () => undefined;
    const firstDone = new Promise<void>((resolve) => {
      finishFirst = resolve;
    });
    const second = vi.fn(async () => undefined);
    const queue = new SerializedTaskQueue();

    const firstRun = queue.run(() => firstDone);
    const secondRun = queue.run(second);
    await Promise.resolve();

    expect(second).not.toHaveBeenCalled();
    finishFirst();
    await firstRun;
    await secondRun;
    expect(second).toHaveBeenCalledOnce();
  });

  it('continues after a failed task', async () => {
    const queue = new SerializedTaskQueue();
    const failed = queue.run(async () => Promise.reject(new Error('disk full')));
    const next = queue.run(async () => 'saved');

    await expect(failed).rejects.toThrow('disk full');
    await expect(next).resolves.toBe('saved');
  });
});
