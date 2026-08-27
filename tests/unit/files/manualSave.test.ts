// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest';
import { runManualSave, showManualSaveFailure } from '../../../src/renderer/files/manualSave';

afterEach(() => {
  document.body.replaceChildren();
});

describe('manual document save', () => {
  it('commits the active editor before reading the save snapshot', async () => {
    const input = document.createElement('input');
    let committed = '';
    let saved = '';
    input.addEventListener('blur', () => {
      committed = input.value;
    });
    document.body.append(input);
    input.focus();
    input.value = 'latest draft';

    await runManualSave(document, async () => {
      saved = committed;
    });

    expect(saved).toBe('latest draft');
  });

  it('shows an actionable ownership conflict', () => {
    showManualSaveFailure(document, new Error('document is already open in another window'));

    const alert = document.querySelector<HTMLElement>('[data-save-failure]');
    expect(alert?.getAttribute('role')).toBe('alert');
    expect(alert?.textContent).toContain('open in another window');

    alert?.querySelector<HTMLButtonElement>('button')?.click();
    expect(document.querySelector('[data-save-failure]')).toBeNull();
  });
});
