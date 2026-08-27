// @vitest-environment jsdom
import { afterEach, describe, expect, it } from 'vitest';
import { commitActiveInput } from '../../../src/renderer/files/commitActiveInput';

afterEach(() => {
  document.body.replaceChildren();
});

describe('commitActiveInput', () => {
  it('blurs the active editor before close snapshots the document', () => {
    const input = document.createElement('input');
    let committed = '';
    input.addEventListener('blur', () => {
      committed = input.value;
    });
    document.body.append(input);
    input.focus();
    input.value = 'latest draft';

    commitActiveInput(document);

    expect(committed).toBe('latest draft');
    expect(document.activeElement).not.toBe(input);
  });
});
