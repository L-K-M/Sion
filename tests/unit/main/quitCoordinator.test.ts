import { describe, expect, it } from 'vitest';
import { QuitCoordinator } from '../../../src/main/quitCoordinator';

describe('QuitCoordinator', () => {
  it('does not resume a quit that a failed window flush canceled', () => {
    const quit = new QuitCoordinator();
    quit.request();
    quit.cancel();

    expect(quit.beginResumeWhenEmpty(0)).toBe(false);
  });

  it('resumes a requested quit after every window closes', () => {
    const quit = new QuitCoordinator();
    quit.request();

    expect(quit.beginResumeWhenEmpty(1)).toBe(false);
    expect(quit.beginResumeWhenEmpty(0)).toBe(true);
    expect(quit.isResuming()).toBe(true);
  });
});
