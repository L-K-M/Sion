import { describe, expect, it } from 'vitest';
import { validateRecoveryWrite } from '../../../src/main/ipcValidation';

const MAX_CONTENT_BYTES = 50 * 1024 * 1024;

describe('validateRecoveryWrite', () => {
  it.each(['../escape', 'a/b', '', 'x'.repeat(65)])('rejects invalid doc id %j', (docId) => {
    expect(() => validateRecoveryWrite(docId, 'ok')).toThrow();
  });

  it('rejects content over the file limit', () => {
    expect(() => validateRecoveryWrite('valid-id', 'x'.repeat(MAX_CONTENT_BYTES + 1))).toThrow(
      'content too large',
    );
  });

  it('accepts a bounded recovery payload', () => {
    expect(() => validateRecoveryWrite('valid_id-1', 'contents')).not.toThrow();
  });
});
